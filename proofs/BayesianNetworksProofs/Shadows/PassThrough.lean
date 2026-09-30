import BayesianNetworksProofs.Finite.OpenSemantics

/-!
# SA-Pass shadow module: own-variable open semantics with pass-through

Claim `bn.passthrough`, from `osem_compose_passthrough`. The prose promises the formula for
arbitrary pass-through on either side "with no hypotheses at all", as "the product of the two
own open semantics summed over the glued variables the composite hides", while a glued
variable that stays on the interface keeps its value.

The candidate names the summed set `innerGlued`; the shadow names it as the prose does, the
glued variables that are hidden in the composite, so a definition of `innerGlued` that no
longer meant that would fail the checkers. Neither states any hypothesis: arbitrary networks,
matches, commutative semirings and kernels.
-/

namespace BayesianNetworksProofs.Shadows.PassThrough

open BayesianNetworksProofs BayesianNetworksProofs.FinBayesNet
open BayesianNetworksProofs.OpenFinBayesNet BayesianNetworksProofs.OpenFinBayesNet.Composable

/-- `osem_compose_passthrough`, restated abstractly: it has no hypotheses. -/
abbrev Candidate : Prop :=
  ∀ (A B : OpenFinBayesNet) (c : Composable A B) (R : Type) [CommSemiring R]
      (κA : A.Kernel R) (κB : B.Kernel R) (x : (compose c).Assignment),
    osem (compose c) (composeKernel c κA κB) x =
      marg (c.innerGlued.map Function.Embedding.inl)
        (fun y => osem A κA (restrictA c y) * osem B κB (restrictB c y)) x

/-- "the product of the two own open semantics summed over the glued variables the composite
hides": the summed set is the glued variables hidden in the composite, so a glued variable
that stays on the composite's interface is never summed and keeps its value. No hypotheses. -/
abbrev Shadow1 : Prop :=
  ∀ (A B : OpenFinBayesNet) (c : Composable A B) (R : Type) [CommSemiring R]
      (κA : A.Kernel R) (κB : B.Kernel R) (x : (compose c).Assignment),
    osem (compose c) (composeKernel c κA κB) x =
      marg ((c.glued.filter fun a => (Sum.inl a : A.V ⊕ Priv B) ∈ (compose c).hidden).map
          Function.Embedding.inl)
        (fun y => osem A κA (restrictA c y) * osem B κB (restrictB c y)) x

theorem forward1 : Candidate → Shadow1 := by
  intro h A B c R _ κA κB x
  rw [← innerGlued_eq_filter_hidden c]
  exact h A B c R κA κB x

theorem backward : Shadow1 → Candidate := by
  intro h A B c R _ κA κB x
  rw [innerGlued_eq_filter_hidden c]
  exact h A B c R κA κB x

/-- SA-Pass anchor: the cited theorem proves `Candidate` as stated, so a restatement that
drifts from the proved theorem stops compiling. -/
theorem anchor : Candidate := fun _ _ c _ _ κA κB x => osem_compose_passthrough c κA κB x

end BayesianNetworksProofs.Shadows.PassThrough
