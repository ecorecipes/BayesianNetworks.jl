import BayesianNetworksProofs.Finite.Evaluation
import Mathlib.Data.Real.Basic

/-!
# SA-Pass shadow module: "the local product sums to one"

Claim `bn.joint-distribution`, from `sum_joint_eq_one`. (An earlier revision of the README said
"is a distribution", which a reader takes to include nonnegative weights; `sum_joint_eq_one` is
a normalisation identity over a commutative semiring and says nothing about signs, so the
nonnegativity shadow was correctly unprovable. The prose has been narrowed to what is proved.)
-/

namespace BayesianNetworksProofs.Shadows.JointDistribution

open BayesianNetworksProofs BayesianNetworksProofs.FinBayesNet

/-- `sum_joint_eq_one` over `ℝ`, restated abstractly. -/
abbrev Candidate : Prop :=
  ∀ (bn : FinBayesNet) (κ : bn.Kernel ℝ), bn.Closed → bn.TopoOrder →
    (∀ m, Local κ m) → (∀ m, Normalised κ m) → ∑ x, joint κ x = 1

/-- Total mass one. -/
abbrev Shadow1 : Prop :=
  ∀ (bn : FinBayesNet) (κ : bn.Kernel ℝ), bn.Closed → bn.TopoOrder →
    (∀ m, Local κ m) → (∀ m, Normalised κ m) → ∑ x, joint κ x = 1

/-- The joint is not identically zero: a consequence of unit mass, not a restatement of it. -/
abbrev Shadow2 : Prop :=
  ∀ (bn : FinBayesNet) (κ : bn.Kernel ℝ), bn.Closed → bn.TopoOrder →
    (∀ m, Local κ m) → (∀ m, Normalised κ m) → ∃ x, joint κ x ≠ 0

theorem forward1 : Candidate → Shadow1 := id

theorem forward2 : Candidate → Shadow2 := by
  intro h bn κ hclosed ord hloc hnorm
  by_contra hcon
  push_neg at hcon
  have hsum := h bn κ hclosed ord hloc hnorm
  rw [Finset.sum_congr rfl (fun x _ => hcon x)] at hsum
  simp at hsum

theorem backward : Shadow1 → Shadow2 → Candidate := by
  intro h1 _
  exact h1

end BayesianNetworksProofs.Shadows.JointDistribution
