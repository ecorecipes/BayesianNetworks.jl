import BayesianNetworksProofs.Finite.Tensor

/-!
# SA-Pass shadow module: Proposition 2, tensor compositionality

Claim `bn.tensor`, from `joint_tensor`. The shadow is independently provable (the joint is a
product over mechanisms, and a product over a sum type splits, `Fintype.prod_sum_type`), so
the claim is registered as weak: the shadow documents the prose without discriminating.

The prose also says "with no shared feet". `FinBayesNet` has no feet: `tensor` is the plain
disjoint union of two closed networks' variables and mechanisms, so that phrase has no
counterpart in the theorem and no shadow can express it.
-/

namespace BayesianNetworksProofs.Shadows.Tensor

open BayesianNetworksProofs BayesianNetworksProofs.FinBayesNet

/-- `joint_tensor`, restated abstractly with every hypothesis. -/
abbrev Candidate : Prop :=
  ∀ (bn₁ bn₂ : FinBayesNet) (R : Type) [CommMonoid R] (κ₁ : bn₁.Kernel R)
    (κ₂ : bn₂.Kernel R) (x : (bn₁.tensor bn₂).Assignment),
    joint (tensorKernel κ₁ κ₂) x = joint κ₁ (Assignment.left x) * joint κ₂ (Assignment.right x)

/-- "`⟦A ⊗ B⟧ = ⟦A⟧ ⊗ ⟦B⟧` for the disjoint union of two networks": on the disjoint union
`bn₁.tensor bn₂`, the joint of the combined kernels is the product of the two joints at the
restrictions of the assignment, over any commutative monoid of weights. -/
abbrev Shadow1 : Prop :=
  ∀ (bn₁ bn₂ : FinBayesNet) (R : Type) [CommMonoid R] (κ₁ : bn₁.Kernel R)
    (κ₂ : bn₂.Kernel R) (x : (bn₁.tensor bn₂).Assignment),
    joint (tensorKernel κ₁ κ₂) x = joint κ₁ (Assignment.left x) * joint κ₂ (Assignment.right x)

theorem forward1 : Candidate → Shadow1 := by
  intro h bn₁ bn₂ R _ κ₁ κ₂ x
  exact h bn₁ bn₂ R κ₁ κ₂ x

theorem backward : Shadow1 → Candidate := by
  intro h bn₁ bn₂ R _ κ₁ κ₂ x
  exact h bn₁ bn₂ R κ₁ κ₂ x

/-- Why the claim is weak: the shadow holds without the cited theorem. -/
theorem shadow1_independent : Shadow1 := by
  intro bn₁ bn₂ R _ κ₁ κ₂ x
  unfold joint
  exact Fintype.prod_sum_type _

/-- SA-Pass anchor: the cited theorem proves `Candidate` as stated, so a restatement that
drifts from the proved theorem stops compiling. -/
theorem anchor : Candidate := fun _ _ _ _ κ₁ κ₂ x => joint_tensor κ₁ κ₂ x

end BayesianNetworksProofs.Shadows.Tensor
