import BayesianNetworksProofs.Finite.ConditionalIndependence
import Mathlib.Combinatorics.SimpleGraph.Connectivity.Connected
import Mathlib.Logic.Relation

/-!
# D-separation soundness on a finite DAG

Separation is defined solely from the directed parent graph: take the ancestors of the query
and conditioning variables, moralize every retained child/parent family, delete conditioning
vertices, and require no graph path between the queries. It is not defined numerically.

Reachability generates a component partition. Every mechanism scope is a clique in the moral
graph, so no retained factor crosses the partition except through conditioning variables.
The ancestor-normalization theorem and the separator probability algebra prove conditional
independence. This is the moralized-ancestral criterion, not a verification of Julia Bayes-ball.
-/

set_option autoImplicit false

namespace BayesianNetworksProofs.FinBayesNet

open Factor
noncomputable section

variable {bn : FinBayesNet}

def ParentEdge (bn : FinBayesNet) (v w : bn.V) : Prop :=
  ∃ m, bn.target m = w ∧ v ∈ bn.parents m

def ancestors (S : Finset bn.V) : Finset bn.V := by
  classical
  exact Finset.univ.filter fun v => ∃ w ∈ S, Relation.ReflTransGen (ParentEdge bn) v w

theorem subset_ancestors (S : Finset bn.V) : S ⊆ ancestors S := by
  classical
  intro v hv
  exact Finset.mem_filter.2 ⟨Finset.mem_univ _, v, hv, Relation.ReflTransGen.refl⟩

theorem ancestors_upstream (S : Finset bn.V) : UpstreamClosed (ancestors S) := by
  classical
  intro m hm v hv
  obtain ⟨w, hw, path⟩ := (Finset.mem_filter.1 hm).2
  exact Finset.mem_filter.2 ⟨Finset.mem_univ _, w, hw,
    (Relation.ReflTransGen.single ⟨m, rfl, hv⟩).trans path⟩

def family (bn : FinBayesNet) (m : bn.M) : Finset bn.V :=
  insert (bn.target m) (bn.parents m)

def moral (U : Finset bn.V) : SimpleGraph bn.V where
  Adj v w := v ≠ w ∧ ∃ m, bn.target m ∈ U ∧ v ∈ family bn m ∧ w ∈ family bn m
  symm := by
    rintro v w ⟨hne, m, hm, hv, hw⟩
    exact ⟨Ne.symm hne, m, hm, hw, hv⟩
  loopless := ⟨fun v h => h.1 rfl⟩

def cutMoral (U C : Finset bn.V) : SimpleGraph bn.V where
  Adj v w := (moral U).Adj v w ∧ v ∉ C ∧ w ∉ C
  symm := by
    rintro v w ⟨h, hv, hw⟩
    exact ⟨h.symm, hw, hv⟩
  loopless := ⟨fun v h => h.1.1 rfl⟩

def GraphSeparated (U A B C : Finset bn.V) : Prop :=
  ∀ a ∈ A, ∀ b ∈ B, ¬(cutMoral U C).Reachable a b

def DSeparated (A B C : Finset bn.V) : Prop :=
  GraphSeparated (ancestors ((A ∪ B) ∪ C)) A B C

def leftSide (U A C : Finset bn.V) : Finset bn.V := by
  classical
  exact (U \ C).filter fun v => ∃ a ∈ A, (cutMoral U C).Reachable a v

def rightSide (U A C : Finset bn.V) : Finset bn.V := U \ (leftSide U A C ∪ C)

theorem left_mem {U A C : Finset bn.V} {v : bn.V} :
    v ∈ leftSide U A C ↔ v ∈ U ∧ v ∉ C ∧ ∃ a ∈ A, (cutMoral U C).Reachable a v := by
  simp [leftSide, and_assoc]

theorem left_subset (U A C : Finset bn.V) : leftSide U A C ⊆ U :=
  fun _ hv => (left_mem.1 hv).1

theorem left_avoids (U A C : Finset bn.V) : Disjoint (leftSide U A C) C :=
  Finset.disjoint_left.2 fun _ hv hc => (left_mem.1 hv).2.1 hc

theorem family_subset {U : Finset bn.V} (hU : UpstreamClosed U) (m : bn.M) (hm : bn.target m ∈ U) :
    family bn m ⊆ U := Finset.insert_subset_iff.2 ⟨hm, hU m hm⟩

theorem left_closed_edge {U A C : Finset bn.V} {v w : bn.V}
    (hv : v ∈ leftSide U A C) (hw : w ∈ U) (he : (cutMoral U C).Adj v w) :
    w ∈ leftSide U A C := by
  obtain ⟨_, _, a, ha, path⟩ := left_mem.1 hv
  exact left_mem.2 ⟨hw, he.2.2, a, ha, path.trans he.reachable⟩

theorem queries_in_sides {U A B C : Finset bn.V}
    (hA : A ⊆ U) (hB : B ⊆ U) (hAC : Disjoint A C) (hBC : Disjoint B C)
    (hsep : GraphSeparated U A B C) :
    A ⊆ leftSide U A C ∧ B ⊆ rightSide U A C := by
  constructor
  · intro v hv
    exact left_mem.2 ⟨hA hv, fun hc => Finset.disjoint_left.1 hAC hv hc,
      v, hv, SimpleGraph.Reachable.refl v⟩
  · intro v hv
    refine Finset.mem_sdiff.2 ⟨hB hv, ?_⟩
    intro hc
    rcases Finset.mem_union.1 hc with hl | hc
    · obtain ⟨_, _, a, ha, path⟩ := left_mem.1 hl
      exact hsep a ha v hv path
    · exact Finset.disjoint_left.1 hBC hv hc

/-- A moral clique touching the reachable side cannot also touch the other side. -/
theorem family_left {U A C : Finset bn.V} (hU : UpstreamClosed U)
    (m : bn.M) (hm : bn.target m ∈ U) (ht : (family bn m ∩ leftSide U A C).Nonempty) :
    family bn m ⊆ leftSide U A C ∪ C := by
  obtain ⟨v, hv⟩ := ht
  have hvF := (Finset.mem_inter.1 hv).1
  have hvL := (Finset.mem_inter.1 hv).2
  intro w hw
  by_cases hc : w ∈ C
  · exact Finset.mem_union_right _ hc
  · apply Finset.mem_union_left
    by_cases he : v = w
    · simpa [he] using hvL
    · exact left_closed_edge hvL (family_subset hU m hm hw)
        ⟨⟨he, m, hm, hvF, hw⟩, (left_mem.1 hvL).2.1, hc⟩

theorem family_right {U A C : Finset bn.V} (hU : UpstreamClosed U)
    (m : bn.M) (hm : bn.target m ∈ U) (ht : ¬(family bn m ∩ leftSide U A C).Nonempty) :
    family bn m ⊆ rightSide U A C ∪ C := by
  intro v hv
  by_cases hc : v ∈ C
  · exact Finset.mem_union_right _ hc
  · apply Finset.mem_union_left
    refine Finset.mem_sdiff.2 ⟨family_subset hU m hm hv, ?_⟩
    intro hbad
    rcases Finset.mem_union.1 hbad with hl | hc'
    · exact ht ⟨v, Finset.mem_inter.2 ⟨hv, hl⟩⟩
    · exact hc hc'

def groupedFactor (κ : bn.Kernel ℝ) (hloc : ∀ m, Local κ m) (S : Finset bn.V)
    (ms : Finset bn.M) (hS : ∀ m ∈ ms, family bn m ⊆ S) : Factor bn ℝ where
  scope := S
  value x := ∏ m ∈ ms, κ m x (x (bn.target m))
  dependsOn x y h := by
    apply Finset.prod_congr rfl
    intro m hm
    rw [hloc m x y (fun v hv => h v (hS m hm (Finset.mem_insert_of_mem hv))),
      h (bn.target m) (hS m hm (Finset.mem_insert_self _ _))]

/-- **D-separation soundness.** The premise is graph path separation in the moralized ancestral
graph. The conclusion is the finite conditional-independence event identity. No numerical
independence or precomputed correct factor partition is assumed. -/
theorem d_separation_sound (κ : bn.Kernel ℝ) (hclosed : bn.Closed) (ord : bn.TopoOrder)
    (hloc : ∀ m, Local κ m) (hnorm : ∀ m, Normalised κ m)
    (A B C : Finset bn.V) (hAC : Disjoint A C) (hBC : Disjoint B C)
    (hsep : DSeparated A B C) : ConditionalIndependent (joint κ) A B C := by
  classical
  let U := ancestors ((A ∪ B) ∪ C)
  have hU : UpstreamClosed U := ancestors_upstream _
  have hAU : A ⊆ U := (Finset.subset_union_left.trans Finset.subset_union_left).trans (subset_ancestors _)
  have hBU : B ⊆ U := (Finset.subset_union_right.trans Finset.subset_union_left).trans (subset_ancestors _)
  have hCU : C ⊆ U := Finset.subset_union_right.trans (subset_ancestors _)
  let L := leftSide U A C
  let R := rightSide U A C
  have hSides := queries_in_sides hAU hBU hAC hBC hsep
  have hLC : Disjoint L C := left_avoids U A C
  have hLR : Disjoint L R := Finset.disjoint_left.2 fun v hv hr =>
    (Finset.mem_sdiff.1 hr).2 (Finset.mem_union_left _ hv)
  have hRC : Disjoint R C := Finset.disjoint_left.2 fun v hr hv =>
    (Finset.mem_sdiff.1 hr).2 (Finset.mem_union_right _ hv)
  have hsplit : (L ∪ R) ∪ C = U := by
    have hLU : L ⊆ U := left_subset U A C
    apply Finset.Subset.antisymm
    · intro v hv
      rcases Finset.mem_union.1 hv with hv | hc
      · rcases Finset.mem_union.1 hv with hl | hr
        · exact hLU hl
        · exact (Finset.mem_sdiff.1 hr).1
      · exact hCU hc
    · intro v hv
      by_cases hc : v ∈ C
      · exact Finset.mem_union_right _ hc
      · apply Finset.mem_union_left
        by_cases hl : v ∈ L
        · exact Finset.mem_union_left _ hl
        · exact Finset.mem_union_right _ (Finset.mem_sdiff.2 ⟨hv, by simpa using And.intro hl hc⟩)
  let ms := Finset.univ.filter (fun m => bn.target m ∈ U)
  let touches := fun m => (family bn m ∩ L).Nonempty
  let ml := ms.filter touches
  let mr := ms.filter (fun m => ¬touches m)
  have hls : ∀ m ∈ ml, family bn m ⊆ L ∪ C := by
    intro m hm
    exact family_left hU m (Finset.mem_filter.1 (Finset.mem_filter.1 hm).1).2
      (Finset.mem_filter.1 hm).2
  have hrs : ∀ m ∈ mr, family bn m ⊆ R ∪ C := by
    intro m hm
    exact family_right hU m (Finset.mem_filter.1 (Finset.mem_filter.1 hm).1).2
      (Finset.mem_filter.1 hm).2
  let f := groupedFactor κ hloc (L ∪ C) ml hls
  let g := groupedFactor κ hloc (R ∪ C) mr hrs
  have hfac : (multiply f g).value = fun x => ∏ m ∈ ms, κ m x (x (bn.target m)) := by
    funext x
    exact Finset.prod_filter_mul_prod_filter_not ms touches _
  have hmarg : ∀ x, marg Uᶜ (joint κ) x = (multiply f g).value x := by
    intro x
    rw [hfac]
    exact marg_joint_upstream κ hclosed ord hloc hnorm U hU x
  intro a b c
  rw [eventMass_of_marginal (joint κ) (multiply f g).value U A B C hmarg hAU hBU hCU,
    eventMass_of_marginal (joint κ) (multiply f g).value U ∅ ∅ C hmarg
      (Finset.empty_subset _) (Finset.empty_subset _) hCU,
    eventMass_of_marginal (joint κ) (multiply f g).value U A ∅ C hmarg hAU (Finset.empty_subset _) hCU,
    eventMass_of_marginal (joint κ) (multiply f g).value U ∅ B C hmarg (Finset.empty_subset _) hBU hCU,
    ← hsplit]
  exact separator_cross_product L R C A B f g hLR hLC hRC (Finset.Subset.refl _)
    (Finset.Subset.refl _) hSides.1 hSides.2 a b c

/-- Probability interpretation, with nonnegativity and normalization explicitly supplied. -/
theorem d_separation_sound_probability (κ : bn.Kernel ℝ) (hclosed : bn.Closed) (ord : bn.TopoOrder)
    (hloc : ∀ m, Local κ m) (hnorm : ∀ m, Normalised κ m) (hnonneg : ∀ m x a, 0 ≤ κ m x a)
    (A B C : Finset bn.V) (hAC : Disjoint A C) (hBC : Disjoint B C) (hsep : DSeparated A B C) :
    (∀ x, 0 ≤ joint κ x) ∧ (∑ x, joint κ x = 1) ∧ ConditionalIndependent (joint κ) A B C :=
  ⟨joint_nonneg κ hnonneg, sum_joint_eq_one κ hclosed ord hloc hnorm,
    d_separation_sound κ hclosed ord hloc hnorm A B C hAC hBC hsep⟩

end
end BayesianNetworksProofs.FinBayesNet
