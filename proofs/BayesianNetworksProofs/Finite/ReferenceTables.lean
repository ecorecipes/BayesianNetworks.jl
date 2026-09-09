import BayesianNetworksProofs.Finite.RawRecords
import Mathlib.Data.List.Forall2
import Mathlib.Data.Rat.Cast.Order
import Mathlib.Data.Fintype.BigOperators
import Mathlib.Algebra.BigOperators.Fin

/-!
# Finite reference tables and checked resolution

Bindings are finite lists of named/policy references and rational columns. Coordinates are
zero-based after checked external-ID conversion. Complete coordinate coverage, unique columns,
output lengths and nonnegative entries are checked independently of compilation; exact
normalization is a separate check. NoRef and missing bindings are rejected, not silently
replaced by a distribution. Point masses resolve through the checked state labels.

This file specifies a finite data checker/model bridge, not the correctness of Julia or of a
JSON parser. Rational values may represent stored Float64 values exactly without pretending
their row sums are exactly one.
-/

set_option autoImplicit false

namespace BayesianNetworksProofs.Raw

open FinBayesNet

def coordinates : List Nat → List (List Nat)
  | [] => [[]]
  | n :: ns => (List.range n).flatMap fun a => (coordinates ns).map (a :: ·)

theorem coordinates_ofFn (n : Nat) (sizes : Fin n → Nat) (x : (i : Fin n) → Fin (sizes i)) :
    List.ofFn (fun i => (x i).val) ∈ coordinates (List.ofFn sizes) := by
  induction n with
  | zero => simp [coordinates]
  | succ n ih =>
    simp only [List.ofFn_succ, coordinates, List.mem_flatMap, List.mem_range, List.mem_map]
    exact ⟨(x 0).val, (x 0).isLt, List.ofFn (fun i => (x i.succ).val),
      ih (fun i => sizes i.succ) (fun i => x i.succ), rfl⟩

structure Column where
  parents : List Nat
  weights : List ℚ
  deriving DecidableEq

structure Table where
  inputSizes : List Nat
  outputSize : Nat
  columns : List Column
  inputLabels : List (List String) := []
  outputLabels : List String := []
  deriving DecidableEq

def Table.column (t : Table) (ctx : List Nat) : Option Column :=
  t.columns.find? fun c => c.parents == ctx

def Table.read (t : Table) (ctx : List Nat) (a : Nat) : ℚ :=
  ((t.column ctx).getD ⟨[], []⟩).weights.getD a 0

def Table.Ready (t : Table) : Prop :=
  (t.columns.map Column.parents).Nodup ∧
    (∀ ctx ∈ coordinates t.inputSizes, ∃ c ∈ t.columns, c.parents = ctx) ∧
    ∀ c ∈ t.columns, c.parents ∈ coordinates t.inputSizes ∧
      c.weights.length = t.outputSize ∧ ∀ q ∈ c.weights, 0 ≤ q

def Table.Normalized (t : Table) : Prop := ∀ c ∈ t.columns, c.weights.sum = 1

instance (t : Table) : Decidable t.Ready := by unfold Table.Ready; infer_instance
instance (t : Table) : Decidable t.Normalized := by unfold Table.Normalized; infer_instance

theorem find_mem {A : Type} (p : A → Bool) (xs : List A) (a : A)
    (h : xs.find? p = some a) : a ∈ xs ∧ p a = true := by
  induction xs with
  | nil => simp at h
  | cons b xs ih =>
    by_cases hb : p b
    · simp [List.find?, hb] at h
      subst a
      exact ⟨List.mem_cons_self .., hb⟩
    · simp [List.find?, hb] at h
      have hi := ih h
      exact ⟨List.mem_cons_of_mem b hi.1, hi.2⟩

theorem find_exists {A : Type} (p : A → Bool) (xs : List A)
    (h : ∃ a ∈ xs, p a = true) : ∃ a, xs.find? p = some a := by
  induction xs with
  | nil => simp at h
  | cons b xs ih =>
    by_cases hb : p b
    · exact ⟨b, by simp [List.find?, hb]⟩
    · obtain ⟨a, ha, hp⟩ := h
      have ht : a ∈ xs := (List.mem_cons.1 ha).resolve_left (fun he => hb (he ▸ hp))
      obtain ⟨c, hc⟩ := ih ⟨a, ht, hp⟩
      exact ⟨c, by simp [List.find?, hb, hc]⟩

theorem column_exists (t : Table) (h : t.Ready) (ctx : List Nat)
    (hc : ctx ∈ coordinates t.inputSizes) : ∃ c, t.column ctx = some c := by
  apply find_exists
  obtain ⟨c, hmem, he⟩ := h.2.1 ctx hc
  exact ⟨c, hmem, by simpa using he⟩

theorem getD_nonnegative (xs : List ℚ) (h : ∀ q ∈ xs, 0 ≤ q) (n : Nat) :
    0 ≤ xs.getD n 0 := by
  induction xs generalizing n with
  | nil => simp
  | cons q xs ih =>
    cases n with
    | zero => exact h q (List.mem_cons_self ..)
    | succ n => simpa using ih (fun r hr => h r (List.mem_cons_of_mem q hr)) n

theorem sum_getD (xs : List ℚ) : (∑ i : Fin xs.length, xs.getD i.val 0) = xs.sum := by
  induction xs with
  | nil => simp
  | cons q xs ih =>
    rw [List.length_cons, Fin.sum_univ_succ]
    simp

theorem Table.read_nonnegative (t : Table) (h : t.Ready) (ctx : List Nat)
    (hc : ctx ∈ coordinates t.inputSizes) (a : Nat) : 0 ≤ t.read ctx a := by
  obtain ⟨c, he⟩ := column_exists t h ctx hc
  have hmem := (find_mem _ t.columns c he).1
  simpa [Table.read, he] using getD_nonnegative c.weights (h.2.2 c hmem).2.2 a

theorem Table.read_normalized (t : Table) (h : t.Ready) (hn : t.Normalized)
    (ctx : List Nat) (hc : ctx ∈ coordinates t.inputSizes) :
    (∑ a : Fin t.outputSize, t.read ctx a.val) = 1 := by
  obtain ⟨c, he⟩ := column_exists t h ctx hc
  have hmem := (find_mem _ t.columns c he).1
  have hlen := (h.2.2 c hmem).2.1
  simp only [Table.read, he, Option.getD_some]
  rw [← hlen, sum_getD]
  exact hn c hmem

structure Binding where
  ref : Ref
  table : Table
  deriving DecidableEq

abbrev Bank := List Binding

def resolve (bank : Bank) (ref : Ref) : Option Table :=
  (bank.find? fun b => b.ref == ref).map Binding.table

theorem resolve_has_key (bank : Bank) (ref : Ref) (t : Table) (h : resolve bank ref = some t) :
    ∃ b ∈ bank, b.ref = ref ∧ b.table = t := by
  unfold resolve at h
  obtain ⟨b, hb, ht⟩ := Option.map_eq_some_iff.1 h
  have hm := find_mem _ bank b hb
  exact ⟨b, hm.1, by simpa using hm.2, ht⟩

namespace Network

noncomputable section

def slotSizes (r : Network) (h : r.Valid) (m : Fin r.nm) : List Nat :=
  List.ofFn fun j => r.stateCount (r.slotVariable h m j)

def slotIndices (r : Network) (h : r.Valid) (m : Fin r.nm) (x : r.SlotValues h m) : List Nat :=
  List.ofFn fun j => (x j).val

theorem slotIndices_valid (r : Network) (h : r.Valid) (m : Fin r.nm) (x : r.SlotValues h m) :
    r.slotIndices h m x ∈ coordinates (r.slotSizes h m) :=
  coordinates_ofFn _ _ x

def Ready (r : Network) (h : r.Valid) (bank : Bank) : Prop :=
  (bank.map Binding.ref).Nodup ∧ ∀ m,
    match (r.mechanisms m).kernelRef with
    | .none => False
    | .pointMass label => ∃ a : Fin (r.stateCount (r.mechanisms m).target),
        r.stateLabel h (r.mechanisms m).target a = label
    | ref => match resolve bank ref with
      | none => False
      | some t => t.inputSizes = r.slotSizes h m ∧
          t.outputSize = r.stateCount (r.mechanisms m).target ∧ t.Ready

def Normalized (r : Network) (bank : Bank) : Prop :=
  ∀ m t, resolve bank (r.mechanisms m).kernelRef = some t → t.Normalized

def resolvedCPT (r : Network) (h : r.Valid) (bank : Bank) : r.CPT h ℚ :=
  fun m x a =>
    match (r.mechanisms m).kernelRef with
    | .none => 0
    | .pointMass label => if r.stateLabel h (r.mechanisms m).target a = label then 1 else 0
    | ref => match resolve bank ref with
      | none => 0
      | some t => t.read (r.slotIndices h m x) a.val

theorem resolvedCPT_nonnegative (r : Network) (h : r.Valid) (bank : Bank) (hb : r.Ready h bank) :
    ∀ m x a, 0 ≤ r.resolvedCPT h bank m x a := by
  intro m x a
  have hm := hb.2 m
  unfold resolvedCPT
  cases hr : (r.mechanisms m).kernelRef with
  | none => simp [hr] at hm
  | pointMass label =>
    dsimp only
    split_ifs <;> norm_num
  | named key | policy key =>
    cases he : resolve bank (r.mechanisms m).kernelRef with
    | none =>
      simp only [hr] at he
      simp [hr, he] at hm
    | some t =>
      simp only [hr] at he
      have ht : t.inputSizes = r.slotSizes h m ∧
          t.outputSize = r.stateCount (r.mechanisms m).target ∧ t.Ready := by simpa [hr, he] using hm
      simpa only [he] using t.read_nonnegative ht.2.2 _ (ht.1.symm ▸ r.slotIndices_valid h m x) a.val

theorem resolvedCPT_normalized (r : Network) (h : r.Valid) (bank : Bank) (hb : r.Ready h bank)
    (hn : r.Normalized bank) : ∀ m x, ∑ a, r.resolvedCPT h bank m x a = 1 := by
  intro m x
  change (∑ a : Fin (r.stateCount (r.mechanisms m).target), r.resolvedCPT h bank m x a) = 1
  have hm := hb.2 m
  cases hr : (r.mechanisms m).kernelRef with
  | none => simp [hr] at hm
  | pointMass label =>
    obtain ⟨a₀, ha⟩ : ∃ a, r.stateLabel h (r.mechanisms m).target a = label := by simpa [hr] using hm
    have he : ∀ a, r.stateLabel h (r.mechanisms m).target a = label ↔ a = a₀ := by
      intro a
      rw [← ha, (r.stateLabel_injective h _).eq_iff]
    simp [resolvedCPT, hr, he]
  | named key | policy key =>
    cases ht : resolve bank (r.mechanisms m).kernelRef with
    | none =>
      simp only [hr] at ht
      simp [hr, ht] at hm
    | some t =>
      simp only [hr] at ht
      have hv : t.inputSizes = r.slotSizes h m ∧
          t.outputSize = r.stateCount (r.mechanisms m).target ∧ t.Ready := by simpa [hr, ht] using hm
      have hn' : t.Normalized := hn m t (by simpa [hr] using ht)
      have hs := t.read_normalized hv.2.2 hn' _ (hv.1.symm ▸ r.slotIndices_valid h m x)
      rw [hv.2.1] at hs
      simpa only [resolvedCPT, hr, ht] using hs

/-- Checked reference resolution plus checked column normalization yields a normalized joint;
the compiler is not assumed correct, and repeated parent slots are evaluated diagonally. -/
theorem resolved_joint_normalized (r : Network) (h : r.Valid) (bank : Bank)
    (hb : r.Ready h bank) (hn : r.Normalized bank) :
    ∑ x, joint (r.kernel h (r.resolvedCPT h bank)) x = 1 :=
  r.compiled_joint_normalised h _ (r.resolvedCPT_normalized h bank hb hn)

end

/-- Executable finite search by owner and position, before any ordering equivalence is built. -/
def rawInputAt (r : Network) (m : Fin r.nm) (position : Nat) : Option (Fin r.ni) :=
  (List.finRange r.ni).find? fun i =>
    decide ((r.inputs i).mechanism = m ∧ (r.inputs i).position = position)

def rawSlotSize (r : Network) (m : Fin r.nm) (position : Nat) : Nat :=
  match r.rawInputAt m position with
  | none => 0
  | some i => r.stateCount (r.inputs i).var

def rawSlotSizes (r : Network) (m : Fin r.nm) : List Nat :=
  List.ofFn fun i : Fin (r.inputCount m) => r.rawSlotSize m i.val

theorem rawSlotSize_eq (r : Network) (h : r.Valid) (m : Fin r.nm) (i : Fin (r.inputCount m)) :
    r.rawSlotSize m i.val = r.stateCount (r.slotVariable h m i) := by
  let wanted := (r.inputOrder h m).symm i
  have hex : ∃ j, r.rawInputAt m i.val = some j := by
    apply find_exists
    refine ⟨wanted.val, by simp, ?_⟩
    simp only [decide_eq_true_eq]
    exact ⟨wanted.property, r.slot_position h m i⟩
  obtain ⟨j, hj⟩ := hex
  have hfound := (find_mem _ (List.finRange r.ni) j hj).2
  have hpair : (r.inputs j).mechanism = m ∧ (r.inputs j).position = i.val := by simpa using hfound
  have he : j = wanted.val := h.input_positions.2 j wanted.val
    (hpair.1.trans wanted.property.symm) (hpair.2.trans (r.slot_position h m i).symm)
  simp only [rawSlotSize, hj, he]
  rfl

theorem rawSlotSizes_eq (r : Network) (h : r.Valid) (m : Fin r.nm) :
    r.rawSlotSizes m = r.slotSizes h m := by
  apply congrArg List.ofFn
  funext i
  exact r.rawSlotSize_eq h m i

def AxisMatch (r : Network) (m : Fin r.nm) (t : Table) : Prop :=
  t.outputLabels.length = r.stateCount (r.mechanisms m).target ∧
    (∀ s, (r.states s).var = (r.mechanisms m).target →
      t.outputLabels.getD (r.states s).position "" = (r.states s).name) ∧
    t.inputLabels.length = r.inputCount m ∧
    ∀ i, (r.inputs i).mechanism = m →
      (t.inputLabels.getD (r.inputs i).position []).length = r.stateCount (r.inputs i).var ∧
      ∀ s, (r.states s).var = (r.inputs i).var →
        (t.inputLabels.getD (r.inputs i).position []).getD (r.states s).position "" = (r.states s).name

instance (r : Network) (m : Fin r.nm) (t : Table) : Decidable (r.AxisMatch m t) := by
  unfold AxisMatch
  infer_instance

theorem AxisMatch.output (r : Network) (h : r.Valid) (m : Fin r.nm) (t : Table)
    (ht : r.AxisMatch m t) (a : Fin (r.stateCount (r.mechanisms m).target)) :
    t.outputLabels.getD a.val "" = r.stateLabel h (r.mechanisms m).target a := by
  have he := ht.2.1 ((r.stateOrder h _).symm a).val ((r.stateOrder h _).symm a).property
  rw [r.state_position h _ a] at he
  exact he

theorem AxisMatch.input (r : Network) (h : r.Valid) (m : Fin r.nm) (t : Table)
    (ht : r.AxisMatch m t) (j : Fin (r.inputCount m))
    (a : Fin (r.stateCount (r.slotVariable h m j))) :
    (t.inputLabels.getD j.val []).getD a.val "" = r.stateLabel h (r.slotVariable h m j) a := by
  let i := (r.inputOrder h m).symm j
  have hi := ht.2.2.2 i.val i.property
  have he := hi.2 ((r.stateOrder h _).symm a).val ((r.stateOrder h _).symm a).property
  change (t.inputLabels.getD (r.inputs i.val).position []).getD
    (r.states ((r.stateOrder h (r.slotVariable h m j)).symm a).val).position "" = _ at he
  rw [r.state_position h _ a, r.slot_position h m j] at he
  exact he

def optionReady (r : Network) (m : Fin r.nm) : Option Table → Prop
  | none => False
  | some t => (t.inputSizes = r.rawSlotSizes m ∧
      t.outputSize = r.stateCount (r.mechanisms m).target ∧ t.Ready) ∧ r.AxisMatch m t

instance (r : Network) (m : Fin r.nm) (o : Option Table) : Decidable (r.optionReady m o) :=
  match o with
  | none => isFalse (fun h => h)
  | some t => inferInstanceAs (Decidable
      ((t.inputSizes = r.rawSlotSizes m ∧ t.outputSize = r.stateCount (r.mechanisms m).target ∧ t.Ready) ∧
        r.AxisMatch m t))

def rawReferenceReady (r : Network) (bank : Bank) (m : Fin r.nm) : Prop :=
    match (r.mechanisms m).kernelRef with
    | .none => False
    | .pointMass label => ∃ s : Fin r.ns,
        (r.states s).var = (r.mechanisms m).target ∧ (r.states s).name = label
    | .named key => r.optionReady m (resolve bank (.named key))
    | .policy key => r.optionReady m (resolve bank (.policy key))

instance (r : Network) (bank : Bank) (m : Fin r.nm) : Decidable (r.rawReferenceReady bank m) := by
  unfold rawReferenceReady
  exact match (r.mechanisms m).kernelRef with
  | .none => isFalse (fun h => h)
  | .pointMass label => inferInstanceAs (Decidable (∃ s : Fin r.ns,
      (r.states s).var = (r.mechanisms m).target ∧ (r.states s).name = label))
  | .named key => inferInstanceAs (Decidable (r.optionReady m (resolve bank (.named key))))
  | .policy key => inferInstanceAs (Decidable (r.optionReady m (resolve bank (.policy key))))

def RawReady (r : Network) (bank : Bank) : Prop :=
  (bank.map Binding.ref).Nodup ∧ ∀ m, r.rawReferenceReady bank m

def optionNormalized : Option Table → Prop
    | none => True
    | some t => t.Normalized

instance (o : Option Table) : Decidable (optionNormalized o) :=
  match o with
  | none => isTrue trivial
  | some t => inferInstanceAs (Decidable t.Normalized)

def rawReferenceNormalized (r : Network) (bank : Bank) (m : Fin r.nm) : Prop :=
  optionNormalized (resolve bank (r.mechanisms m).kernelRef)

instance (r : Network) (bank : Bank) (m : Fin r.nm) : Decidable (r.rawReferenceNormalized bank m) :=
  inferInstanceAs (Decidable (optionNormalized (resolve bank (r.mechanisms m).kernelRef)))

def RawNormalized (r : Network) (bank : Bank) : Prop :=
  ∀ m, r.rawReferenceNormalized bank m

instance (r : Network) (bank : Bank) : Decidable (r.RawReady bank) := by
  unfold RawReady
  infer_instance

instance (r : Network) (bank : Bank) : Decidable (r.RawNormalized bank) := by
  unfold RawNormalized
  infer_instance

def checkReady (r : Network) (bank : Bank) : Bool := decide (r.RawReady bank)
def checkNormalized (r : Network) (bank : Bank) : Bool := decide (r.RawNormalized bank)

theorem rawReady_sound (r : Network) (h : r.Valid) (bank : Bank) (hb : r.RawReady bank) :
    r.Ready h bank := by
  refine ⟨hb.1, ?_⟩
  intro m
  have hm := hb.2 m
  unfold rawReferenceReady at hm
  cases hr : (r.mechanisms m).kernelRef with
  | none => simp [hr] at hm
  | pointMass label =>
    obtain ⟨s, hs, hn⟩ : ∃ s, (r.states s).var = (r.mechanisms m).target ∧
        (r.states s).name = label := by simpa [hr] using hm
    refine ⟨r.stateOrder h _ ⟨s, hs⟩, ?_⟩
    simpa [stateLabel] using hn
  | named key | policy key =>
    cases ht : resolve bank (r.mechanisms m).kernelRef with
    | none =>
      simp only [hr] at ht
      simp [hr, ht, optionReady] at hm
    | some t =>
      simp only [hr] at ht
      have hv' : (t.inputSizes = r.rawSlotSizes m ∧
          t.outputSize = r.stateCount (r.mechanisms m).target ∧ t.Ready) ∧ r.AxisMatch m t := by
        simpa [hr, ht, optionReady] using hm
      have hv := hv'.1
      simpa only [ht] using And.intro (hv.1.trans (r.rawSlotSizes_eq h m)) hv.2

theorem rawNormalized_sound (r : Network) (bank : Bank) (hn : r.RawNormalized bank) :
    r.Normalized bank := by
  intro m t ht
  have hm := hn m
  simpa [rawReferenceNormalized, optionNormalized, ht] using hm

/-- A finite Boolean certificate check, not an assumed compiler theorem, establishes normalized
semantics for the raw reference-resolved, repeated-slot network. -/
theorem checked_reference_normalization (r : Network) (bank : Bank)
    (hs : r.check = true) (hb : r.checkReady bank = true) (hn : r.checkNormalized bank = true) :
    let h := (r.check_iff).1 hs
    ∑ x, joint (r.kernel h (r.resolvedCPT h bank)) x = 1 := by
  let h := (r.check_iff).1 hs
  exact r.resolved_joint_normalized h bank (r.rawReady_sound h bank (of_decide_eq_true hb))
    (r.rawNormalized_sound bank (of_decide_eq_true hn))

noncomputable def realKernel (r : Network) (h : r.Valid) (bank : Bank) : (r.compile h).Kernel ℝ :=
  r.kernel h (fun m x a => (r.resolvedCPT h bank m x a : ℝ))

theorem realKernel_local (r : Network) (h : r.Valid) (bank : Bank) :
    ∀ m, Local (r.realKernel h bank) m := r.kernel_local h _

theorem realKernel_nonnegative (r : Network) (h : r.Valid) (bank : Bank) (hb : r.RawReady bank) :
    ∀ m x a, 0 ≤ r.realKernel h bank m x a := by
  intro m x a
  change (0 : ℝ) ≤ (r.resolvedCPT h bank m (r.gather h m x) a : ℝ)
  exact_mod_cast r.resolvedCPT_nonnegative h bank (r.rawReady_sound h bank hb) m (r.gather h m x) a

theorem realKernel_normalized (r : Network) (h : r.Valid) (bank : Bank)
    (hb : r.RawReady bank) (hn : r.RawNormalized bank) :
    ∀ m, Normalised (r.realKernel h bank) m := by
  intro m x
  have hs := r.resolvedCPT_normalized h bank (r.rawReady_sound h bank hb)
    (r.rawNormalized_sound bank hn) m (r.gather h m x)
  change (∑ a : Fin (r.stateCount (r.mechanisms m).target),
    (r.resolvedCPT h bank m (r.gather h m x) a : ℝ)) = 1
  have hr := congrArg (Rat.castHom ℝ) hs
  rw [map_sum, map_one] at hr
  exact hr

end Network
end BayesianNetworksProofs.Raw
