import BayesianNetworksProofs.Numeric.Binary64

/-!
# SA-Pass shadow module: correct rounding to binary64

Claim `bn.nearest-binary64`, from `nearestBinary64_roundsTo`. The prose promises that, for every
rational `q`, the transcribed `_nearest_binary64` returns a 64-bit word that is the infinity of
the sign of `q` exactly when `|q| ≥ 2^1024 - 2^970`, and otherwise a finite word with the sign
of `q`, a result of zero included, at least as near `q` as every finite binary64 word, with an
even significand when a finite word of a different value is equally near.

The candidate packages these as the structure `RoundsTo` with the named constant
`overflowThreshold`. The shadows state each promise separately and spell the threshold out as
`2 ^ 1024 - 2 ^ 970`, so a change to either definition fails the checkers. The candidate has no
hypotheses: it quantifies over every rational.
-/

namespace BayesianNetworksProofs.Shadows.NearestBinary64

open BayesianNetworksProofs.Binary64

/-- `nearestBinary64_roundsTo`, restated abstractly: no hypotheses. -/
abbrev Candidate : Prop := ∀ q : ℚ, RoundsTo q (nearestBinary64 q)

/-- "returns a 64-bit word". -/
abbrev Shadow1 : Prop := ∀ q : ℚ, nearestBinary64 q < 2 ^ 64

/-- "the infinity of the sign of `q` ... when `|q| ≥ 2^1024 - 2^970`". -/
abbrev Shadow2 : Prop := ∀ q : ℚ, (2 : ℚ) ^ 1024 - 2 ^ 970 ≤ |q| →
  decode (nearestBinary64 q) = .infinity (decide (q < 0))

/-- "exactly when": below the threshold the word is finite. -/
abbrev Shadow3 : Prop := ∀ q : ℚ, |q| < (2 : ℚ) ^ 1024 - 2 ^ 970 →
  field (nearestBinary64 q) ≠ 2047

/-- "a finite word with the sign of `q`". -/
abbrev Shadow4 : Prop := ∀ q : ℚ, |q| < (2 : ℚ) ^ 1024 - 2 ^ 970 →
  signBit (nearestBinary64 q) = decide (q < 0)

/-- "a result of zero included": a result that rounds to zero keeps the sign of `q`. -/
abbrev Shadow5 : Prop := ∀ q : ℚ, |q| < (2 : ℚ) ^ 1024 - 2 ^ 970 →
  value (nearestBinary64 q) = 0 → signBit (nearestBinary64 q) = decide (q < 0)

/-- "at least as near `q` as the value of every finite binary64 word". -/
abbrev Shadow6 : Prop := ∀ q : ℚ, |q| < (2 : ℚ) ^ 1024 - 2 ^ 970 →
  ∀ w', IsFinite w' → |value (nearestBinary64 q) - q| ≤ |value w' - q|

/-- "whose significand is even when a finite word of a different value is equally near". -/
abbrev Shadow7 : Prop := ∀ q : ℚ, |q| < (2 : ℚ) ^ 1024 - 2 ^ 970 →
  ∀ w', IsFinite w' → |value w' - q| = |value (nearestBinary64 q) - q| →
    value w' ≠ value (nearestBinary64 q) → Even (significand (nearestBinary64 q))

theorem forward1 : Candidate → Shadow1 := fun h q => (h q).word

theorem forward2 : Candidate → Shadow2 := fun h q hq => (h q).overflow hq

theorem forward3 : Candidate → Shadow3 := fun h q hq => (h q).finite hq

theorem forward4 : Candidate → Shadow4 := fun h q hq => (h q).sign hq

theorem forward5 : Candidate → Shadow5 := fun h q hq _ => (h q).sign hq

theorem forward6 : Candidate → Shadow6 := fun h q hq => (h q).nearest hq

theorem forward7 : Candidate → Shadow7 := fun h q hq => (h q).tiesToEven hq

theorem backward : Shadow1 → Shadow2 → Shadow3 → Shadow4 → Shadow5 → Shadow6 → Shadow7 →
    Candidate := fun s1 s2 s3 s4 _ s6 s7 q =>
  ⟨s1 q, s2 q, s3 q, s4 q, s6 q, s7 q⟩

/-- SA-Pass anchor: the cited theorem proves `Candidate` as stated, so a restatement that
drifts from the proved theorem stops compiling. -/
theorem anchor : Candidate := nearestBinary64_roundsTo

end BayesianNetworksProofs.Shadows.NearestBinary64
