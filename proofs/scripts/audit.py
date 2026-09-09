#!/usr/bin/env python3
"""Fail-closed wrapper for Lean's #print axioms output; no third-party Python dependency."""

import argparse
from pathlib import Path
import re
import subprocess
import sys

ALLOWED = {"propext", "Classical.choice", "Quot.sound"}
RESULT = re.compile(
    r"'([^']+)' (?:does not depend on any axioms|depends on axioms:\s*\[([^\]]*)\])",
    re.MULTILINE,
)

def lean_code(source: str) -> str:
    result = []
    i = depth = 0
    while i < len(source):
        if source.startswith("/-", i):
            depth += 1
            i += 2
        elif depth and source.startswith("-/", i):
            depth -= 1
            i += 2
        elif depth:
            i += 1
        elif source.startswith("--", i):
            end = source.find("\n", i)
            i = len(source) if end == -1 else end
        elif source[i] == '"':
            i += 1
            while i < len(source) and source[i] != '"':
                i += 2 if source[i] == "\\" else 1
            if i == len(source):
                raise ValueError("unterminated string in source scan")
            i += 1
            result.append(" ")
        else:
            result.append(source[i])
            i += 1
    if depth:
        raise ValueError("unterminated comment in source scan")
    return "".join(result)


def scan_sources() -> None:
    if Path("InfluenceDiagramsProofs.lean").exists():
        roots = [(Path("."), "InfluenceDiagramsProofs"),
                 (Path("../../BayesianNetworks.jl/proofs"), "BayesianNetworksProofs")]
    else:
        roots = [(Path("."), "BayesianNetworksProofs")]
    for root, library in roots:
        if not (root / library).is_dir():
            raise ValueError(f"missing proof library: {root / library}")
        paths = [root / "Audit.lean", root / "Main.lean", root / f"{library}.lean"]
        paths += sorted((root / library).rglob("*.lean"))
        for path in paths:
            code = lean_code(path.read_text())
            forbidden = re.search(
                r"\b(?:sorry|admit|axiom|unsafe|native_decide|implemented_by|extern|run_tac)\b"
                r"|#eval|\bdecide\s+\+native\b|^\s*import\s+Mathlib\s*$", code, re.MULTILINE)
            if forbidden:
                raise ValueError(f"forbidden source construct in {path}: {forbidden.group()}")


def validate(source: str, output: str) -> None:
    requested = re.findall(r"^#print axioms\s+(\S+)\s*$", source, re.MULTILINE)
    results = list(RESULT.finditer(output))
    if not requested or len(requested) != len(results):
        raise ValueError("missing, duplicate, or unexpected audit results")
    if RESULT.sub("", output).strip():
        raise ValueError("unexpected output, warnings, or errors in axiom audit")
    for expected, result in zip(requested, results):
        name, raw = result.groups()
        if name != expected and not name.endswith("." + expected):
            raise ValueError(f"audit order/name mismatch: expected {expected}, got {name}")
        axioms = set() if raw is None or not raw.strip() else {a.strip() for a in raw.split(",")}
        if axioms - ALLOWED:
            raise ValueError(f"{name} uses forbidden axioms: {sorted(axioms - ALLOWED)}")


def self_test() -> None:
    source = "#print axioms Good\n"
    validate(source, "'Example.Good' depends on axioms: [propext,\n Classical.choice, Quot.sound]\n")
    validate(source, "'Good' does not depend on any axioms\n")
    bad = [
        "",
        "'Good' depends on axioms: [sorryAx]\n",
        "'Good' depends on axioms: [UnexpectedAssumption]\n",
        "'Other' does not depend on any axioms\n",
        "'Good' does not depend on any axioms\nwarning: ignored\n",
        "'Good' does not depend on any axioms\n'Good' does not depend on any axioms\n",
    ]
    for output in bad:
        try:
            validate(source, output)
        except ValueError:
            continue
        raise AssertionError("fail-closed audit accepted an invalid fixture")
    print("Audit parser self-test passed (all rejection cases rejected).")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("log", nargs="?")
    parser.add_argument("--file", default="Audit.lean")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    path = Path(args.file)
    try:
        scan_sources()
        if args.log:
            output = Path(args.log).read_text()
        else:
            result = subprocess.run(["lake", "env", "lean", str(path)], capture_output=True, text=True)
            sys.stdout.write(result.stdout)
            sys.stderr.write(result.stderr)
            if result.returncode:
                return result.returncode
            if result.stderr.strip():
                raise ValueError("unexpected stderr in axiom audit")
            output = result.stdout
        validate(path.read_text(), output)
    except ValueError as error:
        print(f"AXIOM AUDIT FAILED: {error}", file=sys.stderr)
        return 1
    print("Axiom allowlist and source scan verified; every requested result was present.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
