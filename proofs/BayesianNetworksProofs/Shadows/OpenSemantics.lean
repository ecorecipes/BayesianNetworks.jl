import BayesianNetworksProofs.Finite.OpenSemantics

/-!
# SA-Pass shadow module: own-variable open semantics (Proposition 3)

Claim `bn.open-semantics`, from `osem_compose_glue`. The prose says the theorem drops
locality, normalisation and match surjectivity but keeps disjoint input/output sets on both
networks. The shadows therefore quantify over arbitrary kernels in any commutative semiring
(no locality or normalisation), split on whether the interface match is surjective, and keep
both disjointness hypotheses.
-/

namespace BayesianNetworksProofs.Shadows.OpenSemantics

open BayesianNetworksProofs BayesianNetworksProofs.FinBayesNet
open BayesianNetworksProofs.OpenFinBayesNet BayesianNetworksProofs.OpenFinBayesNet.Composable

/-- `osem_compose_glue`, restated abstractly with every hypothesis. -/
abbrev Candidate : Prop :=
  ∀ (A B : OpenFinBayesNet) (c : Composable A B) (R : Type) [CommSemiring R]
      (κA : A.Kernel R) (κB : B.Kernel R),
    A.inputs ∩ A.outputs = ∅ → B.inputs ∩ B.outputs = ∅ →
      ∀ x : (compose c).Assignment,
        osem (compose c) (composeKernel c κA κB) x =
          marg (c.glued.map Function.Embedding.inl)
            (fun y => osem A κA (restrictA c y) * osem B κB (restrictB c y)) x

/-- With a surjective (total) match, for arbitrary, possibly non-local and unnormalised,
kernels, given disjoint input/output sets on both networks. -/
abbrev Shadow1 : Prop :=
  ∀ (A B : OpenFinBayesNet) (c : Composable A B) (R : Type) [CommSemiring R]
      (κA : A.Kernel R) (κB : B.Kernel R),
    Function.Surjective c.ι →
    A.inputs ∩ A.outputs = ∅ → B.inputs ∩ B.outputs = ∅ →
      ∀ x : (compose c).Assignment,
        osem (compose c) (composeKernel c κA κB) x =
          marg (c.glued.map Function.Embedding.inl)
            (fun y => osem A κA (restrictA c y) * osem B κB (restrictB c y)) x

/-- "drops ... match surjectivity": the same formula when the match is not surjective, so
some outputs of `A` stay unmatched. -/
abbrev Shadow2 : Prop :=
  ∀ (A B : OpenFinBayesNet) (c : Composable A B) (R : Type) [CommSemiring R]
      (κA : A.Kernel R) (κB : B.Kernel R),
    ¬Function.Surjective c.ι →
    A.inputs ∩ A.outputs = ∅ → B.inputs ∩ B.outputs = ∅ →
      ∀ x : (compose c).Assignment,
        osem (compose c) (composeKernel c κA κB) x =
          marg (c.glued.map Function.Embedding.inl)
            (fun y => osem A κA (restrictA c y) * osem B κB (restrictB c y)) x

theorem forward1 : Candidate → Shadow1 := by
  intro h A B c R _ κA κB _ hA hB x
  exact h A B c R κA κB hA hB x

theorem forward2 : Candidate → Shadow2 := by
  intro h A B c R _ κA κB _ hA hB x
  exact h A B c R κA κB hA hB x

theorem backward : Shadow1 → Shadow2 → Candidate := by
  intro h1 h2 A B c R _ κA κB hA hB x
  by_cases hs : Function.Surjective c.ι
  · exact h1 A B c R κA κB hs hA hB x
  · exact h2 A B c R κA κB hs hA hB x

/-- SA-Pass anchor: the cited theorem proves `Candidate` as stated, so a restatement that
drifts from the proved theorem stops compiling. -/
theorem anchor : Candidate := fun _ _ c _ _ κA κB hA hB x =>
  BayesianNetworksProofs.OpenFinBayesNet.Composable.osem_compose_glue c κA κB hA hB x

end BayesianNetworksProofs.Shadows.OpenSemantics
