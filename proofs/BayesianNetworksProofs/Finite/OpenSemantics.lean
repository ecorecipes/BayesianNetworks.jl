import BayesianNetworksProofs.Finite.Open

/-!
# BayesianNetworksProofs.Finite.OpenSemantics

**Proposition 3 in each component's own open semantics** (SPEC §13.2, §61).

Finite marginal sums transfer across the two pushout legs. The proof uses one-variable
updates and finite Fubini, so state-space equivalences on the glued interface need not be
identities. The resulting composition theorem permits a partial interface match (`glue`),
not only a total match (`compose`), and needs neither kernel locality nor normalisation:
the equality is an algebraic identity of finite sums and products.

`osem_compose_passthrough` is the formula for arbitrary interfaces. A glued variable that
stays on the composite's interface -- an input of `A`, or passed by `B` straight to its
outputs -- keeps its visible value and is never summed; only the `innerGlued` variables are.
It needs no hypotheses at all. With disjoint input and output sets on both networks every
glued variable is inner (`innerGlued_eq_glued`), which gives `osem_compose_glue`.
-/

set_option autoImplicit false

namespace BayesianNetworksProofs.OpenFinBayesNet.Composable

open FinBayesNet

variable {A B : OpenFinBayesNet} (c : Composable A B) {R : Type} [CommSemiring R]

theorem restrictA_update (x : (composeNet c).Assignment) (v : A.V) (z : A.states v) :
    restrictA c (Function.update x (.inl v) z) =
      Function.update (restrictA c x) v z := by
  funext w
  by_cases h : w = v
  · subst w
    simp [restrictA]
  · simp [restrictA, h]

theorem restrictB_update (x : (composeNet c).Assignment) (v : B.V)
    (hv : v ∉ B.inputs) (z : B.states v) :
    restrictB c (Function.update x (.inr ⟨v, hv⟩) z) =
      Function.update (restrictB c x) v z := by
  funext w
  by_cases h : w = v
  · subst w
    simp [restrictB, hv]
  · by_cases hw : w ∈ B.inputs
    · simp [restrictB, hw, Function.update_of_ne h]
    · have hsub : (⟨w, hw⟩ : Priv B) ≠ ⟨v, hv⟩ := fun he => h (congrArg Subtype.val he)
      simp [restrictB, hw, Function.update_of_ne h, hsub]

/-- Transfer a finite marginal across the left pushout leg. -/
theorem marg_restrictA (S : Finset A.V) (F : A.Assignment → R)
    (x : (composeNet c).Assignment) :
    marg (S.map Function.Embedding.inl) (fun y => F (restrictA c y)) x =
      marg S F (restrictA c x) := by
  induction S using Finset.induction_on generalizing x with
  | empty =>
    simp only [Finset.map_empty]
    rw [marg_empty (bn := composeNet c), marg_empty]
  | @insert v S hv ih =>
    rw [Finset.map_insert, marg_insert (by simpa using hv), marg_insert hv]
    exact Finset.sum_congr rfl fun z _ => by
      rw [ih]
      simp only [Function.Embedding.inl_apply]
      rw [restrictA_update]

/-- Transfer a finite marginal across the right leg when no summed variable is glued. -/
theorem marg_restrictB (S : Finset B.V) (hS : Disjoint S B.inputs)
    (F : B.Assignment → R) (x : (composeNet c).Assignment) :
    marg (S.map c.trEmb) (fun y => F (restrictB c y)) x =
      marg S F (restrictB c x) := by
  induction S using Finset.induction_on generalizing x with
  | empty =>
    simp only [Finset.map_empty]
    rw [marg_empty (bn := composeNet c), marg_empty]
  | @insert v S hv ih =>
    have hvi : v ∉ B.inputs :=
      fun h => Finset.disjoint_left.1 hS (Finset.mem_insert_self _ _) h
    have hSi : Disjoint S B.inputs := hS.mono_left (Finset.subset_insert _ _)
    have hnot : c.trEmb v ∉ S.map c.trEmb := by
      intro hm
      obtain ⟨w, hw, he⟩ := Finset.mem_map.1 hm
      exact hv (c.trEmb.injective he ▸ hw)
    rw [trEmb_apply, tr_of_notMem hvi] at hnot
    rw [Finset.map_insert, trEmb_apply, tr_of_notMem hvi,
      marg_insert hnot, marg_insert hv]
    exact Finset.sum_congr rfl fun z _ => by rw [ih hSi, restrictB_update]

theorem glued_subset_outputs : c.glued ⊆ A.outputs := by
  intro v hv
  obtain ⟨w, _, rfl⟩ := Finset.mem_image.1 hv
  exact (c.ι w).property

theorem hidden_disjoint_inputs (O : OpenFinBayesNet) : Disjoint O.hidden O.inputs := by
  rw [Finset.disjoint_left]
  intro v hv hi
  exact (Finset.mem_compl.1 hv) (Finset.mem_union_left _ hi)

/-- An `A`-hidden variable cannot affect the assignment seen by `B`, even at a glued input. -/
theorem restrictB_eq_of_mem_fibre_hidden (x y : (composeNet c).Assignment)
    (hy : y ∈ fibre (A.hidden.map Function.Embedding.inl) x) :
    restrictB c y = restrictB c x := by
  funext v
  by_cases hv : v ∈ B.inputs
  · simp only [restrictB, dif_pos hv]
    congr 1
    apply mem_fibre.1 hy
    simp [hidden, (c.ι ⟨v, hv⟩).property]
  · rw [restrictB_of_notMem c y hv, restrictB_of_notMem c x hv]
    exact mem_fibre.1 hy _ (by simp)

/-- The glued variables that the composite hides. A glued variable stays on the composite's
interface, and must not be summed, when it is an input of `A` (a pass-through on `A`'s side,
which remains a composite input) or when `B` passes it straight to its outputs (a
pass-through on `B`'s side, which becomes a composite output). Only the rest is internal. -/
def innerGlued : Finset A.V :=
  c.glued.filter fun a => a ∉ A.inputs ∧ Sum.inl a ∉ B.outputs.map c.trEmb

theorem innerGlued_subset_glued : c.innerGlued ⊆ c.glued := Finset.filter_subset _ _

/-- An `A` variable that `B`'s outputs reach through the right leg is glued. -/
theorem mem_glued_of_inl_mem_map (a : A.V) (h : Sum.inl a ∈ B.outputs.map c.trEmb) :
    a ∈ c.glued := by
  obtain ⟨w, _, he⟩ := Finset.mem_map.1 h
  by_cases hw : w ∈ B.inputs
  · rw [trEmb_apply, tr_of_mem hw, Sum.inl.injEq] at he
    exact Finset.mem_image.2 ⟨⟨w, hw⟩, Finset.mem_univ _, he⟩
  · rw [trEmb_apply, tr_of_notMem hw] at he
    exact absurd he (by simp)

theorem inl_notMem_map_of_disjoint (a : A.V) (S : Finset B.V) (hs : Disjoint S B.inputs) :
    Sum.inl a ∉ S.map c.trEmb := by
  intro hm
  obtain ⟨v, hv, he⟩ := Finset.mem_map.1 hm
  have hvi : v ∉ B.inputs := fun hi => Finset.disjoint_left.1 hs hv hi
  rw [trEmb_apply, tr_of_notMem hvi] at he
  exact Sum.inr_ne_inl he

/-- The hidden variables of a composite, for **arbitrary** interfaces: pass-through variables
on either side are allowed, and exactly the inner glued variables join the two hidden sets. -/
theorem hidden_compose_general :
    (compose c).hidden =
      (c.innerGlued.map Function.Embedding.inl ∪ A.hidden.map Function.Embedding.inl) ∪
        B.hidden.map c.trEmb := by
  ext v
  cases v with
  | inl a =>
    have hbh : Sum.inl a ∉ B.hidden.map c.trEmb :=
      inl_notMem_map_of_disjoint c a B.hidden (hidden_disjoint_inputs B)
    have hin : (Sum.inl a : A.V ⊕ Priv B) ∈ A.inputs.map Function.Embedding.inl ↔ a ∈ A.inputs :=
      Finset.mem_map' _
    have hout : (Sum.inl a : A.V ⊕ Priv B) ∈ (A.outputs \ c.glued).map Function.Embedding.inl ↔
        a ∈ A.outputs ∧ a ∉ c.glued :=
      (Finset.mem_map' _).trans Finset.mem_sdiff
    have hinner : (Sum.inl a : A.V ⊕ Priv B) ∈ c.innerGlued.map Function.Embedding.inl ↔
        a ∈ c.glued ∧ a ∉ A.inputs ∧ Sum.inl a ∉ B.outputs.map c.trEmb :=
      (Finset.mem_map' _).trans Finset.mem_filter
    have hhid : (Sum.inl a : A.V ⊕ Priv B) ∈ A.hidden.map Function.Embedding.inl ↔
        ¬(a ∈ A.inputs ∨ a ∈ A.outputs) :=
      (Finset.mem_map' _).trans (by rw [hidden, Finset.mem_compl, Finset.mem_union])
    rw [hidden, Finset.mem_compl]
    change (Sum.inl a ∉ A.inputs.map Function.Embedding.inl ∪
      ((A.outputs \ c.glued).map Function.Embedding.inl ∪ B.outputs.map c.trEmb)) ↔
        Sum.inl a ∈ (c.innerGlued.map Function.Embedding.inl ∪
          A.hidden.map Function.Embedding.inl) ∪ B.hidden.map c.trEmb
    rw [Finset.mem_union, Finset.mem_union, Finset.mem_union, Finset.mem_union, hin, hout,
      hinner, hhid]
    simp only [hbh, or_false]
    -- Propositional reasoning, spelled out: `tauto` would unfold the memberships of the
    -- composite, whose definition is large.
    by_cases hg : a ∈ c.glued
    · have ho := glued_subset_outputs c hg
      constructor
      · intro h
        exact Or.inl ⟨hg, fun hi => h (Or.inl hi), fun hbo => h (Or.inr (Or.inr hbo))⟩
      · rintro (⟨-, hi, hbo⟩ | hn) (h | ⟨-, hng⟩ | h)
        · exact hi h
        · exact hng hg
        · exact hbo h
        · exact hn (Or.inl h)
        · exact hng hg
        · exact hn (Or.inr ho)
    · have hb : Sum.inl a ∉ B.outputs.map c.trEmb :=
        fun h => hg (mem_glued_of_inl_mem_map c a h)
      constructor
      · intro h
        exact Or.inr fun h' => h'.elim (fun hi => h (Or.inl hi))
          (fun ho => h (Or.inr (Or.inl ⟨ho, hg⟩)))
      · rintro (⟨hg', -, -⟩ | hn) (h | ⟨ho, -⟩ | h)
        · exact hg hg'
        · exact hg hg'
        · exact hg hg'
        · exact hn (Or.inl h)
        · exact hn (Or.inr ho)
        · exact hb h
  | inr b =>
    rw [hidden, Finset.mem_compl]
    change (Sum.inr b ∉ A.inputs.map Function.Embedding.inl ∪
      ((A.outputs \ c.glued).map Function.Embedding.inl ∪ B.outputs.map c.trEmb)) ↔
        Sum.inr b ∈ (c.innerGlued.map Function.Embedding.inl ∪
          A.hidden.map Function.Embedding.inl) ∪ B.hidden.map c.trEmb
    simp only [Finset.mem_union, inr_mem_map_trEmb (c := c)]
    simp [hidden, b.property]

/-- The inner glued variables are exactly the glued variables that the composite hides. -/
theorem innerGlued_eq_filter_hidden :
    c.innerGlued =
      c.glued.filter fun a => (Sum.inl a : A.V ⊕ Priv B) ∈ (compose c).hidden := by
  ext a
  rw [Finset.mem_filter, hidden_compose_general c]
  constructor
  · intro h
    exact ⟨innerGlued_subset_glued c h,
      Finset.mem_union_left _ (Finset.mem_union_left _ (Finset.mem_map_of_mem _ h))⟩
  · rintro ⟨hg, h⟩
    rcases Finset.mem_union.1 h with h | h
    · rcases Finset.mem_union.1 h with h | h
      · exact (Finset.mem_map' _).1 h
      · exfalso
        have hah : a ∈ A.hidden := (Finset.mem_map' _).1 h
        exact Finset.mem_compl.1 hah (Finset.mem_union_right _ (glued_subset_outputs c hg))
    · exact absurd h (inl_notMem_map_of_disjoint c a B.hidden (hidden_disjoint_inputs B))

/-- With disjoint input and output sets on both networks there is no pass-through, and every
glued variable is inner. -/
theorem innerGlued_eq_glued (hA : A.inputs ∩ A.outputs = ∅)
    (hB : B.inputs ∩ B.outputs = ∅) : c.innerGlued = c.glued := by
  refine Finset.filter_true_of_mem fun a ha => ⟨fun hi => ?_, fun hm => ?_⟩
  · have := Finset.mem_inter.2 ⟨hi, glued_subset_outputs c ha⟩
    rw [hA] at this
    exact Finset.notMem_empty _ this
  · obtain ⟨w, hwo, he⟩ := Finset.mem_map.1 hm
    by_cases hw : w ∈ B.inputs
    · have := Finset.mem_inter.2 ⟨hw, hwo⟩
      rw [hB] at this
      exact Finset.notMem_empty _ this
    · rw [trEmb_apply, tr_of_notMem hw] at he
      exact absurd he (by simp)

/-- The hidden variables of a composite, with unglued outputs retained. Total matching is
not required. -/
theorem hidden_compose (hA : A.inputs ∩ A.outputs = ∅)
    (hB : B.inputs ∩ B.outputs = ∅) :
    (compose c).hidden =
      (c.glued.map Function.Embedding.inl ∪ A.hidden.map Function.Embedding.inl) ∪
        B.hidden.map c.trEmb := by
  rw [hidden_compose_general, innerGlued_eq_glued c hA hB]

/-- **Proposition 3 with pass-through.** For arbitrary interfaces -- copied or passed-through
variables on either side, partial gluing, no locality, normalisation or matching assumptions --
the composite's open semantics is the product of the two own-variable open semantics summed
over the inner glued variables only. A glued variable that stays on the composite's interface
(an input of `A`, or passed by `B` to its outputs) keeps its visible value: it is never summed. -/
theorem osem_compose_passthrough (κA : A.Kernel R) (κB : B.Kernel R)
    (x : (compose c).Assignment) :
    osem (compose c) (composeKernel c κA κB) x =
      marg (c.innerGlued.map Function.Embedding.inl)
        (fun y => osem A κA (restrictA c y) * osem B κB (restrictB c y)) x := by
  have hg : Disjoint (c.innerGlued.map Function.Embedding.inl : Finset (composeNet c).V)
      (A.hidden.map Function.Embedding.inl) := by
    rw [Finset.disjoint_left]
    intro v hv hh
    obtain ⟨a, ha, rfl⟩ := Finset.mem_map.1 hv
    have hah : a ∈ A.hidden := by simpa using hh
    exact Finset.mem_compl.1 hah (Finset.mem_union_right _
      (glued_subset_outputs c (innerGlued_subset_glued c ha)))
  have hS : c.innerGlued.map Function.Embedding.inl ∪ A.hidden.map Function.Embedding.inl
      ⊆ varsA c := by
    intro v hv
    rcases Finset.mem_union.1 hv with hv | hv <;>
      obtain ⟨a, _, rfl⟩ := Finset.mem_map.1 hv <;> exact inl_mem_varsA a
  have hT : B.hidden.map c.trEmb ⊆ varsB c := by
    intro v hv
    obtain ⟨b, hb, rfl⟩ := Finset.mem_map.1 hv
    have hbi : b ∉ B.inputs := fun hi =>
      Finset.disjoint_left.1 (hidden_disjoint_inputs B) hb hi
    rw [trEmb_apply, tr_of_notMem hbi]
    exact inr_mem_varsB _
  unfold osem
  rw [hidden_compose_general c, marg_joint_compose_split κA κB hS hT,
    marg_union_disjoint hg]
  have heq : ∀ z, marg (B.hidden.map c.trEmb)
      (fun w => joint κB (restrictB c w)) z = marg B.hidden (joint κB) (restrictB c z) :=
    marg_restrictB c B.hidden (hidden_disjoint_inputs B) (joint κB)
  simp_rw [heq]
  apply congrArg (fun F => marg (c.innerGlued.map Function.Embedding.inl) F x)
  funext y
  calc
    _ = marg (A.hidden.map Function.Embedding.inl)
          (fun z => joint κA (restrictA c z)) y *
            marg B.hidden (joint κB) (restrictB c y) := by
      unfold marg
      rw [Finset.sum_mul]
      refine Finset.sum_congr rfl fun z hz => ?_
      dsimp only
      rw [restrictB_eq_of_mem_fibre_hidden c y z hz]
    _ = _ := by rw [marg_restrictA]

/-- **Proposition 3, including partial gluing.** Sum the product of the two own-variable
open semantics over the glued interface. No stochastic or locality assumptions are needed.
Without pass-through every glued variable is inner, so this is `osem_compose_passthrough`. -/
theorem osem_compose_glue (κA : A.Kernel R) (κB : B.Kernel R)
    (hA : A.inputs ∩ A.outputs = ∅) (hB : B.inputs ∩ B.outputs = ∅)
    (x : (compose c).Assignment) :
    osem (compose c) (composeKernel c κA κB) x =
      marg (c.glued.map Function.Embedding.inl)
        (fun y => osem A κA (restrictA c y) * osem B κB (restrictB c y)) x := by
  rw [← innerGlued_eq_glued c hA hB]
  exact osem_compose_passthrough c κA κB x

/-- The original Roadmap statement, with its original (now known to be stronger than
necessary) premises retained. `osem_compose_glue` proves it without locality, normalisation,
or surjectivity of the interface map. -/
theorem osem_compose (κA : A.Kernel R) (κB : B.Kernel R)
    (_hlocA : ∀ m, Local κA m) (_hlocB : ∀ m, Local κB m) (_hnormB : ∀ m, Normalised κB m)
    (hA : A.inputs ∩ A.outputs = ∅) (hB : B.inputs ∩ B.outputs = ∅)
    (_hι : Function.Surjective c.ι) (x : (compose c).Assignment) :
    osem (compose c) (composeKernel c κA κB) x =
      marg (c.glued.map Function.Embedding.inl)
        (fun y => osem A κA (restrictA c y) * osem B κB (restrictB c y)) x := by
  exact osem_compose_glue c κA κB hA hB x

end BayesianNetworksProofs.OpenFinBayesNet.Composable
