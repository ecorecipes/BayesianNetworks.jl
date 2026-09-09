import BayesianNetworksProofs.Finite.FactorMarginal
import BayesianNetworksProofs.Finite.Posterior
import Mathlib.Algebra.Order.BigOperators.GroupWithZero.List

/-!
# Collect/distribute on a finite junction tree

The working representation is a binary junction tree. Arbitrary branching is represented by
copying a parent bag along a binary chain with empty local factor lists; no factors or weights
are duplicated. The recursive running-intersection conditions are structural: occurrences
shared by two branches meet in the parent bag, and a branch's intersection with its parent
is present in the branch root.

`prepare` computes only local products and upward separator projections. `distribute` uses
the cached upward messages and an incoming message to send the downward messages and produce
beliefs. No whole-joint enumeration occurs in either computation. `full` is a proof oracle.
An empty virtual-root bag connects disconnected components by scalar messages.
-/

set_option autoImplicit false

namespace BayesianNetworksProofs.Junction

open FinBayesNet FinBayesNet.Factor

noncomputable section
variable {bn : FinBayesNet} {I : Type}

inductive Tree (V I : Type)
  | leaf (bag : Finset V) (assigned : List I)
  | branch (bag : Finset V) (assigned : List I) (left right : Tree V I)

def Tree.bag : Tree bn.V I → Finset bn.V
  | .leaf B _ => B
  | .branch B _ _ _ => B

def Tree.vars : Tree bn.V I → Finset bn.V
  | .leaf B _ => B
  | .branch B _ l r => B ∪ (l.vars ∪ r.vars)

def Tree.indices : Tree bn.V I → List I
  | .leaf _ fs => fs
  | .branch _ fs l r => fs ++ l.indices ++ r.indices

def localFactor (F : I → Factor bn ℝ) (fs : List I) := combine (fs.map F)

def full (F : I → Factor bn ℝ) : Tree bn.V I → Factor bn ℝ
  | .leaf _ fs => localFactor F fs
  | .branch _ fs l r => multiply (localFactor F fs) (multiply (full F l) (full F r))

def Good (F : I → Factor bn ℝ) : Tree bn.V I → Prop
  | .leaf B fs => (localFactor F fs).scope ⊆ B
  | .branch B fs l r => (localFactor F fs).scope ⊆ B ∧ Good F l ∧ Good F r ∧
      l.vars ∩ B ⊆ l.bag ∧ r.vars ∩ B ⊆ r.bag ∧ l.vars ∩ r.vars ⊆ B

def decideGood (F : I → Factor bn ℝ) : (t : Tree bn.V I) → Decidable (Good F t)
  | .leaf B fs => inferInstanceAs (Decidable ((localFactor F fs).scope ⊆ B))
  | .branch B fs l r =>
    letI := decideGood F l
    letI := decideGood F r
    inferInstanceAs (Decidable ((localFactor F fs).scope ⊆ B ∧ Good F l ∧ Good F r ∧
      l.vars ∩ B ⊆ l.bag ∧ r.vars ∩ B ⊆ r.bag ∧ l.vars ∩ r.vars ⊆ B))

def checkGood (F : I → Factor bn ℝ) (t : Tree bn.V I) : Bool :=
  @decide (Good F t) (decideGood F t)

theorem checkGood_iff (F : I → Factor bn ℝ) (t : Tree bn.V I) :
    checkGood F t = true ↔ Good F t := by
  letI := decideGood F t
  unfold checkGood
  exact decide_eq_true_iff

def checkAssignment [Fintype I] [DecidableEq I] (t : Tree bn.V I) : Bool :=
  decide (t.indices.Nodup ∧ ∀ i : I, i ∈ t.indices)

theorem checkAssignment_sound [Fintype I] [DecidableEq I] (t : Tree bn.V I)
    (h : checkAssignment t = true) : t.indices.Perm Finset.univ.toList := by
  have hv : t.indices.Nodup ∧ ∀ i : I, i ∈ t.indices := of_decide_eq_true h
  apply (List.perm_ext_iff_of_nodup hv.1 (Finset.nodup_toList _)).2
  intro i
  simp [hv.2 i]

theorem bag_subset_vars (t : Tree bn.V I) : t.bag ⊆ t.vars := by
  cases t
  · exact Finset.Subset.refl _
  · exact Finset.subset_union_left

theorem full_scope (F : I → Factor bn ℝ) (t : Tree bn.V I) (h : Good F t) :
    (full F t).scope ⊆ t.vars := by
  induction t with
  | leaf B fs => exact h
  | branch B fs l r ihl ihr =>
    exact Finset.union_subset_union h.1 (Finset.union_subset_union (ihl h.2.1) (ihr h.2.2.1))

theorem full_value (F : I → Factor bn ℝ) (t : Tree bn.V I) :
    (full F t).value = Factor.product (t.indices.map F) := by
  induction t with
  | leaf B fs => exact combine_value _
  | branch B fs l r ihl ihr =>
    funext x
    simp [full, localFactor, multiply, combine_value, Tree.indices, Factor.product,
      List.map_append, List.map_map, ihl, ihr]

inductive Prepared (bn : FinBayesNet)
  | leaf (bag : Finset bn.V) (pot : Factor bn ℝ) (up : Factor bn ℝ)
  | branch (bag : Finset bn.V) (pot : Factor bn ℝ) (up : Factor bn ℝ)
      (left right : Prepared bn)

def Prepared.bag : Prepared bn → Finset bn.V
  | .leaf B _ _ => B
  | .branch B _ _ _ _ => B

def Prepared.up : Prepared bn → Factor bn ℝ
  | .leaf _ _ u => u
  | .branch _ _ u _ _ => u

/-- The collect pass; projections enumerate only removed factor coordinates. -/
def prepare (F : I → Factor bn ℝ) (parent : Finset bn.V) : Tree bn.V I → Prepared bn
  | .leaf B fs =>
    let f := localFactor F fs
    .leaf B f (project parent f)
  | .branch B fs l r =>
    let pl := prepare F B l
    let pr := prepare F B r
    let f := localFactor F fs
    .branch B f (project parent (multiply f (multiply pl.up pr.up))) pl pr

theorem prepare_bag (F : I → Factor bn ℝ) (P : Finset bn.V) (t : Tree bn.V I) :
    (prepare F P t).bag = t.bag := by cases t <;> rfl

theorem project_three (B : Finset bn.V) (f l r : Factor bn ℝ)
    (hf : f.scope ⊆ B) (hlr : l.scope ∩ r.scope ⊆ B) :
    project B (multiply f (multiply l r)) =
      multiply f (multiply (project B l) (project B r)) := by
  rw [project_multiply B f _ (Finset.inter_subset_left.trans hf),
    project_of_scope f hf, project_multiply B l r hlr]

/-- Every upward message is the side-of-cut marginal of its assigned factors. -/
theorem prepare_up (F : I → Factor bn ℝ) (t : Tree bn.V I) (h : Good F t)
    (P : Finset bn.V) (hb : t.vars ∩ P ⊆ t.bag) :
    (prepare F P t).up = project P (full F t) := by
  induction t generalizing P with
  | leaf B fs => rfl
  | branch B fs l r ihl ihr =>
    change project P (multiply (localFactor F fs)
      (multiply (prepare F B l).up (prepare F B r).up)) = _
    rw [ihl h.2.1 B h.2.2.2.1, ihr h.2.2.1 B h.2.2.2.2.1]
    have hc : (full F l).scope ∩ (full F r).scope ⊆ B :=
      (Finset.inter_subset_inter (full_scope F l h.2.1) (full_scope F r h.2.2.1)).trans h.2.2.2.2.2
    rw [← project_three B _ _ _ h.1 hc]
    exact project_project P B (full F (.branch B fs l r))
      ((Finset.inter_subset_inter (full_scope F _ h) (Finset.Subset.refl P)).trans hb)

theorem prepare_up_separator (F : I → Factor bn ℝ) (t : Tree bn.V I) (h : Good F t)
    (P : Finset bn.V) (hb : t.vars ∩ P ⊆ t.bag) :
    (prepare F P t).up = project (t.bag ∩ P) (full F t) := by
  rw [prepare_up F t h P hb, project_inter P t.bag (full F t)
    ((Finset.inter_subset_inter (full_scope F t h) (Finset.Subset.refl P)).trans hb),
    Finset.inter_comm P t.bag]

/-- The distribute pass, using the collect pass's cached upward messages. -/
def distribute (incoming : Factor bn ℝ) : Prepared bn → List (Finset bn.V × Factor bn ℝ)
  | .leaf B f _ => [(B, multiply f incoming)]
  | .branch B f _ l r =>
    (B, multiply f (multiply incoming (multiply l.up r.up))) ::
      (distribute (project l.bag (multiply f (multiply incoming r.up))) l ++
       distribute (project r.bag (multiply f (multiply incoming l.up))) r)

theorem frame_scope (B V : Finset bn.V) (f o g : Factor bn ℝ)
    (hf : f.scope ⊆ B) (ho : o.scope ∩ V ⊆ B) (hg : g.scope ∩ V ⊆ B) :
    (multiply o (multiply f g)).scope ∩ V ⊆ B := by
  intro v hv
  have hvV := (Finset.mem_inter.1 hv).2
  rcases Finset.mem_union.1 (Finset.mem_inter.1 hv).1 with hv | hv
  · exact ho (Finset.mem_inter.2 ⟨hv, hvV⟩)
  · rcases Finset.mem_union.1 hv with hv | hv
    · exact hf hv
    · exact hg (Finset.mem_inter.2 ⟨hv, hvV⟩)

theorem outgoing (B C : Finset bn.V) (f o g : Factor bn ℝ)
    (hf : f.scope ⊆ B) (hog : o.scope ∩ g.scope ⊆ B)
    (hC : (multiply o (multiply f g)).scope ∩ C ⊆ B) :
    project C (multiply f (multiply (project B o) (project B g))) =
      project C (multiply o (multiply f g)) := by
  calc
    _ = project C (project B (multiply o (multiply f g))) := by
      rw [multiply_left_comm o f g, project_three B f o g hf hog]
    _ = _ := project_project C B _ hC

/-- The collect/distribute beliefs are the global factor product projected to each bag.
The outside factor is an induction frame; the public calibration theorem supplies unit. -/
theorem distribute_correct (F : I → Factor bn ℝ) (t : Tree bn.V I) (h : Good F t)
    (outside : Factor bn ℝ) (hb : outside.scope ∩ t.vars ⊆ t.bag)
    (P : Finset bn.V) :
    ∀ b ∈ distribute (project t.bag outside) (prepare F P t),
      b.2 = project b.1 (multiply outside (full F t)) := by
  induction t generalizing outside P with
  | leaf B fs =>
    intro b hmem
    have he : b = (B, multiply (localFactor F fs) (project B outside)) := by simpa [distribute, prepare] using hmem
    subst b
    change multiply (localFactor F fs) (project B outside) = project B (multiply outside (localFactor F fs))
    rw [project_multiply B outside _ (Finset.inter_subset_right.trans h), project_of_scope _ h,
      multiply_comm]
  | branch B fs l r ihl ihr =>
    let f := localFactor F fs
    let fl := full F l
    let fr := full F r
    have hl : fl.scope ⊆ l.vars := full_scope F l h.2.1
    have hr : fr.scope ⊆ r.vars := full_scope F r h.2.2.1
    have hvl : l.vars ⊆ (Tree.branch B fs l r).vars :=
      (Finset.subset_union_left : l.vars ⊆ l.vars ∪ r.vars).trans Finset.subset_union_right
    have hvr : r.vars ⊆ (Tree.branch B fs l r).vars :=
      (Finset.subset_union_right : r.vars ⊆ l.vars ∪ r.vars).trans Finset.subset_union_right
    have hoL : outside.scope ∩ l.vars ⊆ B :=
      (Finset.inter_subset_inter (Finset.Subset.refl _) hvl).trans hb
    have hoR : outside.scope ∩ r.vars ⊆ B :=
      (Finset.inter_subset_inter (Finset.Subset.refl _) hvr).trans hb
    have hlr : fl.scope ∩ fr.scope ⊆ B :=
      (Finset.inter_subset_inter hl hr).trans h.2.2.2.2.2
    have hrL : fr.scope ∩ l.vars ⊆ B := by
      intro v hv
      exact h.2.2.2.2.2 (Finset.mem_inter.2 ⟨(Finset.mem_inter.1 hv).2, hr (Finset.mem_inter.1 hv).1⟩)
    have hlR : fl.scope ∩ r.vars ⊆ B :=
      (Finset.inter_subset_inter hl (Finset.Subset.refl _)).trans h.2.2.2.2.2
    let ol := multiply outside (multiply f fr)
    let or := multiply outside (multiply f fl)
    have holB : ol.scope ∩ l.vars ⊆ B := frame_scope B l.vars f outside fr h.1 hoL hrL
    have horB : or.scope ∩ r.vars ⊆ B := frame_scope B r.vars f outside fl h.1 hoR hlR
    have hol : ol.scope ∩ l.vars ⊆ l.bag := by
      intro v hv
      exact h.2.2.2.1 (Finset.mem_inter.2 ⟨(Finset.mem_inter.1 hv).2, holB hv⟩)
    have hor : or.scope ∩ r.vars ⊆ r.bag := by
      intro v hv
      exact h.2.2.2.2.1 (Finset.mem_inter.2 ⟨(Finset.mem_inter.1 hv).2, horB hv⟩)
    have houtl : project l.bag (multiply f (multiply (project B outside) (project B fr))) = project l.bag ol :=
      outgoing B l.bag f outside fr h.1
        ((Finset.inter_subset_inter (Finset.Subset.refl _) hr).trans hoR)
        ((Finset.inter_subset_inter (Finset.Subset.refl _) (bag_subset_vars l)).trans holB)
    have houtr : project r.bag (multiply f (multiply (project B outside) (project B fl))) = project r.bag or :=
      outgoing B r.bag f outside fl h.1
        ((Finset.inter_subset_inter (Finset.Subset.refl _) hl).trans hoL)
        ((Finset.inter_subset_inter (Finset.Subset.refl _) (bag_subset_vars r)).trans horB)
    intro b hm
    simp only [prepare, distribute, prepare_bag] at hm
    rw [prepare_up F l h.2.1 B h.2.2.2.1, prepare_up F r h.2.2.1 B h.2.2.2.2.1] at hm
    change b ∈ (B, multiply f (multiply (project B outside) (multiply (project B fl) (project B fr)))) ::
      (distribute (project l.bag (multiply f (multiply (project B outside) (project B fr)))) (prepare F B l) ++
       distribute (project r.bag (multiply f (multiply (project B outside) (project B fl)))) (prepare F B r)) at hm
    rw [houtl, houtr] at hm
    rcases List.mem_cons.1 hm with rfl | hm
    · change multiply f (multiply (project B outside) (multiply (project B fl) (project B fr))) =
        project B (multiply outside (multiply f (multiply fl fr)))
      have hf := full_scope F (.branch B fs l r) h
      change (multiply f (multiply fl fr)).scope ⊆ (Tree.branch B fs l r).vars at hf
      have hcross : outside.scope ∩ (multiply f (multiply fl fr)).scope ⊆ B :=
        (Finset.inter_subset_inter (Finset.Subset.refl _) hf).trans hb
      rw [project_multiply B outside (multiply f (multiply fl fr)) hcross,
        project_three B f fl fr h.1 hlr]
      ac_rfl
    · rcases List.mem_append.1 hm with hm | hm
      · rw [ihl h.2.1 ol hol B b hm]
        congr 1
        change multiply (multiply outside (multiply f fr)) fl = multiply outside (multiply f (multiply fl fr))
        ac_rfl
      · rw [ihr h.2.2.1 or hor B b hm]
        congr 1
        change multiply (multiply outside (multiply f fl)) fr = multiply outside (multiply f (multiply fl fr))
        ac_rfl

def calibrate (F : I → Factor bn ℝ) (t : Tree bn.V I) :=
  distribute unit (prepare F ∅ t)

theorem calibrate_correct (F : I → Factor bn ℝ) (t : Tree bn.V I) (h : Good F t) :
    ∀ b ∈ calibrate F t, b.2 = project b.1 (full F t) := by
  have hu : project t.bag (unit (bn := bn)) = unit := project_of_scope _ (Finset.empty_subset _)
  have hh := distribute_correct F t h unit (by intro v hv; exact False.elim (Finset.notMem_empty v (Finset.mem_inter.1 hv).1)) ∅
  simpa only [hu, unit_multiply] using hh

/-- Arbitrary branching is encoded by a chain of copies of the same bag with empty local
factor lists. This is a representation transformation, not a restriction to degree three. -/
def graft (B : Finset bn.V) (fs : List I) : List (Tree bn.V I) → Tree bn.V I
  | [] => .leaf B fs
  | t :: ts => .branch B fs t (graft B [] ts)

def forestVars : List (Tree bn.V I) → Finset bn.V
  | [] => ∅
  | t :: ts => t.vars ∪ forestVars ts

theorem graft_bag (B : Finset bn.V) (fs : List I) (ts : List (Tree bn.V I)) :
    (graft B fs ts).bag = B := by cases ts <;> rfl

theorem graft_vars (B : Finset bn.V) (fs : List I) (ts : List (Tree bn.V I)) :
    (graft B fs ts).vars = B ∪ forestVars ts := by
  induction ts generalizing fs with
  | nil => simp [graft, Tree.vars, forestVars]
  | cons t ts ih =>
    simp only [graft, Tree.vars, forestVars, ih]
    ac_rfl

theorem graft_indices (B : Finset bn.V) (fs : List I) (ts : List (Tree bn.V I)) :
    (graft B fs ts).indices = fs ++ ts.flatMap Tree.indices := by
  induction ts generalizing fs with
  | nil => simp [graft, Tree.indices]
  | cons t ts ih => simp [graft, Tree.indices, ih, List.append_assoc]

theorem mem_forestVars (ts : List (Tree bn.V I)) (v : bn.V) :
    v ∈ forestVars ts ↔ ∃ t ∈ ts, v ∈ t.vars := by
  induction ts with
  | nil => simp [forestVars]
  | cons t ts ih => simp [forestVars, ih, List.mem_cons, or_and_right, exists_or]

/-- Ordinary multi-child running intersection and factor-cover conditions generate a valid
binary working representation. No probability or message invariant occurs in the premises. -/
theorem graft_good (F : I → Factor bn ℝ) (B : Finset bn.V) (fs : List I)
    (ts : List (Tree bn.V I)) (hf : (localFactor F fs).scope ⊆ B)
    (hg : ∀ t ∈ ts, Good F t) (hb : ∀ t ∈ ts, t.vars ∩ B ⊆ t.bag)
    (hpair : ts.Pairwise (fun t s => t.vars ∩ s.vars ⊆ B)) :
    Good F (graft B fs ts) := by
  induction ts generalizing fs with
  | nil => exact hf
  | cons t ts ih =>
    have ht := (List.pairwise_cons.1 hpair)
    refine ⟨hf, hg t (List.mem_cons_self ..),
      ih [] (Finset.empty_subset _) (fun s hs => hg s (List.mem_cons_of_mem t hs))
        (fun s hs => hb s (List.mem_cons_of_mem t hs)) ht.2,
      hb t (List.mem_cons_self ..), ?_, ?_⟩
    · rw [graft_bag]
      exact Finset.inter_subset_right
    · intro v hv
      have hvT := (Finset.mem_inter.1 hv).1
      rw [graft_vars] at hv
      rcases Finset.mem_union.1 (Finset.mem_inter.1 hv).2 with hB | hrest
      · exact hB
      · obtain ⟨s, hs, hvS⟩ := (mem_forestVars ts v).1 hrest
        exact ht.1 s hs (Finset.mem_inter.2 ⟨hvT, hvS⟩)

/-- Disconnected components are joined only by empty-separator scalar messages. -/
theorem forest_good (F : I → Factor bn ℝ) (ts : List (Tree bn.V I))
    (hg : ∀ t ∈ ts, Good F t)
    (hd : ts.Pairwise (fun t s => Disjoint t.vars s.vars)) :
    Good F (graft ∅ [] ts) := by
  apply graft_good F ∅ [] ts (Finset.empty_subset _) hg
  · intro t _
    simp
  · exact hd.imp (by
      intro t s h
      rw [Finset.disjoint_iff_inter_eq_empty] at h
      simp [h])

theorem mem_local_scope (F : I → Factor bn ℝ) (fs : List I) (v : bn.V) :
    v ∈ (localFactor F fs).scope ↔ ∃ i ∈ fs, v ∈ (F i).scope := by
  induction fs with
  | nil => simp [localFactor, combine, unit]
  | cons i fs ih =>
    simp only [localFactor, List.map_cons, combine, multiply, Finset.mem_union] at *
    simp [ih, List.mem_cons, or_and_right, exists_or]

theorem mem_full_scope (F : I → Factor bn ℝ) (t : Tree bn.V I) (v : bn.V) :
    v ∈ (full F t).scope ↔ ∃ i ∈ t.indices, v ∈ (F i).scope := by
  induction t with
  | leaf B fs => exact mem_local_scope F fs v
  | branch B fs l r ihl ihr =>
    simp only [full, multiply, Finset.mem_union, mem_local_scope, Tree.indices,
      List.mem_append, or_and_right, exists_or, ihl, ihr, or_assoc]

theorem full_scope_univ (F : I → Factor bn ℝ) (t : Tree bn.V I)
    (hcover : ∀ v, ∃ i ∈ t.indices, v ∈ (F i).scope) : (full F t).scope = Finset.univ := by
  apply Finset.eq_univ_of_forall
  intro v
  exact (mem_full_scope F t v).2 (hcover v)

theorem full_product_of_perm [Fintype I] (F : I → Factor bn ℝ) (t : Tree bn.V I)
    (hassign : t.indices.Perm Finset.univ.toList) :
    (full F t).value = Factor.product (Finset.univ.toList.map F) := by
  rw [full_value]
  funext x
  simpa only [Factor.product, List.map_map, Function.comp_def] using
    (hassign.map (fun i => (F i).value x)).prod_eq

/-- Calibrated clique beliefs agree with the independently defined variable-elimination
algorithm for any duplicate-free elimination order of the other variables. -/
theorem calibrate_eq_ve [Fintype I] (F : I → Factor bn ℝ) (t : Tree bn.V I)
    (ht : Good F t) (hassign : t.indices.Perm Finset.univ.toList)
    (hvars : ∀ v, ∃ i, v ∈ (F i).scope) (b : Finset bn.V × Factor bn ℝ)
    (hb : b ∈ calibrate F t) (vs : List bn.V) (hvs : vs.Nodup) (hset : vs.toFinset = b.1ᶜ)
    (x : bn.Assignment) :
    b.2.value x = Factor.product (Factor.eliminateAll (Finset.univ.toList.map F) vs) x := by
  have hs : (full F t).scope = Finset.univ := full_scope_univ F t (by
    intro v
    obtain ⟨i, hi⟩ := hvars v
    exact ⟨i, hassign.mem_iff.mpr (Finset.mem_toList.2 (Finset.mem_univ _)), hi⟩)
  rw [calibrate_correct F t ht b hb, project_value, hs, ← Finset.compl_eq_univ_sdiff,
    full_product_of_perm F t hassign, Factor.eliminateAll_correct _ vs hvs, hset]

def beliefWeight (b : Finset bn.V × Factor bn ℝ) (base : bn.Assignment)
    (q : PartialAssignment bn b.1) : ℝ :=
  b.2.value (patch b.1 base q)

/-- The sum of a calibrated clique belief is the GLOBAL mass, including all disconnected
components joined through the empty virtual root. Zero entries require no division. -/
theorem belief_mass [Fintype I] (F : I → Factor bn ℝ) (t : Tree bn.V I)
    (ht : Good F t) (hassign : t.indices.Perm Finset.univ.toList)
    (hvars : ∀ v, ∃ i, v ∈ (F i).scope) (b : Finset bn.V × Factor bn ℝ)
    (hb : b ∈ calibrate F t) (base : bn.Assignment) :
    FiniteDistribution.mass (beliefWeight b base) =
      FiniteDistribution.mass (Factor.product (Finset.univ.toList.map F)) := by
  have hs : (full F t).scope = Finset.univ := full_scope_univ F t (by
    intro v
    obtain ⟨i, hi⟩ := hvars v
    exact ⟨i, hassign.mem_iff.mpr (Finset.mem_toList.2 (Finset.mem_univ _)), hi⟩)
  have hw : beliefWeight b base =
      FiniteDistribution.pushWeight (restrictTo b.1) (Factor.product (Finset.univ.toList.map F)) := by
    funext q
    unfold beliefWeight
    rw [calibrate_correct F t ht b hb, project_value, hs, ← Finset.compl_eq_univ_sdiff,
      full_product_of_perm F t hassign, marginal_eq_query_weight, restrict_patch]
  rw [hw, FiniteDistribution.mass_pushWeight]

def queryWeight (Q : Finset bn.V) (b : Finset bn.V × Factor bn ℝ) (base : bn.Assignment)
    (q : PartialAssignment bn Q) : ℝ :=
  (project Q b.2).value (patch Q base q)

theorem queryWeight_correct [Fintype I] (F : I → Factor bn ℝ) (t : Tree bn.V I)
    (ht : Good F t) (hassign : t.indices.Perm Finset.univ.toList)
    (hvars : ∀ v, ∃ i, v ∈ (F i).scope) (b : Finset bn.V × Factor bn ℝ)
    (hb : b ∈ calibrate F t) (Q : Finset bn.V) (hQ : Q ⊆ b.1) (base : bn.Assignment) :
    queryWeight Q b base =
      FiniteDistribution.pushWeight (restrictTo Q) (Factor.product (Finset.univ.toList.map F)) := by
  have hs : (full F t).scope = Finset.univ := full_scope_univ F t (by
    intro v
    obtain ⟨i, hi⟩ := hvars v
    exact ⟨i, hassign.mem_iff.mpr (Finset.mem_toList.2 (Finset.mem_univ _)), hi⟩)
  funext q
  unfold queryWeight
  rw [calibrate_correct F t ht b hb,
    project_project Q b.1 _ (Finset.inter_subset_right.trans hQ),
    project_value, hs, ← Finset.compl_eq_univ_sdiff, full_product_of_perm F t hassign,
    marginal_eq_query_weight, restrict_patch]

theorem factor_product_nonnegative [Fintype I] (F : I → Factor bn ℝ)
    (hF : ∀ i x, 0 ≤ (F i).value x) : ∀ x, 0 ≤ Factor.product (Finset.univ.toList.map F) x := by
  intro x
  unfold Factor.product
  apply List.prod_nonneg
  intro a ha
  obtain ⟨f, hf, rfl⟩ := List.mem_map.1 ha
  obtain ⟨i, _, rfl⟩ := List.mem_map.1 hf
  exact hF i x

def queryPosterior [Fintype I] (F : I → Factor bn ℝ) (t : Tree bn.V I)
    (ht : Good F t) (hassign : t.indices.Perm Finset.univ.toList)
    (hvars : ∀ v, ∃ i, v ∈ (F i).scope) (hF : ∀ i x, 0 ≤ (F i).value x)
    (b : Finset bn.V × Factor bn ℝ) (hb : b ∈ calibrate F t)
    (Q : Finset bn.V) (hQ : Q ⊆ b.1) (base : bn.Assignment) :
    Option (FiniteDistribution.Distribution (PartialAssignment bn Q)) :=
  FiniteDistribution.normalize (queryWeight Q b base) (by
    rw [queryWeight_correct F t ht hassign hvars b hb Q hQ base]
    exact FiniteDistribution.pushWeight_nonneg _ _ (factor_product_nonnegative F hF))

/-- Exact global feasibility, including a zero-mass component disconnected from the queried
clique. The normalized result cannot silently ignore that component. -/
theorem queryPosterior_none_iff [Fintype I] (F : I → Factor bn ℝ) (t : Tree bn.V I)
    (ht : Good F t) (hassign : t.indices.Perm Finset.univ.toList)
    (hvars : ∀ v, ∃ i, v ∈ (F i).scope) (hF : ∀ i x, 0 ≤ (F i).value x)
    (b : Finset bn.V × Factor bn ℝ) (hb : b ∈ calibrate F t)
    (Q : Finset bn.V) (hQ : Q ⊆ b.1) (base : bn.Assignment) :
    queryPosterior F t ht hassign hvars hF b hb Q hQ base = none ↔
      ¬∃ x, 0 < Factor.product (Finset.univ.toList.map F) x := by
  rw [queryPosterior, FiniteDistribution.normalize_none_iff,
    queryWeight_correct F t ht hassign hvars b hb Q hQ base, FiniteDistribution.mass_pushWeight]
  have hn := FiniteDistribution.mass_nonneg _ (factor_product_nonnegative F hF)
  have hz : FiniteDistribution.mass (Factor.product (Finset.univ.toList.map F)) = 0 ↔
      ¬0 < FiniteDistribution.mass (Factor.product (Finset.univ.toList.map F)) :=
    ⟨fun he => by rw [he]; simp, fun he => le_antisymm (le_of_not_gt he) hn⟩
  rw [hz, FiniteDistribution.mass_pos_iff _ (factor_product_nonnegative F hF)]

/-- A returned normalized clique/query posterior is exactly the exhaustive joint posterior. -/
theorem queryPosterior_value [Fintype I] (F : I → Factor bn ℝ) (t : Tree bn.V I)
    (ht : Good F t) (hassign : t.indices.Perm Finset.univ.toList)
    (hvars : ∀ v, ∃ i, v ∈ (F i).scope) (hF : ∀ i x, 0 ≤ (F i).value x)
    (b : Finset bn.V × Factor bn ℝ) (hb : b ∈ calibrate F t)
    (Q : Finset bn.V) (hQ : Q ⊆ b.1) (base : bn.Assignment)
    (d : FiniteDistribution.Distribution (PartialAssignment bn Q))
    (hd : queryPosterior F t ht hassign hvars hF b hb Q hQ base = some d)
    (q : PartialAssignment bn Q) :
    d.pmf q =
      FiniteDistribution.pushWeight (restrictTo Q) (Factor.product (Finset.univ.toList.map F)) q /
        FiniteDistribution.mass (Factor.product (Finset.univ.toList.map F)) := by
  have he := FiniteDistribution.normalize_value _ _ d hd q
  rw [queryWeight_correct F t ht hassign hvars b hb Q hQ base, FiniteDistribution.mass_pushWeight] at he
  exact he

end
end BayesianNetworksProofs.Junction
