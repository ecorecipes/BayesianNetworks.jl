#!/usr/bin/env python3
"""Translate an explicit finite-BN certificate to literal Lean data and kernel-check it.

The translation is inspectable, not assumed verified. Success concerns the emitted literal
data; its structural/reference/normalization facts are proved by `decide +kernel`.
"""

import argparse
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys
from audit import validate


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key {key!r}")
        result[key] = value
    return result


def quoted(value):
    if not isinstance(value, str) or any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise ValueError("names must be strings without control characters")
    return json.dumps(value, ensure_ascii=False)


def nat(value):
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ValueError(f"expected a natural number, got {value!r}")
    return value


def index(value, size):
    value = nat(value)
    if not 1 <= value <= size:
        raise ValueError(f"one-based index {value} outside 1..{size}")
    return f"⟨{value - 1}, by decide⟩"


def position(value):
    value = nat(value)
    if value == 0:
        raise ValueError("positions are one-based and must be positive")
    return str(value - 1)


def ref(value):
    kind = value["kind"]
    if kind in {"named", "policy"}:
        return f"Raw.Ref.{kind} {quoted(value['key'])}"
    if kind == "point_mass":
        return f"Raw.Ref.pointMass {quoted(value['state'])}"
    if kind == "none":
        return "Raw.Ref.none"
    raise ValueError(f"unknown reference kind {kind!r}")


def array_function(rows, row_type):
    return f"fun i => (#[{', '.join(rows)}] : Array ({row_type}))[i]"


def lean_list(values):
    return "[" + ", ".join(values) + "]"


def render(data, digest):
    if data.get("version") != "finite-bn-certificate-1":
        raise ValueError("unsupported certificate version")
    variables, states = data["variables"], data["states"]
    mechanisms, inputs = data["mechanisms"], data["inputs"]
    nv, ns, nm, ni = map(len, [variables, states, mechanisms, inputs])
    order = [nat(v) for v in data["topological_order"]]
    if sorted(order) != list(range(1, nv + 1)):
        raise ValueError("topological_order must be a permutation of variable IDs")
    ranks = [order.index(v + 1) for v in range(nv)]
    vs = [f"⟨{quoted(v['name'])}, {ref(v['space_ref'])}⟩" for v in variables]
    ss = [f"⟨{index(s['variable'], nv)}, {position(s['position'])}, {quoted(s['name'])}⟩" for s in states]
    ms = [f"⟨{index(m['target'], nv)}, {quoted(m['name'])}, {ref(m['kernel_ref'])}⟩" for m in mechanisms]
    ins = [f"⟨{index(i['mechanism'], nm)}, {index(i['variable'], nv)}, {position(i['position'])}⟩" for i in inputs]
    bindings = []
    normalized = {}
    for b in data["bindings"]:
        if b["kind"] not in {"named", "policy"}:
            raise ValueError("bindings may only be named or policy references")
        axes = b["input_states"]
        outputs = b["output_states"]
        if len(b["columns"]) != math.prod(len(a) for a in axes):
            raise ValueError("column count does not match the declared parent-slot dimensions")
        columns = []
        row_normalized = True
        for c in b["columns"]:
            if len(c["parents"]) != len(axes) or any(
                not 1 <= nat(a) <= len(labels) for a, labels in zip(c["parents"], axes)
            ):
                raise ValueError("parent coordinate is outside the declared slot dimensions")
            if len(c["weights"]) != len(outputs):
                raise ValueError("weight count does not match the output state count")
            coordinates = lean_list([position(i) for i in c["parents"]])
            weights = []
            values = []
            for w in c["weights"]:
                if not isinstance(w["num"], str) or not re.fullmatch(r"-?[0-9]+", w["num"]):
                    raise ValueError("rational numerator must be an integer decimal string")
                if not isinstance(w["den"], str) or not re.fullmatch(r"[0-9]+", w["den"]):
                    raise ValueError("rational denominator must be a positive decimal string")
                num, den = int(w["num"]), int(w["den"])
                if den <= 0:
                    raise ValueError("rational denominators must be positive")
                values.append(Fraction(num, den))
                weights.append(f"({num} : ℚ) / {den}")
            row_normalized &= sum(values) == 1
            columns.append(f"⟨{coordinates}, {lean_list(weights)}⟩")
        normalized[(b["kind"], b["key"])] = row_normalized
        table = ("{ inputSizes := " + lean_list([str(len(a)) for a in axes]) +
                 f", outputSize := {len(outputs)}, columns := " + lean_list(columns) +
                 ", inputLabels := " + lean_list([lean_list([quoted(s) for s in a]) for a in axes]) +
                 ", outputLabels := " + lean_list([quoted(s) for s in outputs]) + " }")
        bindings.append(f"⟨{ref(b)}, {table}⟩")
    norm = all(normalized.get((m["kernel_ref"]["kind"], m["kernel_ref"].get("key")), True)
               for m in mechanisms)
    observations = [
        f"({index(e['variable'], nv)}, {position(e['state_position'])})"
        for e in data.get("evidence", [])
    ]
    namespace = "Certificate_" + digest[:16]
    code = f"""import BayesianNetworksProofs.Finite.ReferenceTables
open BayesianNetworksProofs BayesianNetworksProofs.FinBayesNet
namespace {namespace}
def network : Raw.Network where
  nv := {nv}
  ns := {ns}
  nm := {nm}
  ni := {ni}
  vars := {array_function(vs, "Raw.VariableRow")}
  states := {array_function(ss, f"Raw.StateRow {nv}")}
  mechanisms := {array_function(ms, f"Raw.MechanismRow {nv}")}
  inputs := {array_function(ins, f"Raw.InputRow {nv} {nm}")}
  rank := {array_function([f"⟨{i}, by decide⟩" for i in ranks], f"Fin {nv}")}
def bank : Raw.Bank := {lean_list(bindings)}
def observations : List (Fin {nv} × Nat) := {lean_list(observations)}
theorem structural_checked : network.check = true := by decide +kernel
theorem references_checked : network.checkReady bank = true := by decide +kernel
theorem normalization_checked : network.checkNormalized bank = {str(norm).lower()} := by decide +kernel
theorem evidence_bounds : ∀ e ∈ observations, e.2 < network.stateCount e.1 := by decide +kernel
theorem evidence_unique : (observations.map Prod.fst).Nodup := by decide +kernel
#print axioms structural_checked
#print axioms references_checked
#print axioms normalization_checked
#print axioms evidence_bounds
#print axioms evidence_unique
end {namespace}
"""
    if norm:
        code += f"""
namespace {namespace}
noncomputable def valid : network.Valid := network.check_iff.mp structural_checked
theorem compiled_probability :
    ∑ x, joint (network.kernel valid (network.resolvedCPT valid bank)) x = 1 :=
  network.checked_reference_normalization bank structural_checked references_checked normalization_checked
#print axioms compiled_probability
end {namespace}
"""
    return code, norm


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input")
    parser.add_argument("--output", required=True)
    parser.add_argument("--require-normalized", action="store_true")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    inp, output = Path(args.input), Path(args.output)
    if output.exists() and not args.force:
        raise ValueError("output exists; choose another file or pass --force")
    raw = inp.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    code, normalized = render(json.loads(raw, object_pairs_hook=unique_object), digest)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(code)
    proof_root = Path(__file__).resolve().parents[1]
    result = subprocess.run(["lake", "env", "lean", str(output.resolve())], cwd=proof_root,
                            capture_output=True, text=True)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    if result.returncode:
        return result.returncode
    if result.stderr.strip():
        raise ValueError("unexpected stderr during certificate proof checking")
    validate(code, result.stdout)
    if args.require_normalized and not normalized:
        print("Exact normalization is false; no renormalization was performed.", file=sys.stderr)
        return 2
    print(f"Kernel-checked literal certificate; input SHA256 {digest}; normalized={normalized}.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"Certificate error: {error}", file=sys.stderr)
        raise SystemExit(2)
