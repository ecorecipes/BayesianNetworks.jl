import BayesianNetworksProofs.Finite.Evaluation
import Mathlib.Data.Real.Basic

/-!
# Partial assignments and explicit conditioning

Restriction and patching connect concrete tuples of retained/free variables with the existing
full-assignment fibre semantics. Sums over `PartialAssignment S` enumerate only the coordinates
in S. Explicitly fixing evidence and multiplying by its indicator give the same finite sum.
-/

set_option autoImplicit false

namespace BayesianNetworksProofs.FinBayesNet

variable {bn : FinBayesNet}

abbrev PartialAssignment (bn : FinBayesNet) (S : Finset bn.V) :=
  (v : {v : bn.V // v ∈ S}) → bn.states v.val

def restrictTo (S : Finset bn.V) (x : bn.Assignment) : PartialAssignment bn S :=
  fun v => x v.val

def patch (S : Finset bn.V) (base : bn.Assignment) (x : PartialAssignment bn S) : bn.Assignment :=
  fun v => if hv : v ∈ S then x ⟨v, hv⟩ else base v

theorem restrict_patch (S : Finset bn.V) (base : bn.Assignment) (x : PartialAssignment bn S) :
    restrictTo S (patch S base x) = x := by
  funext v
  simp [restrictTo, patch, v.property]

theorem patch_mem_fibre (S : Finset bn.V) (base : bn.Assignment) (x : PartialAssignment bn S) :
    patch S base x ∈ fibre S base := by
  apply mem_fibre.2
  intro v hv
  simp [patch, hv]

theorem patch_restrict_of_mem {S : Finset bn.V} {base x : bn.Assignment}
    (h : x ∈ fibre S base) : patch S base (restrictTo S x) = x := by
  funext v
  by_cases hv : v ∈ S
  · simp [patch, restrictTo, hv]
  · simp [patch, hv, mem_fibre.1 h v hv]

/-- A finite sum over only the free coordinates equals the existing full-assignment marginal. -/
theorem sum_partial_eq_marg {R : Type} [CommSemiring R] (S : Finset bn.V)
    (F : bn.Assignment → R) (base : bn.Assignment) :
    (∑ x : PartialAssignment bn S, F (patch S base x)) = marg S F base := by
  unfold marg
  refine Finset.sum_bij (fun x _ => patch S base x) ?_ ?_ ?_ ?_
  · intro x _
    exact patch_mem_fibre S base x
  · intro x _ y _ h
    have he := congrArg (restrictTo S) h
    simpa only [restrict_patch] using he
  · intro x hx
    exact ⟨restrictTo S x, Finset.mem_univ _, patch_restrict_of_mem hx⟩
  · intro x _
    rfl

def clamp (E : Finset bn.V) (observed x : bn.Assignment) : bn.Assignment :=
  fun v => if v ∈ E then observed v else x v

abbrev agrees (E : Finset bn.V) (observed x : bn.Assignment) : Prop :=
  ∀ v ∈ E, x v = observed v

def indicator (E : Finset bn.V) (observed x : bn.Assignment) : ℝ :=
  if agrees E observed x then 1 else 0

theorem clamp_agrees (E : Finset bn.V) (observed x : bn.Assignment) :
    agrees E observed (clamp E observed x) := by
  intro v hv
  simp [clamp, hv]

theorem clamp_patch {E S : Finset bn.V} (h : Disjoint E S)
    (observed base : bn.Assignment) (x : PartialAssignment bn S) :
    clamp E observed (patch S base x) = patch S (clamp E observed base) x := by
  funext v
  by_cases hv : v ∈ S
  · have he : v ∉ E := fun he => Finset.disjoint_left.1 h he hv
    simp [clamp, patch, hv, he]
  · simp [clamp, patch, hv]

theorem marg_clamp {E S : Finset bn.V} (h : Disjoint E S)
    (F : bn.Assignment → ℝ) (observed base : bn.Assignment) :
    marg S (fun x => F (clamp E observed x)) base = marg S F (clamp E observed base) := by
  rw [← sum_partial_eq_marg, ← sum_partial_eq_marg]
  exact Finset.sum_congr rfl fun x _ => congrArg F (clamp_patch h observed base x)

theorem fibre_condition {E S : Finset bn.V} (h : Disjoint E S)
    (observed base : bn.Assignment) :
    (fibre (S ∪ E) base).filter (agrees E observed) = fibre S (clamp E observed base) := by
  ext x
  simp only [Finset.mem_filter, mem_fibre]
  constructor
  · rintro ⟨hf, he⟩ v hv
    by_cases hvE : v ∈ E
    · simpa [clamp, hvE] using he v hvE
    · simpa [clamp, hvE] using hf v (by simp [hv, hvE])
  · intro hf
    constructor
    · intro v hv
      have hs : v ∉ S := fun hs => hv (Finset.mem_union_left _ hs)
      have he : v ∉ E := fun he => hv (Finset.mem_union_right _ he)
      simpa [clamp, he] using hf v hs
    · intro v hv
      have hs : v ∉ S := fun hs => Finset.disjoint_left.1 h hv hs
      simpa [clamp, hv] using hf v hs

/-- Explicit conditioning versus an indicator factor. The summed coordinate sets are disjoint;
no normalization or positive-mass assumption is needed for this unnormalized identity. -/
theorem marg_indicator_eq_clamp {E S : Finset bn.V} (h : Disjoint E S)
    (F : bn.Assignment → ℝ) (observed base : bn.Assignment) :
    marg (S ∪ E) (fun x => F x * indicator E observed x) base =
      marg S (fun x => F (clamp E observed x)) base := by
  rw [marg_clamp h]
  unfold marg
  rw [← fibre_condition h observed base, Finset.sum_filter]
  apply Finset.sum_congr rfl
  intro x _
  simp [indicator, mul_ite]

/-- Full evidence-conditioned enumeration needs only the unobserved coordinates. -/
theorem sum_conditioned_eq_indicator (E : Finset bn.V) (F : bn.Assignment → ℝ)
    (observed : bn.Assignment) :
    (∑ x : PartialAssignment bn Eᶜ, F (patch Eᶜ observed x)) =
      ∑ x, F x * indicator E observed x := by
  rw [sum_partial_eq_marg]
  have h := marg_indicator_eq_clamp (S := Eᶜ) (E := E)
    (Finset.disjoint_left.2 fun _ he hc => Finset.mem_compl.1 hc he) F observed observed
  have he : clamp E observed observed = observed := by funext v; simp [clamp]
  have hs : Eᶜ ∪ E = Finset.univ := by
    ext v
    by_cases hv : v ∈ E <;> simp [hv]
  rw [hs, marg_univ, marg_clamp
    (Finset.disjoint_left.2 fun _ he hc => Finset.mem_compl.1 hc he), he] at h
  exact h.symm

end BayesianNetworksProofs.FinBayesNet
