/-
`lake exe emit_schema [--check] [--dir DIR]`

Writes the ACSets.jl schema JSON for the three schemas of `BayesianNetworks.jl` into
`DIR` (default `schemas/`, relative to the current directory, i.e. `proofs/schemas/` when run
from `proofs/`). With `--check`, nothing is written: the process exits with status 1 if any
file is missing or differs from what would be emitted.
-/
import BayesianNetworksProofs.Schema.BayesNet

open BayesianNetworksProofs

/-- File stem ↦ schema. -/
def schemas : List (String × SchemaDesc) :=
  [ ("variable_space", schVariableSpace)
  , ("bayesnet", schBayesNet)
  , ("influence_diagram", schInfluenceDiagram) ]

structure Options where
  check : Bool := false
  dir : System.FilePath := "schemas"

partial def parseArgs : List String → Options → Except String Options
  | [], o => .ok o
  | "--check" :: rest, o => parseArgs rest { o with check := true }
  | "--dir" :: d :: rest, o => parseArgs rest { o with dir := d }
  | arg :: _, _ => .error s!"unknown argument: {arg}"

def main (args : List String) : IO UInt32 := do
  let opts ← match parseArgs args {} with
    | .ok o => pure o
    | .error e =>
      IO.eprintln s!"emit_schema: {e}\nusage: emit_schema [--check] [--dir DIR]"
      return 2
  let mut failures : List String := []
  if !opts.check then IO.FS.createDirAll opts.dir
  for (stem, S) in schemas do
    let path := opts.dir / s!"{stem}.schema.json"
    let expected := S.toACSetsJsonString
    if opts.check then
      if ← path.pathExists then
        let actual ← IO.FS.readFile path
        if actual == expected then
          IO.println s!"ok       {path}"
        else
          IO.println s!"DIFFERS  {path}"
          failures := failures ++ [path.toString]
      else
        IO.println s!"MISSING  {path}"
        failures := failures ++ [path.toString]
    else
      IO.FS.writeFile path expected
      IO.println s!"wrote    {path}"
  if failures.isEmpty then
    return 0
  else
    IO.eprintln s!"emit_schema --check: {failures.length} file(s) out of date; run `lake exe emit_schema`"
    return 1
