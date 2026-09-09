import BayesianNetworksProofs.Finite.ReferenceTables
import BayesianNetworksProofs.Finite.JunctionTree
import BayesianNetworksProofs.Finite.DSeparation
import BayesianNetworksProofs.Finite.NumericalContracts
import Mathlib.Tactic.FinCases

/-!
# Nonvacuity and boundary checks

The raw certificate has shuffled state/input row IDs and two repeated parent slots.
The junction example has three disconnected components and impossible evidence in a component
other than the query. The graphical example is a three-variable fork: its children are
d-separated given their parent, by an actual edgeless cut-moral graph argument.
-/

set_option autoImplicit false

namespace BayesianNetworksProofs.RefinementExamples

open FinBayesNet FinBayesNet.Factor Junction

@[reducible] def raw : Raw.Network where
  nv := 2
  ns := 4
  nm := 2
  ni := 2
  vars v := ⟨if v = 0 then "A" else "B", .none⟩
  states s := if s = 0 then ⟨0, 1, "a1"⟩ else if s = 1 then ⟨0, 0, "a0"⟩ else
    if s = 2 then ⟨1, 0, "b0"⟩ else ⟨1, 1, "b1"⟩
  mechanisms m := ⟨m, if m = 0 then "prior" else "child",
    .named (if m = 0 then "prior" else "child")⟩
  inputs i := ⟨1, 0, if i = 0 then 1 else 0⟩
  rank := id

def bank : Raw.Bank := [
  ⟨.named "prior", ⟨[], 2, [⟨[], [1/2, 1/2]⟩], [], ["a0", "a1"]⟩⟩,
  ⟨.named "child", ⟨[2,2], 2,
    [⟨[0,0], [1,0]⟩, ⟨[0,1], [0,1]⟩, ⟨[1,0], [1/2,1/2]⟩, ⟨[1,1], [0,1]⟩],
    [["a0","a1"], ["a0","a1"]], ["b0","b1"]⟩⟩]

theorem raw_structure_checked : raw.check = true := by decide
theorem raw_references_checked : raw.checkReady bank = true := by decide +kernel
theorem raw_normalization_checked : raw.checkNormalized bank = true := by decide +kernel
theorem raw_two_slots : raw.inputCount 1 = 2 := by decide

def badPositions : Raw.Network := {raw with inputs := fun _ => ⟨1, 0, 0⟩}
theorem bad_positions_rejected : badPositions.check = false := by decide +kernel

def badLabels : Raw.Bank := bank.map fun b =>
  if b.ref = .named "prior" then {b with table := {b.table with outputLabels := ["wrong", "a1"]}}
  else b
theorem bad_labels_rejected : raw.checkReady badLabels = false := by decide +kernel

def unnormalized : Raw.Bank := bank.map fun b =>
  if b.ref = .named "prior" then {b with table := {b.table with columns := [⟨[], [2/3, 2/3]⟩]}}
  else b
theorem unnormalized_data_interpretable : raw.checkReady unnormalized = true := by decide +kernel
theorem unnormalized_probability_rejected : raw.checkNormalized unnormalized = false := by decide +kernel
theorem unresolved_reference_rejected : raw.checkReady [] = false := by decide +kernel

noncomputable section

def rawValid : raw.Valid := (raw.check_iff).1 raw_structure_checked

theorem raw_diagonal (i j : Fin (raw.inputCount 1)) (x : (raw.compile rawValid).Assignment) :
    (raw.gather rawValid 1 x i).val = (raw.gather rawValid 1 x j).val := by
  apply raw.repeated_slots_diagonal rawValid
  simp [Raw.Network.slotVariable, raw]

theorem raw_compiled_probability :
    ∑ x, joint (raw.kernel rawValid (raw.resolvedCPT rawValid bank)) x = 1 :=
  raw.checked_reference_normalization bank raw_structure_checked raw_references_checked raw_normalization_checked

@[reducible] def fork : FinBayesNet where
  V := Fin 3
  M := Fin 3
  states _ := Bool
  target := id
  parents m := if m = 0 then ∅ else {0}

theorem fork_closed : fork.Closed := ⟨Function.injective_id, Function.surjective_id⟩

def fork_order : fork.TopoOrder where
  order := [0,1,2]
  nodup := by decide
  complete := by decide
  parents_before := by decide
  no_self := by decide

def forkKernel : fork.Kernel ℝ := fun (m : Fin 3) (x : Fin 3 → Bool) (a : Bool) =>
  if m = 0 then 1/2 else if a = x 0 then 1 else 0

theorem fork_local : ∀ m, Local forkKernel m := by
  intro m x y h
  funext a
  by_cases hm : m = 0
  · simp [forkKernel, hm]
  · have h0 := h 0 (by simp [fork, hm])
    simp [forkKernel, hm, h0]

theorem fork_normalized : ∀ m, Normalised forkKernel m := by
  intro m x
  change (∑ a : Bool, forkKernel m x a) = 1
  by_cases hm : m = 0 <;> simp [forkKernel, hm]

theorem fork_nonnegative : ∀ m x a, 0 ≤ forkKernel m x a := by
  intro m x a
  unfold forkKernel
  split_ifs <;> norm_num

theorem fork_cut_edgeless (U : Finset fork.V) : cutMoral U {0} = ⊥ := by
  ext v w
  constructor
  · intro he
    obtain ⟨hne, m, _, hv, hw⟩ := he.1
    have hs : ∀ m : fork.M, ∀ v w, v ∈ family fork m \ {0} → w ∈ family fork m \ {0} → v = w := by
      decide
    exact hne (hs m v w (Finset.mem_sdiff.2 ⟨hv, he.2.1⟩) (Finset.mem_sdiff.2 ⟨hw, he.2.2⟩))
  · intro he
    exact False.elim he

theorem fork_graph_separated : DSeparated (bn := fork) {1} {2} {0} := by
  intro a ha b hb hpath
  have ha' : a = 1 := by simpa using ha
  have hb' : b = 2 := by simpa using hb
  subst a
  subst b
  rw [fork_cut_edgeless, SimpleGraph.reachable_bot] at hpath
  exact (by decide : (1 : Fin 3) ≠ 2) hpath

theorem fork_conditional_independence :
    ConditionalIndependent (joint forkKernel) {1} {2} {0} :=
  d_separation_sound forkKernel fork_closed fork_order fork_local fork_normalized
    {1} {2} {0} (by decide) (by decide) fork_graph_separated

def forkFactor (m : fork.M) : Factor fork ℝ := Factor.mechanism forkKernel fork_local m

def connectedTree : Tree fork.V fork.M :=
  .branch {0,1} [0,1] (.leaf {0,2} [2]) (.leaf {0,1} [])

theorem connected_tree_valid : Good forkFactor connectedTree := by
  simp [Good, connectedTree, forkFactor, localFactor, combine, multiply, unit,
    Factor.mechanism, fork, Tree.vars, Tree.bag]
  decide

theorem connected_assignment : connectedTree.indices.Perm (Finset.univ : Finset fork.M).toList := by
  apply (List.perm_ext_iff_of_nodup (by decide) (Finset.nodup_toList _)).2
  intro i
  fin_cases i <;> simp [connectedTree, Tree.indices]

theorem connected_tree_check : checkGood forkFactor connectedTree = true := by decide +kernel

theorem connected_assignment_check : checkAssignment connectedTree = true := by decide +kernel

theorem connected_variables : ∀ v : fork.V, ∃ m, v ∈ (forkFactor m).scope :=
  fun v => ⟨v, Finset.mem_insert_self _ _⟩

theorem nonempty_separator_belief_exists :
    ∃ b ∈ calibrate forkFactor connectedTree, b.1 = ({0,2} : Finset fork.V) := by
  simp [calibrate, connectedTree, prepare, distribute]

theorem connected_beliefs_match_ve (b : Finset fork.V × Factor fork ℝ)
    (hb : b ∈ calibrate forkFactor connectedTree) (vs : List fork.V)
    (hv : vs.Nodup) (hs : vs.toFinset = b.1ᶜ) (x : fork.Assignment) :
    b.2.value x = Factor.product (Factor.eliminateAll (Finset.univ.toList.map forkFactor) vs) x :=
  calibrate_eq_ve forkFactor connectedTree connected_tree_valid connected_assignment
    connected_variables b hb vs hv hs x

@[reducible] def roots : FinBayesNet := {fork with parents := fun _ => ∅}

def rootKernel : roots.Kernel ℝ := fun (m : Fin 3) (_ : Fin 3 → Bool) (a : Bool) =>
  if m = 1 then (if a = false then 1 else 0) else 1/2

theorem root_local : ∀ m, Local rootKernel m := fun _ _ _ _ => rfl

def observed : roots.Assignment := fun _ => true

def forestFactor (i : Fin 4) : Factor roots ℝ :=
  if h : i.val < 3 then Factor.mechanism rootKernel root_local ⟨i.val, h⟩
  else evidenceFactor {1} observed

def forestTree : Tree roots.V (Fin 4) :=
  graft ∅ [] [.leaf {0} [0], .leaf {1} [1,3], .leaf {2} [2]]

theorem forest_valid : Good forestFactor forestTree := by
  apply forest_good
  · intro t ht
    simp only [List.mem_cons, List.not_mem_nil, or_false] at ht
    rcases ht with rfl | rfl | rfl <;>
      simp [Good, localFactor, combine, multiply, unit, forestFactor, Factor.mechanism,
        evidenceFactor, roots, fork]
  · decide

theorem forest_assignment : forestTree.indices.Perm (Finset.univ : Finset (Fin 4)).toList := by
  apply (List.perm_ext_iff_of_nodup (by decide) (Finset.nodup_toList _)).2
  intro i
  fin_cases i <;> simp [forestTree, graft_indices, Tree.indices]

theorem forest_variables : ∀ v : roots.V, ∃ i, v ∈ (forestFactor i).scope := by
  intro v
  fin_cases v
  · exact ⟨0, by decide⟩
  · exact ⟨1, by decide⟩
  · exact ⟨2, by decide⟩

theorem forest_nonnegative : ∀ i x, 0 ≤ (forestFactor i).value x := by
  intro i x
  fin_cases i
  all_goals simp [forestFactor, Factor.mechanism, rootKernel, evidenceFactor, indicator, agrees]
  all_goals split_ifs <;> norm_num

theorem product_zero_of_mem {fs : List (Factor roots ℝ)} {f : Factor roots ℝ}
    (hf : f ∈ fs) (x : roots.Assignment) (hz : f.value x = 0) : Factor.product fs x = 0 := by
  induction fs with
  | nil => simp at hf
  | cons g fs ih =>
    rw [Factor.product_cons]
    rcases List.mem_cons.1 hf with rfl | hf
    · rw [hz, zero_mul]
    · rw [ih hf, mul_zero]

theorem forest_zero_mass (x : roots.Assignment) :
    Factor.product ((Finset.univ : Finset (Fin 4)).toList.map forestFactor) x = 0 := by
  cases hx : x 1
  · apply product_zero_of_mem (f := forestFactor 3)
    · exact List.mem_map.2 ⟨3, Finset.mem_toList.2 (Finset.mem_univ _), rfl⟩
    · simp [forestFactor, evidenceFactor, indicator, agrees, observed, hx]
  · apply product_zero_of_mem (f := forestFactor 1)
    · exact List.mem_map.2 ⟨1, Finset.mem_toList.2 (Finset.mem_univ _), rfl⟩
    · simp [forestFactor, Factor.mechanism, rootKernel, roots, fork, hx]

/-- Even a query in the other disconnected component must reject the globally impossible event. -/
theorem disconnected_query_rejects (b : Finset roots.V × Factor roots ℝ)
    (hb : b ∈ calibrate forestFactor forestTree) (Q : Finset roots.V) (hQ : Q ⊆ b.1)
    (base : roots.Assignment) :
    queryPosterior forestFactor forestTree forest_valid forest_assignment forest_variables
      forest_nonnegative b hb Q hQ base = none := by
  rw [queryPosterior_none_iff]
  simp [forest_zero_mass]

end
end BayesianNetworksProofs.RefinementExamples
