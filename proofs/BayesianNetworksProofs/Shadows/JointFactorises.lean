import BayesianNetworksProofs.Finite.Evaluation
import Mathlib.Data.Real.Basic

/-!
# SA-Pass shadow module: the joint is the chain-rule product and normalises

Claim `bn.joint-factorises`, from `sum_joint_eq_one`. The sentence promises two things: that the
joint *is* the product of the conditional probability tables, and that it is a distribution.
`Shadow1` records the first; it holds by definition of `joint`, so it is declared
`independently_provable` in the registry.
-/

namespace BayesianNetworksProofs.Shadows.JointFactorises

open BayesianNetworksProofs BayesianNetworksProofs.FinBayesNet

/-- `sum_joint_eq_one` over `ℝ`, restated abstractly. -/
abbrev Candidate : Prop :=
  ∀ (bn : FinBayesNet) (κ : bn.Kernel ℝ), bn.Closed → bn.TopoOrder →
    (∀ m, Local κ m) → (∀ m, Normalised κ m) → ∑ x, joint κ x = 1

/-- "the chain-rule product of the conditional probability tables". -/
abbrev Shadow1 : Prop :=
  ∀ (bn : FinBayesNet) (κ : bn.Kernel ℝ) (x : bn.Assignment),
    joint κ x = ∏ m, κ m x (x (bn.target m))

/-- "the model has a joint distribution": with every mechanism bound, the product normalises. -/
abbrev Shadow2 : Prop :=
  ∀ (bn : FinBayesNet) (κ : bn.Kernel ℝ), bn.Closed → bn.TopoOrder →
    (∀ m, Local κ m) → (∀ m, Normalised κ m) → ∑ x, joint κ x = 1

theorem forward1 : Candidate → Shadow1 := fun _ _ _ _ => rfl

theorem forward2 : Candidate → Shadow2 := id

theorem backward : Shadow1 → Shadow2 → Candidate := fun _ h2 => h2

/-- SA-Pass anchor: the cited theorem proves `Candidate` as stated, so a restatement that
drifts from the proved theorem stops compiling. -/
theorem anchor : Candidate := fun _ κ hc ord hloc hnorm =>
  BayesianNetworksProofs.FinBayesNet.sum_joint_eq_one κ hc ord hloc hnorm

end BayesianNetworksProofs.Shadows.JointFactorises
