import BayesianNetworksProofs.Finite.FactorMarginal
import BayesianNetworksProofs.Finite.Posterior
import Mathlib.Tactic.Ring
import Mathlib.Tactic.FieldSimp

/-!
# Conditional independence from separator factorization

Conditional independence is stated as the finite event cross-product identity. At positive
conditioning mass it is the usual product of conditional probabilities. Zero conditioning
mass is not divided by. This module proves the probability algebra; graphical separation is
defined independently in `DSeparation.lean`.
-/

set_option autoImplicit false

namespace BayesianNetworksProofs.FinBayesNet

open Factor
noncomputable section
variable {bn : FinBayesNet}

def eventMass (p : bn.Assignment → ℝ) (A B C : Finset bn.V)
    (a b c : bn.Assignment) : ℝ :=
  ∑ x, p x * indicator A a x * indicator B b x * indicator C c x

def ConditionalIndependent (p : bn.Assignment → ℝ) (A B C : Finset bn.V) : Prop :=
  ∀ a b c, eventMass p A B C a b c * eventMass p ∅ ∅ C a b c =
    eventMass p A ∅ C a b c * eventMass p ∅ B C a b c

def relativeEventMass (U : Finset bn.V) (f : bn.Assignment → ℝ) (A B C : Finset bn.V)
    (a b c : bn.Assignment) : ℝ :=
  marg U (fun x => f x * indicator A a x * indicator B b x * indicator C c x) c

theorem indicator_empty (a x : bn.Assignment) : indicator ∅ a x = 1 := by
  simp [indicator, agrees]

theorem separator_event_mass (L R C A B : Finset bn.V) (f g : Factor bn ℝ)
    (hLR : Disjoint L R) (hLC : Disjoint L C) (hRC : Disjoint R C)
    (hf : f.scope ⊆ L ∪ C) (hg : g.scope ⊆ R ∪ C)
    (hA : A ⊆ L) (hB : B ⊆ R) (a b c : bn.Assignment) :
    relativeEventMass ((L ∪ R) ∪ C) (multiply f g).value A B C a b c =
      marg L (fun x => f.value x * indicator A a x) c *
        marg R (fun x => g.value x * indicator B b x) c := by
  let fl := multiply f (evidenceFactor A a)
  let fr := multiply g (evidenceFactor B b)
  have hfl : fl.scope ⊆ L ∪ C :=
    Finset.union_subset hf (hA.trans Finset.subset_union_left)
  have hfr : fr.scope ⊆ R ∪ C :=
    Finset.union_subset hg (hB.trans Finset.subset_union_left)
  have hd : Disjoint C (L ∪ R) := (Finset.disjoint_union_right.2 ⟨hLC.symm, hRC.symm⟩)
  have he : (fun x => (multiply f g).value x * indicator A a x *
      indicator B b x * indicator C c x) =
      (fun x => (multiply fl fr).value x * indicator C c x) := by
    funext x
    dsimp [multiply, evidenceFactor, fl, fr]
    ring
  unfold relativeEventMass
  rw [he, marg_indicator_eq_clamp hd, marg_clamp hd]
  have hc : clamp C c c = c := by funext v; simp [clamp]
  rw [hc]
  apply marg_product_disjoint L R fl fr hLR
  · exact (Finset.disjoint_union_right.2 ⟨hLR.symm, hRC⟩).mono_right hfl
  · exact (Finset.disjoint_union_right.2 ⟨hLR, hLC⟩).mono_right hfr

theorem separator_cross_product (L R C A B : Finset bn.V) (f g : Factor bn ℝ)
    (hLR : Disjoint L R) (hLC : Disjoint L C) (hRC : Disjoint R C)
    (hf : f.scope ⊆ L ∪ C) (hg : g.scope ⊆ R ∪ C)
    (hA : A ⊆ L) (hB : B ⊆ R) (a b c : bn.Assignment) :
    relativeEventMass ((L ∪ R) ∪ C) (multiply f g).value A B C a b c *
      relativeEventMass ((L ∪ R) ∪ C) (multiply f g).value ∅ ∅ C a b c =
    relativeEventMass ((L ∪ R) ∪ C) (multiply f g).value A ∅ C a b c *
      relativeEventMass ((L ∪ R) ∪ C) (multiply f g).value ∅ B C a b c := by
  rw [separator_event_mass L R C A B f g hLR hLC hRC hf hg hA hB,
    separator_event_mass L R C ∅ ∅ f g hLR hLC hRC hf hg (Finset.empty_subset _) (Finset.empty_subset _),
    separator_event_mass L R C A ∅ f g hLR hLC hRC hf hg hA (Finset.empty_subset _),
    separator_event_mass L R C ∅ B f g hLR hLC hRC hf hg (Finset.empty_subset _) hB]
  ring

/-- Marginalizing away variables outside an ancestral factorization commutes with an event
that depends only on retained variables. No numerical separation condition is assumed. -/
theorem eventMass_of_marginal (p q : bn.Assignment → ℝ) (U A B C : Finset bn.V)
    (hm : ∀ x, marg Uᶜ p x = q x) (hA : A ⊆ U) (hB : B ⊆ U) (hC : C ⊆ U)
    (a b c : bn.Assignment) :
    eventMass p A B C a b c = relativeEventMass U q A B C a b c := by
  let mask := multiply (evidenceFactor A a) (multiply (evidenceFactor B b) (evidenceFactor C c))
  have hs : mask.scope ⊆ U := Finset.union_subset hA (Finset.union_subset hB hC)
  have hinner : ∀ x, marg Uᶜ (fun y => p y * mask.value y) x = q x * mask.value x := by
    intro x
    have he : (fun y => p y * mask.value y) = (fun y => mask.value y * p y) := by
      funext y
      ring
    rw [he, marg_mul_left (fun y hy => mask.dependsOn y x fun v hv =>
      mem_fibre.1 hy v (fun hc => Finset.mem_compl.1 hc (hs hv))), hm, mul_comm]
  have he : (fun x => p x * indicator A a x * indicator B b x * indicator C c x) =
      (fun x => p x * mask.value x) := by
    funext x
    dsimp [mask, multiply, evidenceFactor]
    ring
  unfold eventMass relativeEventMass
  rw [he, ← marg_univ _ c]
  have hU : U ∪ Uᶜ = Finset.univ := Finset.union_compl U
  rw [← hU, marg_union_disjoint (Finset.disjoint_left.2 fun _ hu hc => Finset.mem_compl.1 hc hu)]
  simp_rw [hinner]
  apply congrArg (fun f => marg U f c)
  funext x
  dsimp [mask, multiply, evidenceFactor]
  ring

/-- Positive conditioning mass turns the cross-product identity into the usual conditional
probability factorization. The positivity boundary is explicit. -/
theorem ConditionalIndependent.conditional (p : bn.Assignment → ℝ) (A B C : Finset bn.V)
    (h : ConditionalIndependent p A B C) (a b c : bn.Assignment)
    (hz : 0 < eventMass p ∅ ∅ C a b c) :
    eventMass p A B C a b c / eventMass p ∅ ∅ C a b c =
      (eventMass p A ∅ C a b c / eventMass p ∅ ∅ C a b c) *
        (eventMass p ∅ B C a b c / eventMass p ∅ ∅ C a b c) := by
  rw [div_mul_div_comm, ← h a b c]
  field_simp [ne_of_gt hz]

end
end BayesianNetworksProofs.FinBayesNet
