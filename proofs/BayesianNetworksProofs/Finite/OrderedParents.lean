import BayesianNetworksProofs.Finite.Evaluation
import Mathlib.Logic.Equiv.Basic

/-!
# BayesianNetworksProofs.Finite.OrderedParents

**An exact ordered-parent refinement of the finite kernel model** (SPEC §8.2, §10.2,
§11 and the §61 revision-note qualification).

`ParentOrder` equips every mechanism with a bijection from contiguous positions `Fin n` to
its parent variables. Thus each parent occurs exactly once and every position is used.
An ordered CPT takes a dependent tuple of states in this order, followed by its child's
state. Gathering an assignment into that tuple gives a local kernel. Conversely, every
local kernel has an ordered CPT, and the two constructions are inverse.

Changing parent order must be accompanied by a corresponding change in the CPT axes:
`toKernel_reindex` proves the precise transport law, including heterogeneous parent state
types. `sum_joint_ordered` transfers the existing normalisation theorem to ordered CPTs.

This closes the unordered-versus-ordered *finite function* gap, not the entire ACSet gap.
The bijection is supplied as data; this file does not parse `Input` rows, verify Julia's
sorting routine, model `state_position`, resolve `KernelRef`s, or relate real arithmetic to
floating-point arrays. Those correspondence claims remain unproved.
-/

set_option autoImplicit false

namespace BayesianNetworksProofs.FinBayesNet

variable (bn : FinBayesNet)

/-- Contiguous, total and duplicate-free positions for each mechanism's parents.
Julia uses one-based positions; `Fin n` is their zero-based mathematical index. -/
structure ParentOrder where
  count : bn.M → ℕ
  atPosition : (m : bn.M) → Fin (count m) ≃ {v : bn.V // v ∈ bn.parents m}

namespace ParentOrder

variable {bn} (o : ParentOrder bn) {R : Type}

/-- A tuple of parent states in explicit positional order. -/
abbrev Values (m : bn.M) :=
  (i : Fin (o.count m)) → bn.states (o.atPosition m i).val

/-- The equivalent parent-indexed view of a positional tuple. -/
def valuesEquiv (m : bn.M) :
    o.Values m ≃ ((v : {v : bn.V // v ∈ bn.parents m}) → bn.states v.val) :=
  Equiv.piCongrLeft (fun v : {v : bn.V // v ∈ bn.parents m} => bn.states v.val) (o.atPosition m)

/-- Gather a joint assignment according to the declared input positions. -/
def gather (m : bn.M) (x : bn.Assignment) : o.Values m :=
  fun i => x (o.atPosition m i).val

theorem valuesEquiv_gather (m : bn.M) (x : bn.Assignment) :
    o.valuesEquiv m (o.gather m x) = fun v : {v : bn.V // v ∈ bn.parents m} => x v.val := by
  apply (o.valuesEquiv m).symm.injective
  rw [Equiv.symm_apply_apply]
  rfl

/-- Extend parent values to all variables, using the model's nonempty state spaces off-scope. -/
noncomputable def extend (m : bn.M)
    (p : (v : {v : bn.V // v ∈ bn.parents m}) → bn.states v.val) : bn.Assignment :=
  fun v => if hv : v ∈ bn.parents m then p ⟨v, hv⟩ else Classical.choice (bn.nonemptyS v)

theorem gather_extend (m : bn.M) (z : o.Values m) :
    o.gather m (extend m (o.valuesEquiv m z)) = z := by
  have hg : o.gather m (extend m (o.valuesEquiv m z)) =
      (o.valuesEquiv m).symm (o.valuesEquiv m z) := by
    funext i
    simp [gather, extend, (o.atPosition m i).property, valuesEquiv]
  rw [hg, Equiv.symm_apply_apply]

/-- User-facing CPT convention: ordered parent tuple first, child's state last. -/
abbrev CPT (R : Type) :=
  (m : bn.M) → o.Values m → bn.states (bn.target m) → R

/-- Interpret an ordered CPT in the abstract assignment-based model. -/
def toKernel (t : o.CPT R) : bn.Kernel R :=
  fun m x => t m (o.gather m x)

theorem toKernel_local (t : o.CPT R) : ∀ m, Local (o.toKernel t) m := by
  intro m x y h
  apply congrArg (t m)
  funext i
  exact h (o.atPosition m i).val (o.atPosition m i).property

/-- Read a kernel on all possible positional tuples, completing the unused variables. -/
noncomputable def ofKernel (κ : bn.Kernel R) : o.CPT R :=
  fun m z => κ m (extend m (o.valuesEquiv m z))

/-- Locality makes the arbitrary off-parent completion unobservable. -/
theorem toKernel_ofKernel (κ : bn.Kernel R) (hloc : ∀ m, Local κ m) :
    o.toKernel (o.ofKernel κ) = κ := by
  funext m x
  apply hloc m
  intro v hv
  simp [extend, valuesEquiv_gather, hv]

/-- Ordered CPTs are recovered exactly, not only on the assignments used by an evaluator. -/
theorem ofKernel_toKernel (t : o.CPT R) : o.ofKernel (o.toKernel t) = t := by
  funext m z
  change t m (o.gather m (extend m (o.valuesEquiv m z))) = t m z
  rw [gather_extend]

/-- The unordered locality condition is precisely representability by an ordered CPT. -/
theorem local_iff_ordered (κ : bn.Kernel R) :
    (∀ m, Local κ m) ↔ ∃ t : o.CPT R, o.toKernel t = κ := by
  constructor
  · intro h
    exact ⟨o.ofKernel κ, o.toKernel_ofKernel κ h⟩
  · rintro ⟨t, rfl⟩
    exact o.toKernel_local t

/-- Transport new-order tuples into the old order through their common parent-indexed view. -/
def reindexValues (o' : ParentOrder bn) (m : bn.M) : o'.Values m ≃ o.Values m :=
  (o'.valuesEquiv m).trans (o.valuesEquiv m).symm

theorem reindexValues_gather (o' : ParentOrder bn) (m : bn.M) (x : bn.Assignment) :
    o.reindexValues o' m (o'.gather m x) = o.gather m x := by
  change (o.valuesEquiv m).symm (o'.valuesEquiv m (o'.gather m x)) = _
  rw [valuesEquiv_gather]
  rfl

/-- Permute the CPT's parent axes along with their declared order, leaving the child axis last. -/
def reindexCPT (o' : ParentOrder bn) (t : o.CPT R) : o'.CPT R :=
  fun m z => t m (o.reindexValues o' m z)

/-- **Ordered-parent fidelity:** coherent reindexing of parent positions and CPT axes preserves
every kernel entry, and hence every joint, marginal and intervention computed from the kernel. -/
theorem toKernel_reindex (o' : ParentOrder bn) (t : o.CPT R) :
    o'.toKernel (o.reindexCPT o' t) = o.toKernel t := by
  funext m x
  change t m (o.reindexValues o' m (o'.gather m x)) = t m (o.gather m x)
  rw [reindexValues_gather]

theorem toKernel_normalised [CommSemiring R] (t : o.CPT R)
    (ht : ∀ m z, ∑ a, t m z a = 1) : ∀ m, Normalised (o.toKernel t) m :=
  fun m x => ht m (o.gather m x)

/-- **Proposition 1 for genuinely ordered CPTs.** Normalising the child-last axis produces a
normalised joint on a closed acyclic network, independently of the chosen parent ordering. -/
theorem sum_joint_ordered [CommSemiring R] (t : o.CPT R) (hclosed : bn.Closed)
    (ord : bn.TopoOrder) (ht : ∀ m z, ∑ a, t m z a = 1) :
    ∑ x, joint (o.toKernel t) x = 1 :=
  sum_joint_eq_one _ hclosed ord (o.toKernel_local t) (o.toKernel_normalised t ht)

end ParentOrder

end BayesianNetworksProofs.FinBayesNet
