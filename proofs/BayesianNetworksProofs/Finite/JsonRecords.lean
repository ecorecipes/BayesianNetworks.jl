import BayesianNetworksProofs.Finite.RawRecords
import Lean.Data.Json.Basic
import Std.Data.TreeMap.Raw.Lemmas

/-!
# Decoding the ACSets JSON of a `SchBayesNet` network into checked records

`write_json_bayesnet` (BayesianNetworks.jl, `src/serialization.jl`) writes the envelope
`{"format": "bayesnet-acset", "schema_version": "0.1", "acset": body}`, where `body` is ACSets'
`generate_json_acset` of the network. The body is an object with one key per object of
`SchBayesNet` and one per attribute type:

* `"Variable"`, `"State"`, `"Mechanism"`, `"Input"`: arrays of row objects. Row `k` (zero-based
  here) is an object whose `"_id"` is the one-based part ID `k + 1`, whose hom columns
  (`state_variable`, `target`, `input_mechanism`, `input_variable`) are one-based part IDs,
  whose `Label` columns are strings, whose `Position` columns are one-based positions, and whose
  `Ref` columns are `KernelRef` objects with a `"type"` discriminator: `{"type": "NamedRef",
  "id": s}`, `{"type": "PolicyRef", "decision": s}`, `{"type": "PointMassRef", "state": s}` or
  `{"type": "NoRef"}`.
* `"Label"`, `"Position"`, `"Ref"`: the attribute-variable tables, which Julia writes as empty
  arrays for every network with concrete attributes.

This module decodes a parsed `Lean.Json` tree in exactly that layout into `Tables`, the rows of a
`Raw.Network` without its rank, which the JSON does not store. Hom columns go through `decodeId`;
a `Position` column holding `p ≥ 1` becomes the zero-based record position `p - 1`, the convention
of `Raw.Positioned`. The decoder is strict: every row object must have exactly its schema's keys,
`"_id"` must be the row number, a hom ID must lie in `1..n`, a position must be at least `1`,
every number must be a JSON integer written without a fraction or exponent sign (`Json.num` with
exponent `0`), the body must have exactly the seven keys above with the three attribute tables
empty, and the envelope must name the format and schema version (other envelope keys, such as the
`"semantics"` of `write_json_model`, are ignored). Any other shape is an `Except.error` naming the
table, the row and the column.

Results:

* `decodeTables_eq_ok`: decoding succeeds with `t` exactly when the JSON tree has that layout with
  `t`'s row counts and `t`'s field values (`BodyMatches`); `decodeTables_encodeTables`: the
  encoder `encodeTables` is a right inverse, `decodeTables (encodeTables t) = .ok t`.
* The failure lemmas (`decodeTables_error_of_missing_table`, `…_of_missing_column`,
  `…_of_hom_out_of_range`, `…_of_not_nat`, …) follow from the characterisation: no row is ever
  defaulted.
* `Tables.computeRank` places the variables greedily (a variable is placed once every input of
  every mechanism targeting it reads a placed variable). `computeRank_sound` and
  `computeRank_complete`: it succeeds exactly when the tables are acyclic, and then its rank
  satisfies the rank conditions of `Raw.Network.Valid`.
* `decode` and `decodeChecked : Json → Option (Σ' r : Network, r.Valid)`; `decodeChecked_sound` and
  `decodeChecked_encode` (every valid network is recovered, up to the rank, which `compile` does
  not read: `compile_eq_of_tables_eq`).

What is not proved: `Lean.Json.parse` (text to `Json`), Julia's JSON3 writer and ACSets'
`generate_json_acset` are trusted. The theorems start from a parsed `Json` tree.
-/

set_option autoImplicit false

namespace BayesianNetworksProofs.Raw

open Lean (Json JsonNumber)

/-! ## `Except` and JSON scalars -/

theorem bind_eq_ok {ε α β : Type} {x : Except ε α} {f : α → Except ε β} {b : β} :
    x >>= f = .ok b ↔ ∃ a, x = .ok a ∧ f a = .ok b := by
  cases x <;> simp [bind, Except.bind]

theorem pure_eq_ok {ε α : Type} {a b : α} : (pure a : Except ε α) = .ok b ↔ a = b := by
  simp [pure, Except.pure]

theorem throw_ne_ok {ε α : Type} {e : ε} {b : α} : (throw e : Except ε α) ≠ .ok b := by
  simp [throw, throwThe, MonadExceptOf.throw]

/-- A JSON object, as `Lean.Json.obj` stores it. -/
abbrev JsonObject := Std.TreeMap.Raw String Json compare

/-- A natural number as Julia's JSON3 writes an `Int`: a JSON number with exponent `0`. -/
def natJson (n : Nat) : Json := .num ⟨(n : Int), 0⟩

/-- The natural number a JSON value holds, if it is a nonnegative number with exponent `0`. -/
def jsonNat? : Json → Option Nat
  | .num ⟨.ofNat n, 0⟩ => some n
  | _ => none

theorem jsonNat?_eq_some {j : Json} {n : Nat} : jsonNat? j = some n ↔ j = natJson n := by
  constructor
  · intro h
    cases j with
    | num x =>
      obtain ⟨m, e⟩ := x
      cases m with
      | ofNat m =>
        cases e with
        | zero => simp only [jsonNat?, Option.some.injEq] at h; subst h; rfl
        | succ e => simp [jsonNat?] at h
      | negSucc m => simp [jsonNat?] at h
    | _ => simp [jsonNat?] at h
  · rintro rfl
    rfl

theorem decodeId_eq_some {n e : Nat} {i : Fin n} : decodeId n e = some i ↔ e = i.val + 1 := by
  unfold decodeId
  split_ifs with h
  · simp only [Option.some.injEq]
    constructor
    · rintro rfl
      simp only
      omega
    · rintro rfl
      ext
      simp
  · simp only [false_iff]
    intro he
    omega

/-! ## Typed reads of a row object -/

/-- The value of column `k`, or an error naming the row and the column. -/
def field (row : String) (o : JsonObject) (k : String) : Except String Json :=
  match o[k]? with
  | some v => .ok v
  | none => .error s!"{row}: missing column \"{k}\""

theorem field_eq_ok {row : String} {o : JsonObject} {k : String} {v : Json} :
    field row o k = .ok v ↔ o[k]? = some v := by
  unfold field
  split <;> simp_all

def natField (row : String) (o : JsonObject) (k : String) : Except String Nat := do
  let v ← field row o k
  match jsonNat? v with
  | some n => pure n
  | none => throw s!"{row}: column \"{k}\" must be a nonnegative integer"

theorem natField_eq_ok {row : String} {o : JsonObject} {k : String} {n : Nat} :
    natField row o k = .ok n ↔ o[k]? = some (natJson n) := by
  unfold natField
  rw [bind_eq_ok]
  constructor
  · rintro ⟨v, hv, h⟩
    rw [field_eq_ok] at hv
    split at h
    · rename_i m hm
      rw [pure_eq_ok] at h
      subst h
      rw [hv, jsonNat?_eq_some.1 hm]
    · exact absurd h throw_ne_ok
  · intro h
    refine ⟨_, field_eq_ok.2 h, ?_⟩
    rw [show jsonNat? (natJson n) = some n from rfl]
    rfl

def strField (row : String) (o : JsonObject) (k : String) : Except String String := do
  let v ← field row o k
  match v with
  | .str s => pure s
  | _ => throw s!"{row}: column \"{k}\" must be a string"

theorem strField_eq_ok {row : String} {o : JsonObject} {k : String} {s : String} :
    strField row o k = .ok s ↔ o[k]? = some (.str s) := by
  unfold strField
  rw [bind_eq_ok]
  constructor
  · rintro ⟨v, hv, h⟩
    rw [field_eq_ok] at hv
    split at h
    · rw [pure_eq_ok] at h
      subst h
      exact hv
    · exact absurd h throw_ne_ok
  · intro h
    exact ⟨_, field_eq_ok.2 h, rfl⟩

/-- A hom column: a one-based part ID in `1..n`, decoded by `decodeId`. -/
def homField (row : String) (o : JsonObject) (k : String) (n : Nat) : Except String (Fin n) := do
  let e ← natField row o k
  match decodeId n e with
  | some i => pure i
  | none => throw s!"{row}: column \"{k}\" is the ID {e}, not in 1..{n}"

theorem homField_eq_ok {row : String} {o : JsonObject} {k : String} {n : Nat} {i : Fin n} :
    homField row o k n = .ok i ↔ o[k]? = some (natJson (i.val + 1)) := by
  unfold homField
  rw [bind_eq_ok]
  constructor
  · rintro ⟨e, he, h⟩
    rw [natField_eq_ok] at he
    split at h
    · rename_i j hj
      rw [pure_eq_ok] at h
      subst h
      rw [he, decodeId_eq_some.1 hj]
    · exact absurd h throw_ne_ok
  · intro h
    refine ⟨_, natField_eq_ok.2 h, ?_⟩
    rw [show decodeId n (i.val + 1) = some i from decodeId_eq_some.2 rfl]
    rfl

/-- A `Position` column: Julia's one-based position `p ≥ 1`, returned as the zero-based record
position `p - 1`. -/
def posField (row : String) (o : JsonObject) (k : String) : Except String Nat := do
  let e ← natField row o k
  if e = 0 then throw s!"{row}: column \"{k}\" is the position 0; positions are one-based"
  else pure (e - 1)

theorem posField_eq_ok {row : String} {o : JsonObject} {k : String} {p : Nat} :
    posField row o k = .ok p ↔ o[k]? = some (natJson (p + 1)) := by
  unfold posField
  rw [bind_eq_ok]
  constructor
  · rintro ⟨e, he, h⟩
    rw [natField_eq_ok] at he
    by_cases h0 : e = 0
    · rw [if_pos h0] at h
      exact absurd h throw_ne_ok
    · rw [if_neg h0, pure_eq_ok] at h
      subst h
      rw [he]
      congr 2
      omega
  · intro h
    refine ⟨_, natField_eq_ok.2 h, ?_⟩
    rw [if_neg (Nat.add_one_ne_zero p), Nat.add_sub_cancel]
    rfl

/-- A JSON object, of any size. -/
def anyObject (row : String) : Json → Except String JsonObject
  | .obj o => .ok o
  | _ => .error s!"{row}: expected a JSON object"

theorem anyObject_eq_ok {row : String} {j : Json} {o : JsonObject} :
    anyObject row j = .ok o ↔ j = .obj o := by
  cases j <;> simp [anyObject]

def checkSize (row : String) (o : JsonObject) (n : Nat) : Except String Unit :=
  if o.size = n then .ok () else .error s!"{row}: expected {n} keys, found {o.size}"

theorem checkSize_eq_ok {row : String} {o : JsonObject} {n : Nat} {u : Unit} :
    checkSize row o n = .ok u ↔ o.size = n := by
  unfold checkSize
  split_ifs <;> simp_all

/-- A row object with exactly `n` keys. -/
def object (row : String) (n : Nat) (j : Json) : Except String JsonObject := do
  let o ← anyObject row j
  checkSize row o n
  pure o

theorem object_eq_ok {row : String} {n : Nat} {j : Json} {o : JsonObject} :
    object row n j = .ok o ↔ j = .obj o ∧ o.size = n := by
  unfold object
  simp only [bind_eq_ok, anyObject_eq_ok, checkSize_eq_ok, pure_eq_ok]
  constructor
  · rintro ⟨o', rfl, u, hs, rfl⟩
    exact ⟨rfl, hs⟩
  · rintro ⟨rfl, hs⟩
    exact ⟨o, rfl, (), hs, rfl⟩

/-- The `"_id"` column of row `k` (zero-based) is the one-based ID `k + 1`. -/
def checkId (row : String) (o : JsonObject) (k : Nat) : Except String Unit := do
  let e ← natField row o "_id"
  if e = k + 1 then pure () else throw s!"{row}: \"_id\" is {e}, expected {k + 1}"

theorem checkId_eq_ok {row : String} {o : JsonObject} {k : Nat} {u : Unit} :
    checkId row o k = .ok u ↔ o["_id"]? = some (natJson (k + 1)) := by
  unfold checkId
  rw [bind_eq_ok]
  constructor
  · rintro ⟨e, he, h⟩
    rw [natField_eq_ok] at he
    by_cases hk : e = k + 1
    · rw [he, hk]
    · rw [if_neg hk] at h
      exact absurd h throw_ne_ok
  · intro h
    exact ⟨_, natField_eq_ok.2 h, by rw [if_pos rfl]; rfl⟩

/-! ## `KernelRef` objects -/

def decodeRef (row : String) (j : Json) : Except String Ref := do
  let o ← anyObject row j
  let ty ← strField row o "type"
  if ty = "NamedRef" then do
    checkSize row o 2
    let s ← strField row o "id"
    pure (.named s)
  else if ty = "PolicyRef" then do
    checkSize row o 2
    let s ← strField row o "decision"
    pure (.policy s)
  else if ty = "PointMassRef" then do
    checkSize row o 2
    let s ← strField row o "state"
    pure (.pointMass s)
  else if ty = "NoRef" then do
    checkSize row o 1
    pure .none
  else throw s!"{row}: unknown KernelRef type \"{ty}\""

def encodeRef : Ref → Json
  | .named s => Json.mkObj [("type", .str "NamedRef"), ("id", .str s)]
  | .policy s => Json.mkObj [("type", .str "PolicyRef"), ("decision", .str s)]
  | .pointMass s => Json.mkObj [("type", .str "PointMassRef"), ("state", .str s)]
  | .none => Json.mkObj [("type", .str "NoRef")]

/-- The JSON value is the `KernelRef` object of `ref`: exactly its keys, with its values. -/
def RefMatches (j : Json) : Ref → Prop
  | .named s => ∃ o, j = .obj o ∧ o.size = 2 ∧ o["type"]? = some (.str "NamedRef") ∧
      o["id"]? = some (.str s)
  | .policy s => ∃ o, j = .obj o ∧ o.size = 2 ∧ o["type"]? = some (.str "PolicyRef") ∧
      o["decision"]? = some (.str s)
  | .pointMass s => ∃ o, j = .obj o ∧ o.size = 2 ∧ o["type"]? = some (.str "PointMassRef") ∧
      o["state"]? = some (.str s)
  | .none => ∃ o, j = .obj o ∧ o.size = 1 ∧ o["type"]? = some (.str "NoRef")

theorem decodeRef_eq_ok {row : String} {j : Json} {ref : Ref} :
    decodeRef row j = .ok ref ↔ RefMatches j ref := by
  unfold decodeRef
  simp only [bind_eq_ok, anyObject_eq_ok]
  constructor
  · rintro ⟨o, rfl, ty, hty, h⟩
    rw [strField_eq_ok] at hty
    split_ifs at h with h1 h2 h3 h4
    · subst h1
      simp only [bind_eq_ok, checkSize_eq_ok, strField_eq_ok, pure_eq_ok] at h
      obtain ⟨_, hs, s, hs', rfl⟩ := h
      exact ⟨o, rfl, hs, hty, hs'⟩
    · subst h2
      simp only [bind_eq_ok, checkSize_eq_ok, strField_eq_ok, pure_eq_ok] at h
      obtain ⟨_, hs, s, hs', rfl⟩ := h
      exact ⟨o, rfl, hs, hty, hs'⟩
    · subst h3
      simp only [bind_eq_ok, checkSize_eq_ok, strField_eq_ok, pure_eq_ok] at h
      obtain ⟨_, hs, s, hs', rfl⟩ := h
      exact ⟨o, rfl, hs, hty, hs'⟩
    · subst h4
      simp only [bind_eq_ok, checkSize_eq_ok, pure_eq_ok] at h
      obtain ⟨_, hs, rfl⟩ := h
      exact ⟨o, rfl, hs, hty⟩
  · intro h
    cases ref with
    | named s =>
      obtain ⟨o, rfl, hs, hty, hv⟩ := h
      refine ⟨o, rfl, _, strField_eq_ok.2 hty, ?_⟩
      rw [if_pos rfl]
      simp only [bind_eq_ok, checkSize_eq_ok, strField_eq_ok, pure_eq_ok]
      exact ⟨(), hs, s, hv, rfl⟩
    | policy s =>
      obtain ⟨o, rfl, hs, hty, hv⟩ := h
      refine ⟨o, rfl, _, strField_eq_ok.2 hty, ?_⟩
      rw [if_neg (by simp), if_pos rfl]
      simp only [bind_eq_ok, checkSize_eq_ok, strField_eq_ok, pure_eq_ok]
      exact ⟨(), hs, s, hv, rfl⟩
    | pointMass s =>
      obtain ⟨o, rfl, hs, hty, hv⟩ := h
      refine ⟨o, rfl, _, strField_eq_ok.2 hty, ?_⟩
      rw [if_neg (by simp), if_neg (by simp), if_pos rfl]
      simp only [bind_eq_ok, checkSize_eq_ok, strField_eq_ok, pure_eq_ok]
      exact ⟨(), hs, s, hv, rfl⟩
    | none =>
      obtain ⟨o, rfl, hs, hty⟩ := h
      refine ⟨o, rfl, _, strField_eq_ok.2 hty, ?_⟩
      rw [if_neg (by simp), if_neg (by simp), if_neg (by simp), if_pos rfl]
      simp only [bind_eq_ok, checkSize_eq_ok, pure_eq_ok]
      exact ⟨(), hs, trivial⟩

/-- A guard: `.ok ()` when `c` holds, otherwise the error `msg`. -/
def require (c : Prop) [Decidable c] (msg : String) : Except String Unit :=
  if c then .ok () else .error msg

theorem require_eq_ok {c : Prop} [Decidable c] {msg : String} {u : Unit} :
    require c msg = .ok u ↔ c := by
  unfold require
  split_ifs <;> simp_all

/-! ## Encoding: `Json.mkObj` with distinct keys -/

theorem mkObj_getElem? {l : List (String × Json)} (hd : (l.map Prod.fst).Nodup) {k : String}
    {v : Json} (hm : (k, v) ∈ l) : (Std.TreeMap.Raw.ofList l compare)[k]? = some v := by
  refine Std.TreeMap.Raw.getElem?_ofList_of_mem (k := k) Std.ReflCmp.compare_self ?_ hm
  have := List.pairwise_map.1 hd
  exact this.imp fun h he => h (Std.compare_eq_iff_eq.1 he)

theorem mkObj_size {l : List (String × Json)} (hd : (l.map Prod.fst).Nodup) :
    (Std.TreeMap.Raw.ofList l compare).size = l.length := by
  refine Std.TreeMap.Raw.size_ofList ?_
  have := List.pairwise_map.1 hd
  exact this.imp fun h he => h (Std.compare_eq_iff_eq.1 he)

theorem refMatches_encodeRef (ref : Ref) : RefMatches (encodeRef ref) ref := by
  cases ref <;> first
    | exact ⟨_, rfl, mkObj_size (by simp), mkObj_getElem? (by simp) (by simp),
        mkObj_getElem? (by simp) (by simp)⟩
    | exact ⟨_, rfl, mkObj_size (by simp), mkObj_getElem? (by simp) (by simp)⟩

/-! ## Rows -/

/-- The name of row `k` (zero-based) of a table in error messages: `"State row 3"`. -/
def rowLabel (table : String) (k : Nat) : String := s!"{table} row {k + 1}"

def decodeVariableRow (k : Nat) (j : Json) : Except String VariableRow := do
  let o ← object (rowLabel "Variable" k) 3 j
  checkId (rowLabel "Variable" k) o k
  let name ← strField (rowLabel "Variable" k) o "variable_name"
  let rj ← field (rowLabel "Variable" k) o "space_ref"
  let ref ← decodeRef (rowLabel "Variable" k) rj
  pure ⟨name, ref⟩

def decodeStateRow (nv : Nat) (k : Nat) (j : Json) : Except String (StateRow nv) := do
  let o ← object (rowLabel "State" k) 4 j
  checkId (rowLabel "State" k) o k
  let v ← homField (rowLabel "State" k) o "state_variable" nv
  let name ← strField (rowLabel "State" k) o "state_name"
  let p ← posField (rowLabel "State" k) o "state_position"
  pure ⟨v, p, name⟩

def decodeMechanismRow (nv : Nat) (k : Nat) (j : Json) : Except String (MechanismRow nv) := do
  let o ← object (rowLabel "Mechanism" k) 4 j
  checkId (rowLabel "Mechanism" k) o k
  let v ← homField (rowLabel "Mechanism" k) o "target" nv
  let name ← strField (rowLabel "Mechanism" k) o "mechanism_name"
  let rj ← field (rowLabel "Mechanism" k) o "kernel_ref"
  let ref ← decodeRef (rowLabel "Mechanism" k) rj
  pure ⟨v, name, ref⟩

def decodeInputRow (nv nm : Nat) (k : Nat) (j : Json) : Except String (InputRow nv nm) := do
  let o ← object (rowLabel "Input" k) 4 j
  checkId (rowLabel "Input" k) o k
  let m ← homField (rowLabel "Input" k) o "input_mechanism" nm
  let v ← homField (rowLabel "Input" k) o "input_variable" nv
  let p ← posField (rowLabel "Input" k) o "input_position"
  pure ⟨m, v, p⟩

def encodeVariableRow (k : Nat) (r : VariableRow) : Json :=
  Json.mkObj [("_id", natJson (k + 1)), ("variable_name", .str r.name),
    ("space_ref", encodeRef r.spaceRef)]

def encodeStateRow {nv : Nat} (k : Nat) (r : StateRow nv) : Json :=
  Json.mkObj [("_id", natJson (k + 1)), ("state_variable", natJson (r.var.val + 1)),
    ("state_name", .str r.name), ("state_position", natJson (r.position + 1))]

def encodeMechanismRow {nv : Nat} (k : Nat) (r : MechanismRow nv) : Json :=
  Json.mkObj [("_id", natJson (k + 1)), ("target", natJson (r.target.val + 1)),
    ("mechanism_name", .str r.name), ("kernel_ref", encodeRef r.kernelRef)]

def encodeInputRow {nv nm : Nat} (k : Nat) (r : InputRow nv nm) : Json :=
  Json.mkObj [("_id", natJson (k + 1)), ("input_mechanism", natJson (r.mechanism.val + 1)),
    ("input_variable", natJson (r.var.val + 1)), ("input_position", natJson (r.position + 1))]

/-- Row `k` of `"Variable"` holds exactly the columns `_id`, `variable_name`, `space_ref`, with
the one-based ID `k + 1` and the row's values. -/
def VariableRowMatches (k : Nat) (j : Json) (r : VariableRow) : Prop :=
  ∃ o, j = .obj o ∧ o.size = 3 ∧ o["_id"]? = some (natJson (k + 1)) ∧
    o["variable_name"]? = some (.str r.name) ∧
    ∃ rj, o["space_ref"]? = some rj ∧ RefMatches rj r.spaceRef

/-- Row `k` of `"State"`: `state_variable` is the one-based variable ID and `state_position` the
one-based position, i.e. the record's zero-based `position` plus one. -/
def StateRowMatches {nv : Nat} (k : Nat) (j : Json) (r : StateRow nv) : Prop :=
  ∃ o, j = .obj o ∧ o.size = 4 ∧ o["_id"]? = some (natJson (k + 1)) ∧
    o["state_variable"]? = some (natJson (r.var.val + 1)) ∧
    o["state_name"]? = some (.str r.name) ∧
    o["state_position"]? = some (natJson (r.position + 1))

def MechanismRowMatches {nv : Nat} (k : Nat) (j : Json) (r : MechanismRow nv) : Prop :=
  ∃ o, j = .obj o ∧ o.size = 4 ∧ o["_id"]? = some (natJson (k + 1)) ∧
    o["target"]? = some (natJson (r.target.val + 1)) ∧
    o["mechanism_name"]? = some (.str r.name) ∧
    ∃ rj, o["kernel_ref"]? = some rj ∧ RefMatches rj r.kernelRef

def InputRowMatches {nv nm : Nat} (k : Nat) (j : Json) (r : InputRow nv nm) : Prop :=
  ∃ o, j = .obj o ∧ o.size = 4 ∧ o["_id"]? = some (natJson (k + 1)) ∧
    o["input_mechanism"]? = some (natJson (r.mechanism.val + 1)) ∧
    o["input_variable"]? = some (natJson (r.var.val + 1)) ∧
    o["input_position"]? = some (natJson (r.position + 1))

theorem decodeVariableRow_eq_ok {k : Nat} {j : Json} {r : VariableRow} :
    decodeVariableRow k j = .ok r ↔ VariableRowMatches k j r := by
  unfold decodeVariableRow VariableRowMatches
  simp only [bind_eq_ok, object_eq_ok, checkId_eq_ok, strField_eq_ok, field_eq_ok,
    decodeRef_eq_ok, pure_eq_ok]
  constructor
  · rintro ⟨o, ⟨rfl, hs⟩, _, hid, n, hn, rj, hrj, ref, href, rfl⟩
    exact ⟨o, rfl, hs, hid, hn, rj, hrj, href⟩
  · rintro ⟨o, rfl, hs, hid, hn, rj, hrj, href⟩
    exact ⟨o, ⟨rfl, hs⟩, (), hid, _, hn, rj, hrj, _, href, rfl⟩

theorem decodeStateRow_eq_ok {nv k : Nat} {j : Json} {r : StateRow nv} :
    decodeStateRow nv k j = .ok r ↔ StateRowMatches k j r := by
  unfold decodeStateRow StateRowMatches
  simp only [bind_eq_ok, object_eq_ok, checkId_eq_ok, strField_eq_ok, homField_eq_ok,
    posField_eq_ok, pure_eq_ok]
  constructor
  · rintro ⟨o, ⟨rfl, hs⟩, _, hid, v, hv, n, hn, p, hp, rfl⟩
    exact ⟨o, rfl, hs, hid, hv, hn, hp⟩
  · rintro ⟨o, rfl, hs, hid, hv, hn, hp⟩
    exact ⟨o, ⟨rfl, hs⟩, (), hid, _, hv, _, hn, _, hp, rfl⟩

theorem decodeMechanismRow_eq_ok {nv k : Nat} {j : Json} {r : MechanismRow nv} :
    decodeMechanismRow nv k j = .ok r ↔ MechanismRowMatches k j r := by
  unfold decodeMechanismRow MechanismRowMatches
  simp only [bind_eq_ok, object_eq_ok, checkId_eq_ok, strField_eq_ok, homField_eq_ok,
    field_eq_ok, decodeRef_eq_ok, pure_eq_ok]
  constructor
  · rintro ⟨o, ⟨rfl, hs⟩, _, hid, v, hv, n, hn, rj, hrj, ref, href, rfl⟩
    exact ⟨o, rfl, hs, hid, hv, hn, rj, hrj, href⟩
  · rintro ⟨o, rfl, hs, hid, hv, hn, rj, hrj, href⟩
    exact ⟨o, ⟨rfl, hs⟩, (), hid, _, hv, _, hn, rj, hrj, _, href, rfl⟩

theorem decodeInputRow_eq_ok {nv nm k : Nat} {j : Json} {r : InputRow nv nm} :
    decodeInputRow nv nm k j = .ok r ↔ InputRowMatches k j r := by
  unfold decodeInputRow InputRowMatches
  simp only [bind_eq_ok, object_eq_ok, checkId_eq_ok, homField_eq_ok, posField_eq_ok,
    pure_eq_ok]
  constructor
  · rintro ⟨o, ⟨rfl, hs⟩, _, hid, m, hm, v, hv, p, hp, rfl⟩
    exact ⟨o, rfl, hs, hid, hm, hv, hp⟩
  · rintro ⟨o, rfl, hs, hid, hm, hv, hp⟩
    exact ⟨o, ⟨rfl, hs⟩, (), hid, _, hm, _, hv, _, hp, rfl⟩

theorem variableRowMatches_encode (k : Nat) (r : VariableRow) :
    VariableRowMatches k (encodeVariableRow k r) r :=
  ⟨_, rfl, mkObj_size (by simp), mkObj_getElem? (by simp) (by simp),
    mkObj_getElem? (by simp) (by simp), _, mkObj_getElem? (by simp) (by simp),
    refMatches_encodeRef _⟩

theorem stateRowMatches_encode {nv : Nat} (k : Nat) (r : StateRow nv) :
    StateRowMatches k (encodeStateRow k r) r :=
  ⟨_, rfl, mkObj_size (by simp), mkObj_getElem? (by simp) (by simp),
    mkObj_getElem? (by simp) (by simp), mkObj_getElem? (by simp) (by simp),
    mkObj_getElem? (by simp) (by simp)⟩

theorem mechanismRowMatches_encode {nv : Nat} (k : Nat) (r : MechanismRow nv) :
    MechanismRowMatches k (encodeMechanismRow k r) r :=
  ⟨_, rfl, mkObj_size (by simp), mkObj_getElem? (by simp) (by simp),
    mkObj_getElem? (by simp) (by simp), mkObj_getElem? (by simp) (by simp), _,
    mkObj_getElem? (by simp) (by simp), refMatches_encodeRef _⟩

theorem inputRowMatches_encode {nv nm : Nat} (k : Nat) (r : InputRow nv nm) :
    InputRowMatches k (encodeInputRow k r) r :=
  ⟨_, rfl, mkObj_size (by simp), mkObj_getElem? (by simp) (by simp),
    mkObj_getElem? (by simp) (by simp), mkObj_getElem? (by simp) (by simp),
    mkObj_getElem? (by simp) (by simp)⟩

/-! ## Tables -/

/-- Run `f` on every index in order, failing at the first error; on success the results as a
list of length `n`. -/
def decodeList {α : Type} : (n : Nat) → (Fin n → Except String α) →
    Except String {l : List α // l.length = n}
  | 0, _ => .ok ⟨[], rfl⟩
  | n + 1, f => do
    let x ← f 0
    let xs ← decodeList n (fun i => f i.succ)
    pure ⟨x :: xs.val, by rw [List.length_cons, xs.property]⟩

theorem decodeList_eq_ok {α : Type} :
    ∀ {n : Nat} {f : Fin n → Except String α} {l : {l : List α // l.length = n}},
      decodeList n f = .ok l ↔ ∀ i : Fin n, f i = .ok (l.val[i.val]'(lt_of_lt_of_eq i.isLt l.property.symm))
  | 0, f, ⟨l, hl⟩ => by
    simp only [decodeList, Except.ok.injEq, IsEmpty.forall_iff, iff_true]
    exact Subtype.ext (List.eq_nil_of_length_eq_zero hl).symm
  | n + 1, f, ⟨l, hl⟩ => by
    simp only [decodeList, bind_eq_ok, pure_eq_ok]
    constructor
    · rintro ⟨x, hx, ⟨xs, hxs⟩, hd, he⟩ i
      cases he
      rw [decodeList_eq_ok] at hd
      refine Fin.cases ?_ (fun i => ?_) i
      · simpa using hx
      · simpa using hd i
    · intro h
      obtain ⟨y, ys, rfl⟩ := List.exists_cons_of_length_eq_add_one hl
      refine ⟨y, by simpa using h 0, ⟨ys, by simpa using hl⟩, ?_, rfl⟩
      rw [decodeList_eq_ok]
      intro i
      simpa using h i.succ

/-- Run `f` on every index, failing at the first error; on success the results as a function
(backed by a list, so that a lookup costs linear time). -/
def decodeFn {α : Type} (n : Nat) (f : Fin n → Except String α) : Except String (Fin n → α) := do
  let l ← decodeList n f
  pure fun i => l.val[i.val]'(lt_of_lt_of_eq i.isLt l.property.symm)

theorem decodeFn_eq_ok {α : Type} {n : Nat} {f : Fin n → Except String α} {g : Fin n → α} :
    decodeFn n f = .ok g ↔ ∀ i, f i = .ok (g i) := by
  unfold decodeFn
  rw [bind_eq_ok]
  constructor
  · rintro ⟨l, hl, he⟩ i
    rw [pure_eq_ok] at he
    subst he
    exact decodeList_eq_ok.1 hl i
  · intro h
    refine ⟨⟨List.ofFn g, List.length_ofFn⟩, decodeList_eq_ok.2 fun i => by simpa using h i, ?_⟩
    rw [pure_eq_ok]
    funext i
    simp

/-- Decode the table `name` of the body: an array whose row `k` is decoded by `row k`. -/
def decodeTable {α : Type} (body : JsonObject) (name : String)
    (row : Nat → Json → Except String α) : Except String (Σ n, Fin n → α) := do
  let t ← field "acset" body name
  match t with
  | .arr a => do
    let f ← decodeFn a.size (fun i => row i.val a[i])
    pure ⟨a.size, f⟩
  | _ => throw s!"acset: table \"{name}\" must be an array"

/-- The table `name` is an array of exactly `n` rows, row `k` matching `f k`. -/
def TableMatches {α : Type} (body : JsonObject) (name : String) (M : Nat → Json → α → Prop)
    (n : Nat) (f : Fin n → α) : Prop :=
  ∃ a : Array Json, body[name]? = some (.arr a) ∧ a.size = n ∧
    ∀ i : Fin n, ∃ x, a[i.val]? = some x ∧ M i.val x (f i)

theorem sigma_fin_eq_iff {α : Type} {m n : Nat} {g : Fin m → α} {f : Fin n → α} :
    (⟨m, g⟩ : Σ n, Fin n → α) = ⟨n, f⟩ ↔ ∃ h : m = n, ∀ i, g i = f (Fin.cast h i) := by
  constructor
  · intro he
    cases he
    exact ⟨rfl, fun _ => rfl⟩
  · rintro ⟨rfl, h⟩
    have : g = f := funext h
    subst this
    rfl

theorem decodeTable_eq_ok {α : Type} {body : JsonObject} {name : String}
    {row : Nat → Json → Except String α} {M : Nat → Json → α → Prop}
    (hrow : ∀ k j x, row k j = .ok x ↔ M k j x) {n : Nat} {f : Fin n → α} :
    decodeTable body name row = .ok ⟨n, f⟩ ↔ TableMatches body name M n f := by
  unfold decodeTable TableMatches
  rw [bind_eq_ok]
  constructor
  · rintro ⟨t, ht, h⟩
    rw [field_eq_ok] at ht
    split at h
    · rename_i a
      rw [bind_eq_ok] at h
      obtain ⟨g, hg, he⟩ := h
      rw [pure_eq_ok, sigma_fin_eq_iff] at he
      obtain ⟨rfl, he⟩ := he
      rw [decodeFn_eq_ok] at hg
      have hgf : g = f := funext fun i => (he i).trans rfl
      subst hgf
      exact ⟨a, ht, rfl, fun i => ⟨a[i], by simp, (hrow _ _ _).1 (hg i)⟩⟩
    · exact absurd h throw_ne_ok
  · rintro ⟨a, ha, rfl, hrows⟩
    refine ⟨_, field_eq_ok.2 ha, ?_⟩
    simp only [bind_eq_ok, pure_eq_ok]
    refine ⟨f, decodeFn_eq_ok.2 fun i => ?_, rfl⟩
    obtain ⟨x, hx, hm⟩ := hrows i
    rw [Array.getElem?_eq_getElem i.isLt, Option.some.injEq] at hx
    subst hx
    exact (hrow _ _ _).2 hm

def encodeTable {α : Type} {n : Nat} (enc : Nat → α → Json) (f : Fin n → α) : Json :=
  .arr (Array.ofFn fun i => enc i.val (f i))

theorem tableMatches_encode {α : Type} {body : JsonObject} {name : String}
    {M : Nat → Json → α → Prop} {n : Nat} {f : Fin n → α} {enc : Nat → α → Json}
    (hget : body[name]? = some (encodeTable enc f)) (henc : ∀ k x, M k (enc k x) x) :
    TableMatches body name M n f :=
  ⟨_, hget, Array.size_ofFn, fun i => ⟨_, by simp, henc _ _⟩⟩

/-- An attribute-variable table (`"Label"`, `"Position"`, `"Ref"`): present and empty. -/
def emptyTable (body : JsonObject) (name : String) : Except String Unit := do
  let t ← field "acset" body name
  match t with
  | .arr a =>
    require (a.size = 0) s!"acset: attribute-variable table \"{name}\" must be empty"
  | _ => throw s!"acset: table \"{name}\" must be an array"

theorem emptyTable_eq_ok {body : JsonObject} {name : String} {u : Unit} :
    emptyTable body name = .ok u ↔ body[name]? = some (.arr #[]) := by
  unfold emptyTable
  rw [bind_eq_ok]
  constructor
  · rintro ⟨t, ht, h⟩
    rw [field_eq_ok] at ht
    split at h
    · rw [require_eq_ok, Array.size_eq_zero_iff] at h
      subst h
      exact ht
    · exact absurd h throw_ne_ok
  · intro h
    exact ⟨_, field_eq_ok.2 h, require_eq_ok.2 rfl⟩

/-! ## The network body and the envelope -/

/-- The rows of a `Raw.Network` without its rank: exactly what the ACSet JSON stores. -/
structure Tables where
  nv : Nat
  ns : Nat
  nm : Nat
  ni : Nat
  vars : Fin nv → VariableRow
  states : Fin ns → StateRow nv
  mechanisms : Fin nm → MechanismRow nv
  inputs : Fin ni → InputRow nv nm

/-- The object tables of `SchBayesNet` and its attribute-variable tables. -/
def bnObjectTables : List String := ["Variable", "State", "Mechanism", "Input"]
def bnAttrTables : List String := ["Label", "Position", "Ref"]

def decodeBody (j : Json) : Except String Tables := do
  let body ← object "acset" 7 j
  emptyTable body "Label"
  emptyTable body "Position"
  emptyTable body "Ref"
  let V ← decodeTable body "Variable" decodeVariableRow
  let S ← decodeTable body "State" (decodeStateRow V.1)
  let M ← decodeTable body "Mechanism" (decodeMechanismRow V.1)
  let I ← decodeTable body "Input" (decodeInputRow V.1 M.1)
  pure ⟨V.1, S.1, M.1, I.1, V.2, S.2, M.2, I.2⟩

/-- The body is the ACSet JSON of `t`: an object with exactly the seven tables, the attribute
tables empty, and each object table matching `t` row for row. -/
def BodyMatches (j : Json) (t : Tables) : Prop :=
  ∃ body, j = .obj body ∧ body.size = 7 ∧
    body["Label"]? = some (.arr #[]) ∧ body["Position"]? = some (.arr #[]) ∧
    body["Ref"]? = some (.arr #[]) ∧
    TableMatches body "Variable" VariableRowMatches t.nv t.vars ∧
    TableMatches body "State" StateRowMatches t.ns t.states ∧
    TableMatches body "Mechanism" MechanismRowMatches t.nm t.mechanisms ∧
    TableMatches body "Input" InputRowMatches t.ni t.inputs

theorem decodeBody_eq_ok {j : Json} {t : Tables} : decodeBody j = .ok t ↔ BodyMatches j t := by
  unfold decodeBody BodyMatches
  simp only [bind_eq_ok, object_eq_ok, emptyTable_eq_ok, pure_eq_ok]
  constructor
  · rintro ⟨body, ⟨rfl, hs⟩, _, hL, _, hP, _, hR, ⟨nv, vars⟩, hV, ⟨ns, states⟩, hS,
      ⟨nm, mechs⟩, hM, ⟨ni, inputs⟩, hI, rfl⟩
    exact ⟨body, rfl, hs, hL, hP, hR, (decodeTable_eq_ok fun _ _ _ => decodeVariableRow_eq_ok).1 hV,
      (decodeTable_eq_ok fun _ _ _ => decodeStateRow_eq_ok).1 hS,
      (decodeTable_eq_ok fun _ _ _ => decodeMechanismRow_eq_ok).1 hM,
      (decodeTable_eq_ok fun _ _ _ => decodeInputRow_eq_ok).1 hI⟩
  · rintro ⟨body, rfl, hs, hL, hP, hR, hV, hS, hM, hI⟩
    exact ⟨body, ⟨rfl, hs⟩, (), hL, (), hP, (), hR, ⟨t.nv, t.vars⟩,
      (decodeTable_eq_ok fun _ _ _ => decodeVariableRow_eq_ok).2 hV, ⟨t.ns, t.states⟩,
      (decodeTable_eq_ok fun _ _ _ => decodeStateRow_eq_ok).2 hS, ⟨t.nm, t.mechanisms⟩,
      (decodeTable_eq_ok fun _ _ _ => decodeMechanismRow_eq_ok).2 hM, ⟨t.ni, t.inputs⟩,
      (decodeTable_eq_ok fun _ _ _ => decodeInputRow_eq_ok).2 hI, rfl⟩

def encodeBody (t : Tables) : Json :=
  Json.mkObj [("Variable", encodeTable encodeVariableRow t.vars),
    ("State", encodeTable encodeStateRow t.states),
    ("Mechanism", encodeTable encodeMechanismRow t.mechanisms),
    ("Input", encodeTable encodeInputRow t.inputs),
    ("Label", .arr #[]), ("Position", .arr #[]), ("Ref", .arr #[])]

theorem bodyMatches_encode (t : Tables) : BodyMatches (encodeBody t) t :=
  ⟨_, rfl, mkObj_size (by simp), mkObj_getElem? (by simp) (by simp),
    mkObj_getElem? (by simp) (by simp), mkObj_getElem? (by simp) (by simp),
    tableMatches_encode (mkObj_getElem? (by simp) (by simp)) variableRowMatches_encode,
    tableMatches_encode (mkObj_getElem? (by simp) (by simp)) stateRowMatches_encode,
    tableMatches_encode (mkObj_getElem? (by simp) (by simp)) mechanismRowMatches_encode,
    tableMatches_encode (mkObj_getElem? (by simp) (by simp)) inputRowMatches_encode⟩

/-- The schema version both Julia packages write and require. -/
def schemaVersion : String := "0.1"

/-- The envelope: an object whose `"format"` and `"schema_version"` are as required; its
`"acset"` value is the body. Other keys are ignored. -/
def decodeEnvelope (format : String) (j : Json) : Except String Json := do
  let o ← anyObject "envelope" j
  let f ← strField "envelope" o "format"
  require (f = format) s!"envelope: format is \"{f}\", expected \"{format}\""
  let v ← strField "envelope" o "schema_version"
  require (v = schemaVersion) s!"envelope: schema_version is \"{v}\", expected \"{schemaVersion}\""
  field "envelope" o "acset"

def EnvelopeMatches (format : String) (j body : Json) : Prop :=
  ∃ o, j = .obj o ∧ o["format"]? = some (.str format) ∧
    o["schema_version"]? = some (.str schemaVersion) ∧ o["acset"]? = some body

theorem decodeEnvelope_eq_ok {format : String} {j body : Json} :
    decodeEnvelope format j = .ok body ↔ EnvelopeMatches format j body := by
  unfold decodeEnvelope EnvelopeMatches
  simp only [bind_eq_ok, anyObject_eq_ok, strField_eq_ok, require_eq_ok, field_eq_ok]
  constructor
  · rintro ⟨o, rfl, f, hf, _, rfl, v, hv, _, rfl, hb⟩
    exact ⟨o, rfl, hf, hv, hb⟩
  · rintro ⟨o, rfl, hf, hv, hb⟩
    exact ⟨o, rfl, _, hf, (), rfl, _, hv, (), rfl, hb⟩

def encodeEnvelope (format : String) (body : Json) : Json :=
  Json.mkObj [("format", .str format), ("schema_version", .str schemaVersion), ("acset", body)]

theorem envelopeMatches_encode (format : String) (body : Json) :
    EnvelopeMatches format (encodeEnvelope format body) body :=
  ⟨_, rfl, mkObj_getElem? (by simp) (by simp), mkObj_getElem? (by simp) (by simp),
    mkObj_getElem? (by simp) (by simp)⟩

/-- The format name `write_json_bayesnet` writes. -/
def bnFormat : String := "bayesnet-acset"

/-- **The decoder.** A parsed `write_json_bayesnet` document to its rows. -/
def decodeTables (j : Json) : Except String Tables := do
  let body ← decodeEnvelope bnFormat j
  decodeBody body

/-- **The encoder**, the layout `write_json_bayesnet` writes (up to key order and whitespace,
which a parsed `Json` object does not record). -/
def encodeTables (t : Tables) : Json := encodeEnvelope bnFormat (encodeBody t)

/-- **Faithfulness.** Decoding succeeds with `t` exactly when the document is a
`"bayesnet-acset"` envelope whose body has `t`'s row counts and, row by row and column by
column, `t`'s values (hom columns as one-based IDs, positions one-based). -/
theorem decodeTables_eq_ok {j : Json} {t : Tables} :
    decodeTables j = .ok t ↔ ∃ body, EnvelopeMatches bnFormat j body ∧ BodyMatches body t := by
  unfold decodeTables
  simp only [bind_eq_ok, decodeEnvelope_eq_ok, decodeBody_eq_ok]

/-- **Round trip.** -/
theorem decodeTables_encodeTables (t : Tables) : decodeTables (encodeTables t) = .ok t :=
  decodeTables_eq_ok.2 ⟨_, envelopeMatches_encode _ _, bodyMatches_encode t⟩

/-! ## Shape: every failure is reported, no row is defaulted -/

/-- The kind of a column of a schema table, as Julia writes it. -/
inductive ColumnKind
  /-- `"_id"`: the one-based row number. -/
  | id
  /-- A hom into `table`: a one-based part ID of that table. -/
  | hom (table : String)
  /-- A `Position` attribute: a one-based position. -/
  | position
  /-- A `Label` attribute: a string. -/
  | label
  /-- A `Ref` attribute: a `KernelRef` object. -/
  | ref

/-- The columns of each object table of `SchBayesNet`. -/
def bnColumns : String → List (String × ColumnKind)
  | "Variable" => [("_id", .id), ("variable_name", .label), ("space_ref", .ref)]
  | "State" => [("_id", .id), ("state_variable", .hom "Variable"), ("state_name", .label),
      ("state_position", .position)]
  | "Mechanism" => [("_id", .id), ("target", .hom "Variable"), ("mechanism_name", .label),
      ("kernel_ref", .ref)]
  | "Input" => [("_id", .id), ("input_mechanism", .hom "Mechanism"),
      ("input_variable", .hom "Variable"), ("input_position", .position)]
  | _ => []

/-- The number of rows of table `T` in the body (`0` if it is not an array). -/
def rowCount (body : JsonObject) (T : String) : Nat :=
  match body[T]? with
  | some (.arr a) => a.size
  | _ => 0

/-- The value `v` of a column of kind `κ` in row `k` is well formed. -/
def ColumnOk (body : JsonObject) (k : Nat) (v : Json) : ColumnKind → Prop
  | .id => v = natJson (k + 1)
  | .hom T => ∃ e, v = natJson e ∧ 1 ≤ e ∧ e ≤ rowCount body T
  | .position => ∃ e, v = natJson e ∧ 1 ≤ e
  | .label => ∃ s, v = .str s
  | .ref => ∃ ref, RefMatches v ref

/-- Every object table is an array; every row is an object with exactly its schema's columns, each
well formed. -/
def Shape (tables : List String) (columns : String → List (String × ColumnKind))
    (body : JsonObject) : Prop :=
  ∀ T ∈ tables, ∃ a : Array Json, body[T]? = some (.arr a) ∧
    ∀ k (hk : k < a.size), ∃ ro, a[k] = .obj ro ∧ ro.size = (columns T).length ∧
      ∀ c κ, (c, κ) ∈ columns T → ∃ v, ro[c]? = some v ∧ ColumnOk body k v κ

/-- A table of a well-shaped body is present and an array. -/
theorem Shape.table {tables : List String} {columns : String → List (String × ColumnKind)}
    {body : JsonObject} (h : Shape tables columns body) {T : String} (hT : T ∈ tables) :
    ∃ a : Array Json, body[T]? = some (.arr a) :=
  let ⟨a, ha, _⟩ := h T hT
  ⟨a, ha⟩

/-- Every row of a table of a well-shaped body is an object with exactly its schema's columns. -/
theorem Shape.row {tables : List String} {columns : String → List (String × ColumnKind)}
    {body : JsonObject} (h : Shape tables columns body) {T : String} (hT : T ∈ tables)
    {a : Array Json} (ha : body[T]? = some (.arr a)) {k : Nat} {row : Json}
    (hk : a[k]? = some row) : ∃ ro, row = .obj ro ∧ ro.size = (columns T).length := by
  obtain ⟨a', ha', hrows⟩ := h T hT
  rw [ha, Option.some.injEq, Json.arr.injEq] at ha'
  subst ha'
  have hlt : k < a.size := by
    by_contra hge
    rw [Array.getElem?_eq_none (Nat.le_of_not_lt hge)] at hk
    cases hk
  obtain ⟨ro, hro, hs, -⟩ := hrows k hlt
  rw [Array.getElem?_eq_getElem hlt, Option.some.injEq, hro] at hk
  exact ⟨ro, hk.symm, hs⟩

/-- Every column of every row of a well-shaped body is present and well formed. -/
theorem Shape.column {tables : List String} {columns : String → List (String × ColumnKind)}
    {body : JsonObject} (h : Shape tables columns body) {T : String} (hT : T ∈ tables)
    {a : Array Json} (ha : body[T]? = some (.arr a)) {k : Nat} {ro : JsonObject}
    (hk : a[k]? = some (.obj ro)) {c : String} {κ : ColumnKind} (hc : (c, κ) ∈ columns T) :
    ∃ v, ro[c]? = some v ∧ ColumnOk body k v κ := by
  obtain ⟨a', ha', hrows⟩ := h T hT
  rw [ha, Option.some.injEq, Json.arr.injEq] at ha'
  subst ha'
  have hlt : k < a.size := by
    by_contra hge
    rw [Array.getElem?_eq_none (Nat.le_of_not_lt hge)] at hk
    cases hk
  obtain ⟨ro', hro, -, hcols⟩ := hrows k hlt
  rw [Array.getElem?_eq_getElem hlt, Option.some.injEq, hro, Json.obj.injEq] at hk
  subst hk
  exact hcols c κ hc

/-- A hom value of a well-shaped body is the ID of an existing row of the referenced table. -/
theorem ColumnOk.hom_range {body : JsonObject} {k e : Nat} {T' : String}
    (h : ColumnOk body k (natJson e) (.hom T')) : 1 ≤ e ∧ e ≤ rowCount body T' := by
  obtain ⟨e', he', h1, h2⟩ := h
  have : e = e' := by
    have := congrArg jsonNat? he'
    simpa [jsonNat?, natJson] using this
  subst this
  exact ⟨h1, h2⟩

/-- A well-formed `_id`, hom or position value is a nonnegative JSON integer. -/
theorem ColumnOk.isNat {body : JsonObject} {k : Nat} {v : Json} {κ : ColumnKind}
    (h : ColumnOk body k v κ) (hκ : κ = .id ∨ κ = .position ∨ ∃ T', κ = .hom T') :
    (jsonNat? v).isSome := by
  rcases hκ with rfl | rfl | ⟨T', rfl⟩
  · rw [h]
    rfl
  · obtain ⟨e, rfl, -⟩ := h
    rfl
  · obtain ⟨e, rfl, -⟩ := h
    rfl

theorem rowCount_of_tableMatches {α : Type} {body : JsonObject} {name : String}
    {M : Nat → Json → α → Prop} {n : Nat} {f : Fin n → α} (h : TableMatches body name M n f) :
    rowCount body name = n := by
  obtain ⟨a, ha, hs, -⟩ := h
  simp [rowCount, ha, hs]

/-- Read row `k` off a matched table. -/
theorem TableMatches.row {α : Type} {body : JsonObject} {name : String}
    {M : Nat → Json → α → Prop} {n : Nat} {f : Fin n → α} (h : TableMatches body name M n f)
    {a : Array Json} (ha : body[name]? = some (.arr a)) (k : Nat) (hk : k < a.size) :
    ∃ i : Fin n, i.val = k ∧ M k a[k] (f i) := by
  obtain ⟨a', ha', hs, hrows⟩ := h
  rw [ha] at ha'
  cases ha'
  obtain ⟨x, hx, hm⟩ := hrows ⟨k, hs ▸ hk⟩
  rw [Array.getElem?_eq_getElem hk, Option.some.injEq] at hx
  subst hx
  exact ⟨⟨k, hs ▸ hk⟩, rfl, hm⟩

theorem natJson_le {n : Nat} {e : Fin n} : 1 ≤ e.val + 1 ∧ e.val + 1 ≤ n :=
  ⟨Nat.le_add_left 1 _, e.isLt⟩

/-- A decoded body has the shape of `SchBayesNet`. -/
theorem BodyMatches.shape {j : Json} {t : Tables} (h : BodyMatches j t) :
    ∃ body, j = .obj body ∧ Shape bnObjectTables bnColumns body := by
  obtain ⟨body, rfl, -, -, -, -, hV, hS, hM, hI⟩ := h
  refine ⟨body, rfl, ?_⟩
  have cV := rowCount_of_tableMatches hV
  have cM := rowCount_of_tableMatches hM
  intro T hT
  simp only [bnObjectTables, List.mem_cons, List.not_mem_nil, or_false] at hT
  rcases hT with rfl | rfl | rfl | rfl
  · obtain ⟨a, ha, -, -⟩ := id hV
    refine ⟨a, ha, fun k hk => ?_⟩
    obtain ⟨i, -, o, ho, hs, hid, hn, rj, hrj, href⟩ := hV.row ha k hk
    refine ⟨o, ho, hs, fun c κ hc => ?_⟩
    simp only [bnColumns, List.mem_cons, Prod.mk.injEq, List.not_mem_nil, or_false] at hc
    rcases hc with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    · exact ⟨_, hid, rfl⟩
    · exact ⟨_, hn, _, rfl⟩
    · exact ⟨_, hrj, _, href⟩
  · obtain ⟨a, ha, -, -⟩ := id hS
    refine ⟨a, ha, fun k hk => ?_⟩
    obtain ⟨i, -, o, ho, hs, hid, hv, hn, hp⟩ := hS.row ha k hk
    refine ⟨o, ho, hs, fun c κ hc => ?_⟩
    simp only [bnColumns, List.mem_cons, Prod.mk.injEq, List.not_mem_nil, or_false] at hc
    rcases hc with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    · exact ⟨_, hid, rfl⟩
    · exact ⟨_, hv, _, rfl, by rw [cV]; exact natJson_le⟩
    · exact ⟨_, hn, _, rfl⟩
    · exact ⟨_, hp, _, rfl, Nat.le_add_left 1 _⟩
  · obtain ⟨a, ha, -, -⟩ := id hM
    refine ⟨a, ha, fun k hk => ?_⟩
    obtain ⟨i, -, o, ho, hs, hid, hv, hn, rj, hrj, href⟩ := hM.row ha k hk
    refine ⟨o, ho, hs, fun c κ hc => ?_⟩
    simp only [bnColumns, List.mem_cons, Prod.mk.injEq, List.not_mem_nil, or_false] at hc
    rcases hc with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    · exact ⟨_, hid, rfl⟩
    · exact ⟨_, hv, _, rfl, by rw [cV]; exact natJson_le⟩
    · exact ⟨_, hn, _, rfl⟩
    · exact ⟨_, hrj, _, href⟩
  · obtain ⟨a, ha, -, -⟩ := id hI
    refine ⟨a, ha, fun k hk => ?_⟩
    obtain ⟨i, -, o, ho, hs, hid, hm, hv, hp⟩ := hI.row ha k hk
    refine ⟨o, ho, hs, fun c κ hc => ?_⟩
    simp only [bnColumns, List.mem_cons, Prod.mk.injEq, List.not_mem_nil, or_false] at hc
    rcases hc with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    · exact ⟨_, hid, rfl⟩
    · exact ⟨_, hm, _, rfl, by rw [cM]; exact natJson_le⟩
    · exact ⟨_, hv, _, rfl, by rw [cV]; exact natJson_le⟩
    · exact ⟨_, hp, _, rfl, Nat.le_add_left 1 _⟩

/-- The body of a successfully decoded document has the shape of `SchBayesNet`. -/
theorem decodeBody_shape {acset : JsonObject} {t : Tables}
    (h : decodeBody (.obj acset) = .ok t) : Shape bnObjectTables bnColumns acset := by
  obtain ⟨body, hb, hs⟩ := (decodeBody_eq_ok.1 h).shape
  cases hb
  exact hs

/-- With a well-formed envelope, the document decodes exactly as its body. -/
theorem decodeTables_of_envelope {j body : Json} (h : EnvelopeMatches bnFormat j body) :
    decodeTables j = decodeBody body := by
  unfold decodeTables
  rw [decodeEnvelope_eq_ok.2 h]
  rfl

/-- A document whose envelope is malformed (not an object, another format or schema version,
no `"acset"`) does not decode. -/
theorem decodeTables_error_of_envelope {j : Json} (h : ∀ body, ¬ EnvelopeMatches bnFormat j body)
    (t : Tables) : decodeTables j ≠ .ok t := fun hd =>
  let ⟨body, he, _⟩ := decodeTables_eq_ok.1 hd
  h body he

/-- **Failure: a missing table.** -/
theorem decodeBody_error_of_missing_table {acset : JsonObject} {T : String}
    (hT : T ∈ bnObjectTables ∨ T ∈ bnAttrTables) (h : acset[T]? = none) (t : Tables) :
    decodeBody (.obj acset) ≠ .ok t := by
  intro hd
  rcases hT with hT | hT
  · obtain ⟨a, ha, -⟩ := decodeBody_shape hd T hT
    rw [h] at ha
    cases ha
  · obtain ⟨body, hb, -, hL, hP, hR, -⟩ := decodeBody_eq_ok.1 hd
    cases hb
    simp only [bnAttrTables, List.mem_cons, List.not_mem_nil, or_false] at hT
    rcases hT with rfl | rfl | rfl <;> simp_all

/-- **Failure: a table that is not an array, or a nonempty attribute-variable table.** -/
theorem decodeBody_error_of_bad_table {acset : JsonObject} {T : String} {v : Json}
    (hT : T ∈ bnObjectTables ∨ T ∈ bnAttrTables) (h : acset[T]? = some v)
    (hv : ∀ a : Array Json, v = .arr a → T ∈ bnAttrTables ∧ a.size ≠ 0) (t : Tables) :
    decodeBody (.obj acset) ≠ .ok t := by
  intro hd
  rcases hT with hT | hT
  · obtain ⟨a, ha, -⟩ := decodeBody_shape hd T hT
    rw [h, Option.some.injEq] at ha
    obtain ⟨hT', -⟩ := hv a ha
    simp [bnObjectTables, bnAttrTables] at hT hT'
    rcases hT with rfl | rfl | rfl | rfl <;> simp_all
  · obtain ⟨body, hb, -, hL, hP, hR, -⟩ := decodeBody_eq_ok.1 hd
    cases hb
    simp only [bnAttrTables, List.mem_cons, List.not_mem_nil, or_false] at hT
    rcases hT with rfl | rfl | rfl
    · rw [hL, Option.some.injEq] at h
      exact (hv _ h.symm).2 rfl
    · rw [hP, Option.some.injEq] at h
      exact (hv _ h.symm).2 rfl
    · rw [hR, Option.some.injEq] at h
      exact (hv _ h.symm).2 rfl

/-- **Failure: a body with keys other than the seven tables.** -/
theorem decodeBody_error_of_size {acset : JsonObject} (h : acset.size ≠ 7) (t : Tables) :
    decodeBody (.obj acset) ≠ .ok t := by
  intro hd
  obtain ⟨body, hb, hs, -⟩ := decodeBody_eq_ok.1 hd
  cases hb
  exact h hs

/-- **Failure: a row that is not an object, or has missing or extra columns.** -/
theorem decodeBody_error_of_bad_row {acset : JsonObject} {T : String} {a : Array Json} {k : Nat}
    {row : Json} (hT : T ∈ bnObjectTables) (ha : acset[T]? = some (.arr a))
    (hk : a[k]? = some row)
    (hrow : ∀ ro : JsonObject, row = .obj ro → ro.size ≠ (bnColumns T).length) (t : Tables) :
    decodeBody (.obj acset) ≠ .ok t := by
  intro hd
  obtain ⟨a', ha', hrows⟩ := decodeBody_shape hd T hT
  rw [ha, Option.some.injEq, Json.arr.injEq] at ha'
  subst ha'
  have hlt : k < a.size := by
    by_contra hge
    rw [Array.getElem?_eq_none (Nat.le_of_not_lt hge)] at hk
    cases hk
  obtain ⟨ro, hro, hs, -⟩ := hrows k hlt
  rw [Array.getElem?_eq_getElem hlt, Option.some.injEq, hro] at hk
  exact hrow ro hk.symm hs

/-- **Failure: a missing column, or a column value that is not well formed** — of the wrong JSON
type, a hom ID outside `1..` the referenced table's row count, a position `0`, an `"_id"` other
than the row number, or a malformed `KernelRef`. -/
theorem decodeBody_error_of_bad_column {acset : JsonObject} {T : String} {a : Array Json}
    {k : Nat} {ro : JsonObject} {c : String} {κ : ColumnKind} (hT : T ∈ bnObjectTables)
    (ha : acset[T]? = some (.arr a)) (hk : a[k]? = some (.obj ro)) (hc : (c, κ) ∈ bnColumns T)
    (hbad : ∀ v, ro[c]? = some v → ¬ ColumnOk acset k v κ) (t : Tables) :
    decodeBody (.obj acset) ≠ .ok t := by
  intro hd
  obtain ⟨a', ha', hrows⟩ := decodeBody_shape hd T hT
  rw [ha, Option.some.injEq, Json.arr.injEq] at ha'
  subst ha'
  have hlt : k < a.size := by
    by_contra hge
    rw [Array.getElem?_eq_none (Nat.le_of_not_lt hge)] at hk
    cases hk
  obtain ⟨ro', hro, -, hcols⟩ := hrows k hlt
  rw [Array.getElem?_eq_getElem hlt, Option.some.injEq, hro, Json.obj.injEq] at hk
  subst hk
  obtain ⟨v, hv, hok⟩ := hcols c κ hc
  exact hbad v hv hok

/-- **Failure: a missing column.** -/
theorem decodeBody_error_of_missing_column {acset : JsonObject} {T : String} {a : Array Json}
    {k : Nat} {ro : JsonObject} {c : String} {κ : ColumnKind} (hT : T ∈ bnObjectTables)
    (ha : acset[T]? = some (.arr a)) (hk : a[k]? = some (.obj ro)) (hc : (c, κ) ∈ bnColumns T)
    (hmissing : ro[c]? = none) (t : Tables) : decodeBody (.obj acset) ≠ .ok t :=
  decodeBody_error_of_bad_column hT ha hk hc (fun v hv => by simp_all) t

/-- **Failure: a hom ID out of range** (`0`, or more than the referenced table's row count). -/
theorem decodeBody_error_of_hom_out_of_range {acset : JsonObject} {T T' : String}
    {a : Array Json} {k e : Nat} {ro : JsonObject} {c : String} (hT : T ∈ bnObjectTables)
    (ha : acset[T]? = some (.arr a)) (hk : a[k]? = some (.obj ro))
    (hc : (c, ColumnKind.hom T') ∈ bnColumns T) (hv : ro[c]? = some (natJson e))
    (hout : e = 0 ∨ rowCount acset T' < e) (t : Tables) : decodeBody (.obj acset) ≠ .ok t := by
  refine decodeBody_error_of_bad_column hT ha hk hc (fun v hv' => ?_) t
  rw [hv, Option.some.injEq] at hv'
  subst hv'
  rintro ⟨e', he', h1, h2⟩
  have : e = e' := by
    have := congrArg jsonNat? he'
    simpa [jsonNat?, natJson] using this
  omega

/-- **Failure: an ID, hom or position column that is not a nonnegative JSON integer.** -/
theorem decodeBody_error_of_not_integer {acset : JsonObject} {T : String} {a : Array Json}
    {k : Nat} {ro : JsonObject} {c : String} {κ : ColumnKind} {v : Json}
    (hT : T ∈ bnObjectTables) (ha : acset[T]? = some (.arr a)) (hk : a[k]? = some (.obj ro))
    (hc : (c, κ) ∈ bnColumns T) (hκ : κ = .id ∨ κ = .position ∨ ∃ T', κ = .hom T')
    (hv : ro[c]? = some v) (hnot : jsonNat? v = none) (t : Tables) :
    decodeBody (.obj acset) ≠ .ok t := by
  refine decodeBody_error_of_bad_column hT ha hk hc (fun v' hv' => ?_) t
  rw [hv, Option.some.injEq] at hv'
  subst hv'
  rcases hκ with rfl | rfl | ⟨T', rfl⟩
  · intro h
    rw [h] at hnot
    cases hnot
  · rintro ⟨e, rfl, -⟩
    cases hnot
  · rintro ⟨e, rfl, -⟩
    cases hnot

/-- **Failure: a `Label` column that is not a JSON string.** -/
theorem decodeBody_error_of_not_string {acset : JsonObject} {T : String} {a : Array Json}
    {k : Nat} {ro : JsonObject} {c : String} {v : Json} (hT : T ∈ bnObjectTables)
    (ha : acset[T]? = some (.arr a)) (hk : a[k]? = some (.obj ro))
    (hc : (c, ColumnKind.label) ∈ bnColumns T) (hv : ro[c]? = some v) (hnot : ∀ s, v ≠ .str s)
    (t : Tables) : decodeBody (.obj acset) ≠ .ok t := by
  refine decodeBody_error_of_bad_column hT ha hk hc (fun v' hv' => ?_) t
  rw [hv, Option.some.injEq] at hv'
  subst hv'
  rintro ⟨s, rfl⟩
  exact hnot s rfl

/-! ## Validity of the rows, and a computed causal rank -/

namespace Tables

/-- The structural checks of `Network.Valid` that do not mention the rank. -/
structure RowsValid (t : Tables) : Prop where
  state_positions : Positioned (fun s => (t.states s).var) (fun s => (t.states s).position)
  input_positions : Positioned (fun i => (t.inputs i).mechanism) (fun i => (t.inputs i).position)
  nonempty_states : ∀ v, 0 < Fintype.card {s : Fin t.ns // (t.states s).var = v}
  state_names : ∀ s u, (t.states s).var = (t.states u).var →
    (t.states s).name = (t.states u).name → s = u
  generators : Function.Bijective (fun m => (t.mechanisms m).target)

theorem rowsValid_iff (t : Tables) : t.RowsValid ↔
    Positioned (fun s => (t.states s).var) (fun s => (t.states s).position) ∧
    Positioned (fun i => (t.inputs i).mechanism) (fun i => (t.inputs i).position) ∧
    (∀ v, 0 < Fintype.card {s : Fin t.ns // (t.states s).var = v}) ∧
    (∀ s u, (t.states s).var = (t.states u).var → (t.states s).name = (t.states u).name → s = u) ∧
    Function.Bijective (fun m => (t.mechanisms m).target) :=
  ⟨fun h => ⟨h.1, h.2, h.3, h.4, h.5⟩, fun h => ⟨h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2⟩⟩

instance (t : Tables) : Decidable t.RowsValid := by
  letI : Decidable (Function.Bijective (fun m => (t.mechanisms m).target)) := by
    unfold Function.Bijective Function.Injective Function.Surjective
    infer_instance
  exact decidable_of_iff _ (rowsValid_iff t).symm

/-- `rank` is a causal rank: injective, and every input variable ranks below the target of its
mechanism. -/
def CausalRank (t : Tables) (rank : Fin t.nv → Fin t.nv) : Prop :=
  Function.Injective rank ∧
    ∀ i, rank (t.inputs i).var < rank (t.mechanisms (t.inputs i).mechanism).target

/-- Some causal rank exists: the mechanism inputs have no directed cycle. -/
def Acyclic (t : Tables) : Prop := ∃ rank, t.CausalRank rank

/-- `v` may be placed after `placed`: every input of every mechanism targeting `v` reads a placed
variable. -/
def ready (t : Tables) (placed : List (Fin t.nv)) (v : Fin t.nv) : Bool :=
  decide (∀ i : Fin t.ni, (t.mechanisms (t.inputs i).mechanism).target = v →
    (t.inputs i).var ∈ placed)

/-- Place `k` more variables after `acc`, each time the first (by part ID) unplaced ready one. -/
def place (t : Tables) : Nat → List (Fin t.nv) → Option (List (Fin t.nv))
  | 0, acc => some acc
  | k + 1, acc =>
    match (List.finRange t.nv).find? (fun v => !(acc.contains v) && t.ready acc v) with
    | none => none
    | some v => t.place k (acc ++ [v])

/-- The placement order of all variables, when one exists. -/
def order (t : Tables) : Option (List (Fin t.nv)) := t.place t.nv []

/-- The rank of a variable is its index in the placement order. -/
def computeRank (t : Tables) : Option (Fin t.nv → Fin t.nv) :=
  match t.order with
  | none => none
  | some l => if h : ∀ v : Fin t.nv, l.idxOf v < t.nv then some (fun v => ⟨l.idxOf v, h v⟩)
      else none

/-- Every placed variable was ready when it was placed. -/
def PlacedOk (t : Tables) (l : List (Fin t.nv)) : Prop :=
  l.Nodup ∧ ∀ j (hj : j < l.length) (i : Fin t.ni),
    (t.mechanisms (t.inputs i).mechanism).target = l[j] → (t.inputs i).var ∈ l.take j

theorem placedOk_snoc {t : Tables} {acc : List (Fin t.nv)} {v : Fin t.nv} (h : t.PlacedOk acc)
    (hv : v ∉ acc) (hr : t.ready acc v = true) : t.PlacedOk (acc ++ [v]) := by
  refine ⟨List.nodup_append.2 ⟨h.1, List.nodup_singleton v, ?_⟩, ?_⟩
  · intro a ha b hb
    rw [List.mem_singleton] at hb
    subst hb
    rintro rfl
    exact hv ha
  · intro j hj i hi
    rw [List.length_append, List.length_singleton] at hj
    by_cases hlt : j < acc.length
    · rw [List.getElem_append_left hlt] at hi
      rw [List.take_append_of_le_length hlt.le]
      exact h.2 j hlt i hi
    · have hj' : j = acc.length := by omega
      rw [List.getElem_concat_length hj'] at hi
      rw [List.take_left' hj'.symm]
      exact of_decide_eq_true hr i hi

theorem place_spec (t : Tables) :
    ∀ (k : Nat) (acc l : List (Fin t.nv)), t.place k acc = some l → t.PlacedOk acc →
      t.PlacedOk l ∧ l.length = acc.length + k
  | 0, acc, l, h, hacc => by
    simp only [place, Option.some.injEq] at h
    subst h
    exact ⟨hacc, rfl⟩
  | k + 1, acc, l, h, hacc => by
    unfold place at h
    split at h
    · cases h
    · rename_i v hv
      have hp := List.find?_some hv
      simp only [Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at hp
      have hnot : v ∉ acc := by simpa using hp.1
      obtain ⟨hl, hlen⟩ := place_spec t k _ l h (placedOk_snoc hacc hnot hp.2)
      refine ⟨hl, ?_⟩
      rw [hlen, List.length_append, List.length_singleton]
      omega

theorem place_complete {t : Tables} (hac : t.Acyclic) :
    ∀ (k : Nat) (acc : List (Fin t.nv)), acc.Nodup → acc.length + k ≤ t.nv →
      (t.place k acc).isSome
  | 0, acc, _, _ => rfl
  | k + 1, acc, hnd, hlen => by
    obtain ⟨rank, hinj, hcausal⟩ := hac
    have hne : (Finset.univ.filter (fun v => v ∉ acc)).Nonempty := by
      by_contra hempty
      rw [Finset.not_nonempty_iff_eq_empty, Finset.filter_eq_empty_iff] at hempty
      have hsub : (Finset.univ : Finset (Fin t.nv)) ⊆ acc.toFinset := fun v _ =>
        List.mem_toFinset.2 (not_not.1 (hempty (Finset.mem_univ v)))
      have hc := Finset.card_le_card hsub
      rw [Finset.card_univ, Fintype.card_fin, List.toFinset_card_of_nodup hnd] at hc
      omega
    obtain ⟨v, hv, hmin⟩ := Finset.exists_min_image _ rank hne
    rw [Finset.mem_filter] at hv
    have hready : t.ready acc v = true := by
      apply decide_eq_true
      intro i hi
      by_contra hnot
      have h1 := hmin (t.inputs i).var (Finset.mem_filter.2 ⟨Finset.mem_univ _, hnot⟩)
      have h2 := hcausal i
      rw [hi] at h2
      exact absurd h1 (not_le_of_gt h2)
    unfold place
    split
    · rename_i hfind
      rw [List.find?_eq_none] at hfind
      exact absurd (by simp [hv.2, hready]) (hfind v (List.mem_finRange v))
    · rename_i w hw
      have hp := List.find?_some hw
      simp only [Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at hp
      have hnot : w ∉ acc := by simpa using hp.1
      refine place_complete ⟨rank, hinj, hcausal⟩ k _ ?_ ?_
      · refine List.nodup_append.2 ⟨hnd, List.nodup_singleton w, ?_⟩
        intro a ha b hb
        rw [List.mem_singleton] at hb
        subst hb
        rintro rfl
        exact hnot ha
      · rw [List.length_append, List.length_singleton]
        omega

theorem order_spec {t : Tables} {l : List (Fin t.nv)} (h : t.order = some l) :
    t.PlacedOk l ∧ l.length = t.nv ∧ ∀ v, v ∈ l := by
  obtain ⟨hok, hlen⟩ := t.place_spec t.nv [] l h ⟨List.nodup_nil, by simp⟩
  rw [List.length_nil, Nat.zero_add] at hlen
  refine ⟨hok, hlen, fun v => ?_⟩
  have huniv : l.toFinset = Finset.univ := Finset.eq_univ_of_card _ (by
    rw [List.toFinset_card_of_nodup hok.1, hlen, Fintype.card_fin])
  exact List.mem_toFinset.1 (huniv ▸ Finset.mem_univ v)

/-- **The computed rank is a causal rank.** -/
theorem computeRank_sound {t : Tables} {rk : Fin t.nv → Fin t.nv}
    (h : t.computeRank = some rk) : t.CausalRank rk := by
  unfold computeRank at h
  split at h
  · cases h
  · rename_i l hl
    split_ifs at h with hidx
    cases h
    obtain ⟨⟨hnd, hok⟩, hlen, hmem⟩ := order_spec hl
    constructor
    · intro v w hvw
      exact (List.idxOf_inj (hmem v)).1 (congrArg Fin.val hvw)
    · intro i
      rw [Fin.lt_def]
      have hj : l.idxOf (t.mechanisms (t.inputs i).mechanism).target < l.length :=
        List.idxOf_lt_length_iff.2 (hmem _)
      have hu := hok _ hj i (List.getElem_idxOf hj).symm
      obtain ⟨j', hj', hget⟩ := List.mem_take_iff_getElem.1 hu
      simp only
      rw [← hget, hnd.idxOf_getElem]
      omega

/-- **The computed rank exists whenever some causal rank does.** -/
theorem computeRank_complete {t : Tables} (h : t.Acyclic) : ∃ rk, t.computeRank = some rk := by
  obtain ⟨l, hl⟩ := Option.isSome_iff_exists.1 (place_complete h t.nv [] List.nodup_nil (by simp))
  have hl' : t.order = some l := hl
  obtain ⟨-, hlen, hmem⟩ := order_spec hl'
  have hidx : ∀ v : Fin t.nv, l.idxOf v < t.nv := fun v =>
    lt_of_lt_of_eq (List.idxOf_lt_length_iff.2 (hmem v)) hlen
  unfold computeRank
  rw [hl']
  exact ⟨_, dif_pos hidx⟩

theorem acyclic_iff_computeRank (t : Tables) : t.Acyclic ↔ t.computeRank.isSome := by
  constructor
  · intro h
    obtain ⟨rk, hrk⟩ := computeRank_complete h
    rw [hrk]
    rfl
  · intro h
    obtain ⟨rk, hrk⟩ := Option.isSome_iff_exists.1 h
    exact ⟨rk, computeRank_sound hrk⟩

instance (t : Tables) : Decidable t.Acyclic := decidable_of_iff _ (acyclic_iff_computeRank t).symm

/-- The rows are valid and acyclic: decidable, and exactly the existence of a valid network on
these rows (`valid_iff_exists`). -/
def Valid (t : Tables) : Prop := t.RowsValid ∧ t.Acyclic

instance (t : Tables) : Decidable t.Valid := inferInstanceAs (Decidable (_ ∧ _))

/-- The network on these rows with the given rank. -/
def withRank (t : Tables) (rank : Fin t.nv → Fin t.nv) : Network :=
  ⟨t.nv, t.ns, t.nm, t.ni, t.vars, t.states, t.mechanisms, t.inputs, rank⟩

end Tables

namespace Network

/-- The rows of a network, forgetting the rank. -/
def tables (r : Network) : Tables :=
  ⟨r.nv, r.ns, r.nm, r.ni, r.vars, r.states, r.mechanisms, r.inputs⟩

@[simp] theorem tables_withRank (t : Tables) (rank : Fin t.nv → Fin t.nv) :
    (t.withRank rank).tables = t := rfl

theorem withRank_tables (r : Network) : r.tables.withRank r.rank = r := rfl

/-- `Network.Valid` is the row checks plus a causal rank. -/
theorem valid_iff_tables (r : Network) :
    r.Valid ↔ r.tables.RowsValid ∧ r.tables.CausalRank r.rank :=
  ⟨fun h => ⟨⟨h.1, h.2, h.3, h.4, h.5⟩, h.6, h.7⟩,
    fun h => ⟨h.1.1, h.1.2, h.1.3, h.1.4, h.1.5, h.2.1, h.2.2⟩⟩

end Network

theorem Tables.valid_iff_exists (t : Tables) : t.Valid ↔ ∃ rank, (t.withRank rank).Valid := by
  constructor
  · rintro ⟨hrows, rank, hrank⟩
    exact ⟨rank, (Network.valid_iff_tables _).2 ⟨hrows, hrank⟩⟩
  · rintro ⟨rank, h⟩
    obtain ⟨hrows, hrank⟩ := (Network.valid_iff_tables _).1 h
    exact ⟨hrows, rank, hrank⟩

/-- `compile` reads the rows, never the rank: two valid networks on the same rows compile to the
same finite network. -/
theorem Network.compile_eq_of_tables_eq {r r' : Network} (h : r.Valid) (h' : r'.Valid)
    (he : r.tables = r'.tables) : r.compile h = r'.compile h' := by
  obtain ⟨nv, ns, nm, ni, vars, states, mechanisms, inputs, rank⟩ := r
  obtain ⟨nv', ns', nm', ni', vars', states', mechanisms', inputs', rank'⟩ := r'
  simp only [tables, Tables.mk.injEq] at he
  obtain ⟨rfl, rfl, rfl, rfl, he1, he2, he3, he4⟩ := he
  simp only [heq_eq_eq] at he1 he2 he3 he4
  subst he1 he2 he3 he4
  rfl

/-! ## Decoding to a checked network -/

/-- Decode the rows and attach the computed causal rank; a cyclic document is an error. -/
def decode (j : Json) : Except String Network := do
  let t ← decodeTables j
  match t.computeRank with
  | some rank => pure (t.withRank rank)
  | none => throw "Mechanism/Input: the mechanism inputs form a directed cycle; no causal rank"

/-- The JSON of a network: its rows (the rank is not stored). -/
def encode (r : Network) : Json := encodeTables r.tables

theorem decode_eq_ok {j : Json} {r : Network} :
    decode j = .ok r ↔ decodeTables j = .ok r.tables ∧ r.tables.computeRank = some r.rank := by
  unfold decode
  rw [bind_eq_ok]
  constructor
  · rintro ⟨t, ht, h⟩
    split at h
    · rename_i rank hrank
      rw [pure_eq_ok] at h
      subst h
      exact ⟨ht, hrank⟩
    · exact absurd h throw_ne_ok
  · rintro ⟨h1, h2⟩
    refine ⟨r.tables, h1, ?_⟩
    rw [h2]
    rfl

/-- **Round trip for networks**: exact when the network carries the computed rank. -/
theorem decode_encode_of_rank {r : Network} (h : r.tables.computeRank = some r.rank) :
    decode (encode r) = .ok r :=
  decode_eq_ok.2 ⟨decodeTables_encodeTables _, h⟩

/-- **Round trip for networks**, any acyclic rows: the rows come back exactly, with the computed
rank. -/
theorem decode_encode {r : Network} (h : r.tables.Acyclic) :
    ∃ r', decode (encode r) = .ok r' ∧ r'.tables = r.tables ∧ r'.tables.CausalRank r'.rank := by
  obtain ⟨rank, hrank⟩ := Tables.computeRank_complete h
  exact ⟨r.tables.withRank rank, decode_eq_ok.2 ⟨decodeTables_encodeTables _, hrank⟩, rfl,
    Tables.computeRank_sound hrank⟩

/-- **The checked decoder**: decode, attach the computed rank, and run `Network.check`. -/
def decodeChecked (j : Json) : Option (Σ' r : Network, r.Valid) :=
  match decode j with
  | .ok r => if h : r.check = true then some ⟨r, (Network.check_iff r).1 h⟩ else none
  | .error _ => none

theorem decodeChecked_eq_some {j : Json} {r : Network} {h : r.Valid} :
    decodeChecked j = some ⟨r, h⟩ ↔ decode j = .ok r := by
  unfold decodeChecked
  constructor
  · intro hd
    split at hd
    · rename_i r' hr'
      split_ifs at hd
      simp only [Option.some.injEq, PSigma.mk.injEq] at hd
      obtain ⟨rfl, -⟩ := hd
      exact hr'
    · cases hd
  · intro hd
    rw [hd]
    simp only
    rw [dif_pos ((Network.check_iff r).2 h)]

/-- **Soundness**: a successful checked decode is a valid network whose rows are exactly the
document's (`decodeTables_eq_ok`), with the computed rank. -/
theorem decodeChecked_sound {j : Json} {r : Network} {h : r.Valid}
    (hd : decodeChecked j = some ⟨r, h⟩) :
    decodeTables j = .ok r.tables ∧ r.tables.computeRank = some r.rank :=
  decode_eq_ok.1 (decodeChecked_eq_some.1 hd)

/-- **Exactly the valid documents decode**: the checked decoder succeeds iff the document's rows
decode and are valid (some causal rank exists). -/
theorem decodeChecked_isSome_iff {j : Json} :
    (decodeChecked j).isSome ↔ ∃ t, decodeTables j = .ok t ∧ t.Valid := by
  constructor
  · intro hs
    obtain ⟨⟨r, h⟩, hr⟩ := Option.isSome_iff_exists.1 hs
    obtain ⟨ht, -⟩ := decodeChecked_sound hr
    obtain ⟨hrows, hrank⟩ := (Network.valid_iff_tables r).1 h
    exact ⟨r.tables, ht, hrows, r.rank, hrank⟩
  · rintro ⟨t, ht, hrows, hac⟩
    obtain ⟨rank, hrank⟩ := Tables.computeRank_complete hac
    have hv : (t.withRank rank).Valid :=
      (Network.valid_iff_tables _).2 ⟨hrows, Tables.computeRank_sound hrank⟩
    have hd : decodeChecked j = some ⟨t.withRank rank, hv⟩ :=
      decodeChecked_eq_some.2 (decode_eq_ok.2 ⟨ht, hrank⟩)
    rw [hd]
    rfl

/-- **Completeness on encoded networks**: every valid network is recovered from its JSON, rows
exactly, and with the same compiled finite network. -/
theorem decodeChecked_encode {r : Network} (h : r.Valid) :
    ∃ r' h', decodeChecked (encode r) = some ⟨r', h'⟩ ∧ r'.tables = r.tables ∧
      r'.compile h' = r.compile h := by
  obtain ⟨hrows, hrank⟩ := (Network.valid_iff_tables r).1 h
  obtain ⟨rank, hrk⟩ := Tables.computeRank_complete (t := r.tables) ⟨r.rank, hrank⟩
  have hv : (r.tables.withRank rank).Valid :=
    (Network.valid_iff_tables _).2 ⟨hrows, Tables.computeRank_sound hrk⟩
  exact ⟨_, hv, decodeChecked_eq_some.2 (decode_eq_ok.2 ⟨decodeTables_encodeTables _, hrk⟩), rfl,
    Network.compile_eq_of_tables_eq hv h rfl⟩

/-! ## What a successful checked decode guarantees -/

namespace Tables

/-- The label at zero-based position `a` of variable `v`: the name of the first `State` row of
`v` at that position (computable; `Network.labelAt_eq`). -/
def labelAt (t : Tables) (v : Fin t.nv) (a : Nat) : Option String :=
  ((List.finRange t.ns).find? fun s => (t.states s).var = v && (t.states s).position = a).map
    fun s => (t.states s).name

/-- The variable in zero-based slot `j` of mechanism `m`: that of the first `Input` row of `m` at
that position (computable; `Network.slotAt_eq`). -/
def slotAt (t : Tables) (m : Fin t.nm) (j : Nat) : Option (Fin t.nv) :=
  ((List.finRange t.ni).find? fun i => (t.inputs i).mechanism = m && (t.inputs i).position = j).map
    fun i => (t.inputs i).var

end Tables

namespace Network

/-- On valid rows, `labelAt` is the label of `compile`'s state at that position. -/
theorem labelAt_eq (r : Network) (h : r.Valid) (v : Fin r.nv) (a : Fin (r.stateCount v)) :
    r.tables.labelAt v a.val = some (r.stateLabel h v a) := by
  set s := ((r.stateOrder h v).symm a).val with hs
  have hvar : (r.states s).var = v := ((r.stateOrder h v).symm a).property
  have hpos : (r.states s).position = a.val := r.state_position h v a
  have hsome : ((List.finRange r.ns).find? fun s =>
      (r.states s).var = v && (r.states s).position = a.val).isSome :=
    List.find?_isSome.2 ⟨s, List.mem_finRange s, by simp [hvar, hpos]⟩
  obtain ⟨s', hs'⟩ := Option.isSome_iff_exists.1 hsome
  have hp := List.find?_some hs'
  simp only [Bool.and_eq_true, decide_eq_true_eq] at hp
  have he : s' = s := h.state_positions.2 s' s (hp.1.trans hvar.symm) (hp.2.trans hpos.symm)
  subst he
  unfold Tables.labelAt
  exact congrArg (Option.map fun s => (r.states s).name) hs'

/-- On valid rows, `slotAt` is `compile`'s slot variable. -/
theorem slotAt_eq (r : Network) (h : r.Valid) (m : Fin r.nm) (j : Fin (r.inputCount m)) :
    r.tables.slotAt m j.val = some (r.slotVariable h m j) := by
  set i := ((r.inputOrder h m).symm j).val with hi
  have hmech : (r.inputs i).mechanism = m := ((r.inputOrder h m).symm j).property
  have hpos : (r.inputs i).position = j.val := r.slot_position h m j
  have hsome : ((List.finRange r.ni).find? fun i =>
      (r.inputs i).mechanism = m && (r.inputs i).position = j.val).isSome :=
    List.find?_isSome.2 ⟨i, List.mem_finRange i, by simp [hmech, hpos]⟩
  obtain ⟨i', hi'⟩ := Option.isSome_iff_exists.1 hsome
  have hp := List.find?_some hi'
  simp only [Bool.and_eq_true, decide_eq_true_eq] at hp
  have he : i' = i := h.input_positions.2 i' i (hp.1.trans hmech.symm) (hp.2.trans hpos.symm)
  subst he
  unfold Tables.slotAt
  exact congrArg (Option.map fun i => (r.inputs i).var) hi'

end Network

/-- **States in the document.** After a successful checked decode, for every variable `v` and
every state `a` of `compile`'s space for `v`, the document's `"State"` table has a row with
`state_variable = v + 1`, `state_position = a + 1` and `state_name` the label of `a`. -/
theorem decodeChecked_stateLabel {j : Json} {r : Network} {h : r.Valid}
    (hd : decodeChecked j = some ⟨r, h⟩) (v : Fin r.nv) (a : Fin (r.stateCount v)) :
    ∃ (acset : JsonObject) (arr : Array Json), EnvelopeMatches bnFormat j (.obj acset) ∧
      acset["State"]? = some (.arr arr) ∧
      ∃ (k : Nat) (ro : JsonObject), arr[k]? = some (.obj ro) ∧ ro["state_variable"]? = some (natJson (v.val + 1)) ∧
        ro["state_position"]? = some (natJson (a.val + 1)) ∧
        ro["state_name"]? = some (.str (r.stateLabel h v a)) := by
  obtain ⟨body, henv, acset, rfl, -, -, -, -, -, hS, -, -⟩ :=
    decodeTables_eq_ok.1 (decodeChecked_sound hd).1
  obtain ⟨arr, harr, -, hrows⟩ := hS
  set s := (r.stateOrder h v).symm a
  obtain ⟨x, hx, ro, rfl, -, -, hvar, hname, hpos⟩ := hrows s.val
  refine ⟨acset, arr, henv, harr, s.val.val, ro, hx, ?_, ?_, hname⟩
  · rw [hvar]
    exact congrArg (fun w : Fin r.nv => some (natJson (w.val + 1))) s.property
  · rw [hpos]
    exact congrArg (fun p => some (natJson (p + 1))) (r.state_position h v a)

/-- **Inputs in the document.** After a successful checked decode, for every mechanism `m` and
slot `j` of `compile`'s ordered inputs, the document's `"Input"` table has a row with
`input_mechanism = m + 1`, `input_position = j + 1` and `input_variable` the slot's variable
plus one. -/
theorem decodeChecked_slotVariable {j : Json} {r : Network} {h : r.Valid}
    (hd : decodeChecked j = some ⟨r, h⟩) (m : Fin r.nm) (slot : Fin (r.inputCount m)) :
    ∃ (acset : JsonObject) (arr : Array Json), EnvelopeMatches bnFormat j (.obj acset) ∧
      acset["Input"]? = some (.arr arr) ∧
      ∃ (k : Nat) (ro : JsonObject), arr[k]? = some (.obj ro) ∧ ro["input_mechanism"]? = some (natJson (m.val + 1)) ∧
        ro["input_position"]? = some (natJson (slot.val + 1)) ∧
        ro["input_variable"]? = some (natJson ((r.slotVariable h m slot).val + 1)) := by
  obtain ⟨body, henv, acset, rfl, -, -, -, -, -, -, -, hI⟩ :=
    decodeTables_eq_ok.1 (decodeChecked_sound hd).1
  obtain ⟨arr, harr, -, hrows⟩ := hI
  set i := (r.inputOrder h m).symm slot
  obtain ⟨x, hx, ro, rfl, -, -, hmech, hvar, hpos⟩ := hrows i.val
  refine ⟨acset, arr, henv, harr, i.val.val, ro, hx, ?_, ?_, hvar⟩
  · rw [hmech]
    exact congrArg (fun w : Fin r.nm => some (natJson (w.val + 1))) i.property
  · rw [hpos]
    exact congrArg (fun p => some (natJson (p + 1))) (r.slot_position h m slot)

/-- **The compiled network.** A successful checked decode compiles to a closed finite network with
a topological order, whose parent sets are the slot images. -/
theorem decodeChecked_compile {j : Json} {r : Network} {h : r.Valid}
    (_hd : decodeChecked j = some ⟨r, h⟩) :
    (r.compile h).Closed ∧ Nonempty (r.compile h).TopoOrder ∧
      ∀ m, Finset.univ.image (r.slotVariable h m) = (r.compile h).parents m :=
  ⟨r.compile_closed h, ⟨r.topological h⟩, r.slot_image h⟩

end BayesianNetworksProofs.Raw
