import BayesianNetworksProofs.Finite.JsonRecords

/-!
# SA-Pass shadow module: the ACSets JSON decoder

Claim `bn.json-decoder`, from `Raw.decodeTables_eq_ok` and `Raw.decodeTables_encodeTables`:
"`decodeTables_eq_ok` proves that the decoder succeeds with rows `t` exactly when every table of
the document has `t`'s row count and every column of every row holds `t`'s value, hom columns as
one-based part IDs and positions one-based, and `decodeTables_encodeTables` that decoding the
encoded rows gives them back."

"The decoder" is `decodeTables` on a parsed `Json` tree; "the document" is the `"acset"` body
of a `"bayesnet-acset"` envelope (`EnvelopeMatches`); "every table … every column" is
`BodyMatches`. The shadows split "exactly when" into its two directions, pin the row counts
(`rowCount`) and, for the `State` table, the one-based hom and position encodings explicitly,
and state the round trip.
-/

set_option autoImplicit false

namespace BayesianNetworksProofs.Shadows.JsonDecoder

open Lean (Json)
open BayesianNetworksProofs.Raw

/-- `decodeTables_eq_ok` and `decodeTables_encodeTables`, restated abstractly. -/
abbrev Candidate : Prop :=
  (∀ (j : Json) (t : Tables),
      decodeTables j = .ok t ↔ ∃ body, EnvelopeMatches bnFormat j body ∧ BodyMatches body t) ∧
    ∀ t : Tables, decodeTables (encodeTables t) = .ok t

/-- "succeeds with rows `t` only when every table … every column … holds `t`'s value". -/
abbrev Shadow1 : Prop :=
  ∀ (j : Json) (t : Tables), decodeTables j = .ok t →
    ∃ body, EnvelopeMatches bnFormat j body ∧ BodyMatches body t

/-- "exactly when": such a document decodes to `t`. -/
abbrev Shadow2 : Prop :=
  ∀ (j : Json) (t : Tables), (∃ body, EnvelopeMatches bnFormat j body ∧ BodyMatches body t) →
    decodeTables j = .ok t

/-- "every table of the document has `t`'s row count". -/
abbrev Shadow3 : Prop :=
  ∀ (j : Json) (t : Tables), decodeTables j = .ok t →
    ∃ acset : JsonObject, EnvelopeMatches bnFormat j (.obj acset) ∧
      rowCount acset "Variable" = t.nv ∧ rowCount acset "State" = t.ns ∧
      rowCount acset "Mechanism" = t.nm ∧ rowCount acset "Input" = t.ni

/-- "hom columns as one-based part IDs and positions one-based", on the `State` table. -/
abbrev Shadow4 : Prop :=
  ∀ (j : Json) (t : Tables), decodeTables j = .ok t →
    ∃ (acset : JsonObject) (arr : Array Json), EnvelopeMatches bnFormat j (.obj acset) ∧
      acset["State"]? = some (.arr arr) ∧
      ∀ i : Fin t.ns, ∃ ro : JsonObject, arr[i.val]? = some (.obj ro) ∧
        ro["state_variable"]? = some (natJson ((t.states i).var.val + 1)) ∧
        ro["state_position"]? = some (natJson ((t.states i).position + 1))

/-- "decoding the encoded rows gives them back". -/
abbrev Shadow5 : Prop := ∀ t : Tables, decodeTables (encodeTables t) = .ok t

theorem forward1 : Candidate → Shadow1 := fun h j t => (h.1 j t).1

theorem forward2 : Candidate → Shadow2 := fun h j t => (h.1 j t).2

theorem forward3 : Candidate → Shadow3 := fun h j t hd => by
  obtain ⟨body, henv, acset, rfl, -, -, -, -, hV, hS, hM, hI⟩ := (h.1 j t).1 hd
  exact ⟨acset, henv, rowCount_of_tableMatches hV, rowCount_of_tableMatches hS,
    rowCount_of_tableMatches hM, rowCount_of_tableMatches hI⟩

theorem forward4 : Candidate → Shadow4 := fun h j t hd => by
  obtain ⟨body, henv, acset, rfl, -, -, -, -, -, ⟨arr, harr, -, hrows⟩, -, -⟩ := (h.1 j t).1 hd
  refine ⟨acset, arr, henv, harr, fun i => ?_⟩
  obtain ⟨x, hx, ro, rfl, -, -, hv, -, hp⟩ := hrows i
  exact ⟨ro, hx, hv, hp⟩

theorem forward5 : Candidate → Shadow5 := fun h => h.2

theorem backward : Shadow1 → Shadow2 → Shadow3 → Shadow4 → Shadow5 → Candidate :=
  fun s1 s2 _ _ s5 => ⟨fun j t => ⟨s1 j t, s2 j t⟩, s5⟩

/-- SA-Pass anchor: the cited theorems prove `Candidate` as stated. -/
theorem anchor : Candidate :=
  ⟨fun _ _ => decodeTables_eq_ok, decodeTables_encodeTables⟩

end BayesianNetworksProofs.Shadows.JsonDecoder
