import Lean.Data.Json

/-!
# BayesianNetworksProofs.Schema.Desc

**Schema descriptions** — a small, Mathlib-free data type describing the *presentation* of an
ACSet schema (objects, homs, attribute types, attributes), together with the decidable
well-formedness / inclusion / "no outgoing arrow" predicates that the Julia layer relies on and
the JSON writer that reproduces ACSets.jl's `generate_json_acset_schema` format.

The Lean terms here and the `@present` schemas in `BayesianNetworks.jl` are two independent
hand-written definitions, checked to agree rather than generated from one another:
`lake exe emit_schema` writes `proofs/schemas/*.schema.json` from the terms in
`BayesianNetworksProofs.Schema.BayesNet`, and a Julia test asserts that the `@present` schema
matches (ADR 0005).

This module deliberately imports only `Lean.Data.Json` so that the `emit_schema` executable links
against Lean core alone (no Mathlib object code is required).
-/

namespace BayesianNetworksProofs

open Lean (Json ToJson FromJson)

/-- A generator of arrow shape: a hom `name : dom → cod` between objects, or an attribute
`name : dom → cod` from an object to an attribute type. -/
structure Arrow where
  name : String
  dom : String
  cod : String
  deriving ToJson, FromJson, DecidableEq, Repr

/-- A presentation of an ACSet schema: object generators, hom generators, attribute-type
generators and attribute generators. Equations are not modelled (the schemas of
`BayesianNetworks.jl` have none). -/
structure SchemaDesc where
  obs : List String
  homs : List Arrow
  attrtypes : List String
  attrs : List Arrow
  deriving ToJson, FromJson, DecidableEq, Repr

namespace SchemaDesc

/-- All generator names of a schema, in the order `obs, homs, attrtypes, attrs`. -/
def names (S : SchemaDesc) : List String :=
  S.obs ++ S.homs.map Arrow.name ++ S.attrtypes ++ S.attrs.map Arrow.name

/-- Well-formedness: every generator name is distinct; every hom has an object as domain and
codomain; every attribute has an object as domain and an attribute type as codomain. -/
def WF (S : SchemaDesc) : Prop :=
  S.names.Nodup ∧
  (∀ h ∈ S.homs, h.dom ∈ S.obs ∧ h.cod ∈ S.obs) ∧
  (∀ a ∈ S.attrs, a.dom ∈ S.obs ∧ a.cod ∈ S.attrtypes)

instance (S : SchemaDesc) : Decidable S.WF := by unfold WF; infer_instance

/-- `Sub S₀ S`: every generator of `S₀` is a generator of `S` (generator-wise inclusion, the
shape of a Catlab `@present Sch <: Sch₀`). -/
def Sub (S₀ S : SchemaDesc) : Prop :=
  (∀ x ∈ S₀.obs, x ∈ S.obs) ∧ (∀ h ∈ S₀.homs, h ∈ S.homs) ∧
  (∀ x ∈ S₀.attrtypes, x ∈ S.attrtypes) ∧ (∀ a ∈ S₀.attrs, a ∈ S.attrs)

instance (S₀ S : SchemaDesc) : Decidable (Sub S₀ S) := by unfold Sub; infer_instance

/-- `NoOutgoing S₀ S`: no hom or attribute of `S` whose domain is an object of `S₀` has a
codomain outside `S₀`. This is the precondition of Catlab's multi-object `OpenACSetTypes`:
the sub-schema `S₀` can then serve as the interface (foot) type of open `S`-ACSets. -/
def NoOutgoing (S₀ S : SchemaDesc) : Prop :=
  (∀ h ∈ S.homs, h.dom ∈ S₀.obs → h.cod ∈ S₀.obs) ∧
  (∀ a ∈ S.attrs, a.dom ∈ S₀.obs → a.cod ∈ S₀.attrtypes)

instance (S₀ S : SchemaDesc) : Decidable (NoOutgoing S₀ S) := by unfold NoOutgoing; infer_instance

/-- Extend a schema by appending generators (the Lean counterpart of `@present Sch <: Sch₀`). -/
def extend (S : SchemaDesc) (obs : List String := []) (homs : List Arrow := [])
    (attrtypes : List String := []) (attrs : List Arrow := []) : SchemaDesc where
  obs := S.obs ++ obs
  homs := S.homs ++ homs
  attrtypes := S.attrtypes ++ attrtypes
  attrs := S.attrs ++ attrs

/-- An extension always contains the schema it extends. -/
theorem sub_extend (S : SchemaDesc) (obs homs attrtypes attrs) :
    Sub S (S.extend obs homs attrtypes attrs) := by
  refine ⟨?_, ?_, ?_, ?_⟩ <;> intro x hx <;> simp [extend, hx]

/-! ## ACSets.jl schema JSON

`generate_json_acset_schema` in `ACSets/src/serialization/JSONACSets.jl` emits

```
{ "version": {"ACSetSchema": "0.0.1", "ACSets": <pkg version>},
  "Ob": [{"name": ..}], "Hom": [{"name","dom","codom"}],
  "AttrType": [{"name"}], "Attr": [{"name","dom","codom"}],
  "equations": [] }
```

(codomains are spelled `codom`; `Ob`/`AttrType` entries are objects with a single `name`).
JSON objects are unordered; Lean's `Json.obj` stores keys in an RB-map, so `Json.pretty`
prints keys in a fixed (reverse-alphabetical) order. Consumers must compare structurally.
-/

/-- The `ACSetSchema` format version written by ACSets.jl. -/
def acsetSchemaVersion : String := "0.0.1"

/-- The ACSets.jl package version recorded in emitted files (informational; Julia compares
modulo `version`). -/
def acsetsPkgVersion : String := "0.2.29"

private def arrowJson (a : Arrow) : Json :=
  Json.mkObj [("name", a.name), ("dom", a.dom), ("codom", a.cod)]

private def namedJson (x : String) : Json := Json.mkObj [("name", x)]

/-- Render a schema description in the ACSets.jl `generate_json_acset_schema` format. -/
def toACSetsJson (S : SchemaDesc) : Json :=
  Json.mkObj
    [ ("version", Json.mkObj [("ACSetSchema", acsetSchemaVersion), ("ACSets", acsetsPkgVersion)])
    , ("Ob", Json.arr (S.obs.map namedJson).toArray)
    , ("Hom", Json.arr (S.homs.map arrowJson).toArray)
    , ("AttrType", Json.arr (S.attrtypes.map namedJson).toArray)
    , ("Attr", Json.arr (S.attrs.map arrowJson).toArray)
    , ("equations", Json.arr #[]) ]

/-- Pretty-printed, deterministic text of `toACSetsJson` (trailing newline included). -/
def toACSetsJsonString (S : SchemaDesc) : String :=
  (S.toACSetsJson.pretty 100) ++ "\n"

end SchemaDesc

end BayesianNetworksProofs
