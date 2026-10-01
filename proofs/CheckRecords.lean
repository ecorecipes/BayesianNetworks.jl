/-
`lake exe check_records FILE.json`

Reads a document written by BayesianNetworks.jl's `write_json_bayesnet`, parses it with
`Lean.Json.parse`, decodes it with the proved decoder `Raw.decodeChecked`
(`BayesianNetworksProofs/Finite/JsonRecords.lean`) and prints a canonical summary:

    format: bayesnet-acset
    valid: yes
    variables: <n>
    states <variable>: <label at position 1>, <label at position 2>, ...
    parents <target variable>: <slot 1 variable>, <slot 2 variable>, ...
    mechanism <mechanism name>: <target variable>
    topological: <variable>, <variable>, ...
    acyclic: yes

`states` lines list `Tables.labelAt`, which `Network.labelAt_eq` proves to be the labels of the
compiled state space in position order; `parents` lines list `Tables.slotAt`, which
`Network.slotAt_eq` proves to be the compiled slot variables in `input_position` order. The
topological line is the placement order behind the computed rank. A document that does not decode
prints `error: <message>` and exits with status 1; one that decodes but fails `Network.check`
prints `valid: no` and exits with status 1.

The parse (`Lean.Json.parse`) and this printing code are trusted, not proved.
-/
import BayesianNetworksProofs.Finite.JsonRecords
import Lean.Data.Json.Parser

open BayesianNetworksProofs.Raw

def joinLabels (xs : List String) : String := ", ".intercalate xs

/-- The summary lines of a checked network. -/
def summary (r : Network) (_h : r.Valid) : List String := Id.run do
  let t := r.tables
  let name (v : Fin r.nv) : String := (r.vars v).name
  let mut out : List String := ["format: bayesnet-acset", "valid: yes", s!"variables: {r.nv}"]
  for v in List.finRange r.nv do
    let labels := (List.range (r.stateCount v)).map fun a => (t.labelAt v a).getD "?"
    out := out ++ [s!"states {name v}: {joinLabels labels}"]
  for m in List.finRange r.nm do
    let slots := (List.range (r.inputCount m)).map fun j =>
      match t.slotAt m j with
      | some v => name v
      | none => "?"
    out := out ++ [s!"parents {name (r.mechanisms m).target}: {joinLabels slots}"]
  for m in List.finRange r.nm do
    out := out ++ [s!"mechanism {(r.mechanisms m).name}: {name (r.mechanisms m).target}"]
  match t.order with
  | some l => out := out ++ [s!"topological: {joinLabels (l.map name)}"]
  | none => out := out ++ ["topological: ?"]
  out := out ++ ["acyclic: yes"]
  return out

def main (args : List String) : IO UInt32 := do
  match args with
  | [path] =>
    let text ← IO.FS.readFile path
    match Lean.Json.parse text with
    | .error e =>
      IO.println s!"error: not JSON: {e}"
      return 1
    | .ok j =>
      match decode j with
      | .error e =>
        IO.println s!"error: {e}"
        return 1
      | .ok r =>
        match decodeChecked j with
        | some ⟨r', h⟩ =>
          for line in summary r' h do
            IO.println line
          return 0
        | none =>
          IO.println "format: bayesnet-acset"
          IO.println "valid: no"
          IO.println s!"variables: {r.nv}"
          return 1
  | _ =>
    IO.eprintln "usage: check_records FILE.json"
    return 2
