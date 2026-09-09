import BayesianNetworksProofs.Finite.OrderedParents
import BayesianNetworksProofs.Finite.VariableElimination
import Mathlib.Data.Fintype.EquivFin
import Mathlib.Data.List.OfFn
import Mathlib.Data.Real.Basic

/-!
# Checked finite records, positions and repeated input slots

Raw rows carry concrete finite IDs, names, references and numeric positions. `decodeId`
checks external one-based IDs before constructing those finite IDs. Position validity is
only a boundedness/injectivity check on each owner fibre; finiteness derives surjectivity
onto every contiguous position. Input variables need not be injective: repeated slots read
the same assignment coordinate, i.e. diagonal rather than independent evaluation.

`Valid` consists of decidable structural facts, not a compiler-correctness certificate.
The compiler derives the abstract parent sets, state spaces, closedness and topological order.
Raw names/references remain attached to the records; the finite-network reduct deliberately
erases metadata. This is not a theorem about the Julia compiler or its JSON parser.
-/

set_option autoImplicit false

namespace BayesianNetworksProofs.Raw

open FinBayesNet

def decodeId (n external : Nat) : Option (Fin n) :=
  if h : 0 < external ∧ external ≤ n then some ⟨external - 1, by omega⟩ else none

theorem decodeId_none_iff (n external : Nat) :
    decodeId n external = none ↔ external = 0 ∨ n < external := by
  unfold decodeId
  split_ifs <;> simp_all <;> omega

theorem decodeId_value {n external : Nat} {i : Fin n} (h : decodeId n external = some i) :
    i.val + 1 = external := by
  unfold decodeId at h
  split_ifs at h with hb
  · cases Option.some.inj h
    change external - 1 + 1 = external
    omega

inductive Ref
  | named (key : String)
  | policy (key : String)
  | pointMass (state : String)
  | none
  deriving DecidableEq

structure VariableRow where
  name : String
  spaceRef : Ref

structure StateRow (nv : Nat) where
  var : Fin nv
  position : Nat
  name : String

structure MechanismRow (nv : Nat) where
  target : Fin nv
  name : String
  kernelRef : Ref

structure InputRow (nv nm : Nat) where
  mechanism : Fin nm
  var : Fin nv
  position : Nat

structure Network where
  nv : Nat
  ns : Nat
  nm : Nat
  ni : Nat
  vars : Fin nv → VariableRow
  states : Fin ns → StateRow nv
  mechanisms : Fin nm → MechanismRow nv
  inputs : Fin ni → InputRow nv nm
  rank : Fin nv → Fin nv

def Positioned {nr no : Nat} (owner : Fin nr → Fin no) (pos : Fin nr → Nat) : Prop :=
  (∀ r, pos r < Fintype.card {s : Fin nr // owner s = owner r}) ∧
    ∀ r s, owner r = owner s → pos r = pos s → r = s

instance {nr no : Nat} (owner : Fin nr → Fin no) (pos : Fin nr → Nat) :
    Decidable (Positioned owner pos) := by unfold Positioned; infer_instance

def positionMap {nr no : Nat} (owner : Fin nr → Fin no) (pos : Fin nr → Nat)
    (h : Positioned owner pos) (o : Fin no) (r : {s : Fin nr // owner s = o}) :
    Fin (Fintype.card {s : Fin nr // owner s = o}) :=
  ⟨pos r.val, by simpa only [r.property] using h.1 r.val⟩

/-- Total positional coverage follows from checked bounds, uniqueness, and equal finite
cardinalities; an ordering equivalence is not an input assumption. -/
noncomputable def positionEquiv {nr no : Nat} (owner : Fin nr → Fin no) (pos : Fin nr → Nat)
    (h : Positioned owner pos) (o : Fin no) :
    {s : Fin nr // owner s = o} ≃ Fin (Fintype.card {s : Fin nr // owner s = o}) :=
  Equiv.ofBijective (positionMap owner pos h o) ((Fintype.bijective_iff_injective_and_card _).2 ⟨
    (by
      intro r s he
      apply Subtype.ext
      exact h.2 r.val s.val (r.property.trans s.property.symm) (congrArg Fin.val he)),
    by simp⟩)

namespace Network

def stateOwner (r : Network) (s : Fin r.ns) := (r.states s).var
def inputOwner (r : Network) (i : Fin r.ni) := (r.inputs i).mechanism
def stateCount (r : Network) (v : Fin r.nv) := Fintype.card {s : Fin r.ns // r.stateOwner s = v}
def inputCount (r : Network) (m : Fin r.nm) := Fintype.card {i : Fin r.ni // r.inputOwner i = m}

structure Valid (r : Network) : Prop where
  state_positions : Positioned r.stateOwner (fun s => (r.states s).position)
  input_positions : Positioned r.inputOwner (fun i => (r.inputs i).position)
  nonempty_states : ∀ v, 0 < r.stateCount v
  state_names : ∀ s t, (r.states s).var = (r.states t).var →
    (r.states s).name = (r.states t).name → s = t
  generators : Function.Bijective (fun m => (r.mechanisms m).target)
  rank_injective : Function.Injective r.rank
  causal_rank : ∀ i, r.rank (r.inputs i).var < r.rank (r.mechanisms (r.inputs i).mechanism).target

theorem valid_iff (r : Network) : r.Valid ↔
    Positioned r.stateOwner (fun s => (r.states s).position) ∧
    Positioned r.inputOwner (fun i => (r.inputs i).position) ∧
    (∀ v, 0 < r.stateCount v) ∧
    (∀ s t, (r.states s).var = (r.states t).var → (r.states s).name = (r.states t).name → s = t) ∧
    Function.Bijective (fun m => (r.mechanisms m).target) ∧ Function.Injective r.rank ∧
    (∀ i, r.rank (r.inputs i).var < r.rank (r.mechanisms (r.inputs i).mechanism).target) :=
  ⟨fun h => ⟨h.state_positions, h.input_positions, h.nonempty_states, h.state_names,
    h.generators, h.rank_injective, h.causal_rank⟩,
    fun h => ⟨h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2⟩⟩

instance (r : Network) : Decidable r.Valid := by
  letI : Decidable (Function.Bijective (fun m => (r.mechanisms m).target)) := by
    unfold Function.Bijective Function.Injective Function.Surjective
    infer_instance
  letI : Decidable (Function.Injective r.rank) := by
    unfold Function.Injective
    infer_instance
  exact decidable_of_iff _ (valid_iff r).symm

def check (r : Network) : Bool := decide r.Valid

theorem check_iff (r : Network) : r.check = true ↔ r.Valid := by simp [check]

noncomputable section

@[reducible] def compile (r : Network) (h : r.Valid) : FinBayesNet where
  V := Fin r.nv
  M := Fin r.nm
  states v := Fin (r.stateCount v)
  nonemptyS v := ⟨⟨0, h.nonempty_states v⟩⟩
  target m := (r.mechanisms m).target
  parents m := (Finset.univ.filter fun i => (r.inputs i).mechanism = m).image
    (fun i => (r.inputs i).var)

def stateOrder (r : Network) (h : r.Valid) (v : Fin r.nv) :
    {s : Fin r.ns // (r.states s).var = v} ≃ Fin (r.stateCount v) :=
  positionEquiv r.stateOwner (fun s => (r.states s).position) h.state_positions v

def inputOrder (r : Network) (h : r.Valid) (m : Fin r.nm) :
    {i : Fin r.ni // (r.inputs i).mechanism = m} ≃ Fin (r.inputCount m) :=
  positionEquiv r.inputOwner (fun i => (r.inputs i).position) h.input_positions m

def stateLabel (r : Network) (h : r.Valid) (v : Fin r.nv) (a : Fin (r.stateCount v)) : String :=
  (r.states ((r.stateOrder h v).symm a).val).name

theorem stateLabel_injective (r : Network) (h : r.Valid) (v : Fin r.nv) :
    Function.Injective (r.stateLabel h v) := by
  intro a b he
  have hs : (r.stateOrder h v).symm a = (r.stateOrder h v).symm b := by
    apply Subtype.ext
    exact h.state_names _ _ (((r.stateOrder h v).symm a).property.trans
      ((r.stateOrder h v).symm b).property.symm) he
  exact (r.stateOrder h v).symm.injective hs

def slotVariable (r : Network) (h : r.Valid) (m : Fin r.nm) (j : Fin (r.inputCount m)) : Fin r.nv :=
  (r.inputs ((r.inputOrder h m).symm j).val).var

theorem slot_position (r : Network) (h : r.Valid) (m : Fin r.nm) (j : Fin (r.inputCount m)) :
    (r.inputs ((r.inputOrder h m).symm j).val).position = j.val :=
  congrArg Fin.val ((r.inputOrder h m).apply_symm_apply j)

theorem state_position (r : Network) (h : r.Valid) (v : Fin r.nv) (j : Fin (r.stateCount v)) :
    (r.states ((r.stateOrder h v).symm j).val).position = j.val :=
  congrArg Fin.val ((r.stateOrder h v).apply_symm_apply j)

theorem slot_image (r : Network) (h : r.Valid) (m : Fin r.nm) :
    Finset.univ.image (r.slotVariable h m) = (r.compile h).parents m := by
  ext v
  constructor
  · rintro hv
    obtain ⟨j, _, rfl⟩ := Finset.mem_image.1 hv
    exact Finset.mem_image.2 ⟨((r.inputOrder h m).symm j).val,
      Finset.mem_filter.2 ⟨Finset.mem_univ _, ((r.inputOrder h m).symm j).property⟩, rfl⟩
  · intro hv
    obtain ⟨i, hi, rfl⟩ := Finset.mem_image.1 hv
    let s : {i : Fin r.ni // (r.inputs i).mechanism = m} := ⟨i, (Finset.mem_filter.1 hi).2⟩
    refine Finset.mem_image.2 ⟨r.inputOrder h m s, Finset.mem_univ _, ?_⟩
    simp [slotVariable, s]

def rankEquiv (r : Network) (h : r.Valid) : Fin r.nv ≃ Fin r.nv :=
  Equiv.ofBijective r.rank ⟨h.rank_injective, Finite.surjective_of_injective h.rank_injective⟩

/-- A checked ranking produces the topological list, rather than assuming a compiler theorem. -/
def topological (r : Network) (h : r.Valid) : (r.compile h).TopoOrder where
  order := List.ofFn (r.rankEquiv h).symm
  nodup := List.nodup_ofFn.2 (r.rankEquiv h).symm.injective
  complete v := List.mem_ofFn.2 ⟨r.rankEquiv h v, (r.rankEquiv h).symm_apply_apply v⟩
  parents_before := by
    apply List.pairwise_ofFn.2
    intro i j hij m hm hv
    obtain ⟨slot, hs, he⟩ := Finset.mem_image.1 hv
    have heOwner := (Finset.mem_filter.1 hs).2
    have hr := h.causal_rank slot
    have hi : r.rank ((r.rankEquiv h).symm i) = i := (r.rankEquiv h).apply_symm_apply i
    have hj : r.rank ((r.rankEquiv h).symm j) = j := (r.rankEquiv h).apply_symm_apply j
    change (r.mechanisms m).target = (r.rankEquiv h).symm i at hm
    rw [heOwner, hm, he, hi, hj] at hr
    exact (not_lt_of_ge hij.le) hr
  no_self m := by
    intro hm
    obtain ⟨i, hi, he⟩ := Finset.mem_image.1 hm
    have hr := h.causal_rank i
    rw [(Finset.mem_filter.1 hi).2, he] at hr
    exact (lt_irrefl _ hr)

theorem compile_closed (r : Network) (h : r.Valid) : (r.compile h).Closed := h.generators

abbrev SlotValues (r : Network) (h : r.Valid) (m : Fin r.nm) :=
  (j : Fin (r.inputCount m)) → (r.compile h).states (r.slotVariable h m j)

def gather (r : Network) (h : r.Valid) (m : Fin r.nm) (x : (r.compile h).Assignment) :
    r.SlotValues h m := fun j => x (r.slotVariable h m j)

abbrev CPT (r : Network) (h : r.Valid) (R : Type) :=
  (m : Fin r.nm) → r.SlotValues h m → (r.compile h).states ((r.compile h).target m) → R

def kernel (r : Network) (h : r.Valid) {R : Type} (t : r.CPT h R) : (r.compile h).Kernel R :=
  fun m x => t m (r.gather h m x)

theorem kernel_local (r : Network) (h : r.Valid) {R : Type} (t : r.CPT h R) :
    ∀ m, Local (r.kernel h t) m := by
  intro m x y hx
  apply congrArg (t m)
  funext j
  apply hx
  rw [← r.slot_image h m]
  exact Finset.mem_image_of_mem _ (Finset.mem_univ j)

/-- Repeated input-variable slots are evaluated on the diagonal, not sampled independently. -/
theorem repeated_slots_diagonal (r : Network) (h : r.Valid) (m : Fin r.nm)
    (i j : Fin (r.inputCount m)) (he : r.slotVariable h m i = r.slotVariable h m j)
    (x : (r.compile h).Assignment) :
    (r.gather h m x i).val = (r.gather h m x j).val :=
  congrArg (fun v => (x v).val) he

theorem kernel_normalised (r : Network) (h : r.Valid) {R : Type} [CommSemiring R]
    (t : r.CPT h R) (ht : ∀ m z, ∑ a, t m z a = 1) :
    ∀ m, Normalised (r.kernel h t) m := fun m x => ht m (r.gather h m x)

theorem compiled_joint_normalised (r : Network) (h : r.Valid) {R : Type} [CommSemiring R]
    (t : r.CPT h R) (ht : ∀ m z, ∑ a, t m z a = 1) :
    ∑ x, joint (r.kernel h t) x = 1 :=
  sum_joint_eq_one _ (r.compile_closed h) (r.topological h)
    (r.kernel_local h t) (r.kernel_normalised h t ht)

/-- The existing valuation/factor compiler preserves the actual repeated-slot CPT product. -/
theorem factor_compilation (r : Network) (h : r.Valid) (t : r.CPT h ℝ) :
    Factor.product (Factor.ofKernel (r.kernel h t) (r.kernel_local h t)) =
      fun x => ∏ m, t m (r.gather h m x) (x ((r.compile h).target m)) := by
  rw [Factor.product_ofKernel]
  rfl

end
end Network
end BayesianNetworksProofs.Raw
