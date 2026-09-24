import BayesianNetworksProofs.Finite.Intervention
import Mathlib.Data.Real.Basic

/-!
# SA-Pass shadow module: hard intervention gives the truncated factorisation

Claim `bn.intervention`, from `joint_intervene`.
-/

namespace BayesianNetworksProofs.Shadows.TruncatedFactorisation

open BayesianNetworksProofs BayesianNetworksProofs.FinBayesNet

/-- `joint_intervene` over `ℝ`, restated abstractly. -/
abbrev Candidate : Prop :=
  ∀ (bn : FinBayesNet) (κ : bn.Kernel ℝ) (m₀ : bn.M) (a : bn.states (bn.target m₀))
      (x : bn.Assignment),
    joint (intervene κ m₀ a) x =
      (if x (bn.target m₀) = a then 1 else 0) *
        ∏ m ∈ Finset.univ.erase m₀, κ m x (x (bn.target m))

/-- "the same product of conditional probability tables": on the assignments the intervention
admits, every other mechanism's table is untouched and no factor is added. -/
abbrev Shadow1 : Prop :=
  ∀ (bn : FinBayesNet) (κ : bn.Kernel ℝ) (m₀ : bn.M) (a : bn.states (bn.target m₀))
      (x : bn.Assignment), x (bn.target m₀) = a →
    joint (intervene κ m₀ a) x = ∏ m ∈ Finset.univ.erase m₀, κ m x (x (bn.target m))

/-- "with the factor for the intervened variable replaced by a point mass": off the intervened
value the joint vanishes. -/
abbrev Shadow2 : Prop :=
  ∀ (bn : FinBayesNet) (κ : bn.Kernel ℝ) (m₀ : bn.M) (a : bn.states (bn.target m₀))
      (x : bn.Assignment), x (bn.target m₀) ≠ a → joint (intervene κ m₀ a) x = 0

theorem forward1 : Candidate → Shadow1 := by
  intro h bn κ m₀ a x hx
  rw [h bn κ m₀ a x, if_pos hx, one_mul]

theorem forward2 : Candidate → Shadow2 := by
  intro h bn κ m₀ a x hx
  rw [h bn κ m₀ a x, if_neg hx, zero_mul]

theorem backward : Shadow1 → Shadow2 → Candidate := by
  intro h1 h2 bn κ m₀ a x
  by_cases hx : x (bn.target m₀) = a
  · rw [h1 bn κ m₀ a x hx, if_pos hx, one_mul]
  · rw [h2 bn κ m₀ a x hx, if_neg hx, zero_mul]

end BayesianNetworksProofs.Shadows.TruncatedFactorisation
