import BayesianNetworksProofs.Finite.Assignments
import BayesianNetworksProofs.Finite.VariableElimination
import Mathlib.Algebra.Order.BigOperators.GroupWithZero.Finset
import Mathlib.Algebra.Order.BigOperators.Group.Finset
import Mathlib.Data.Fintype.BigOperators

/-!
# Finite posterior distributions and exact feasibility

Normalization returns a probability distribution only at positive mass. With nonnegative
weights, zero mass is exactly the absence of a positive-weight assignment. Query distributions
live on partial assignments, so eliminated coordinates are not counted repeatedly.

The VE theorem uses the existing bucket algorithm and joint semantics. Explicit conditioning
is modeled by clamping evidence coordinates and dropping them from factor scopes; its finite
elimination result equals indicator-likelihood elimination on the original model.
-/

set_option autoImplicit false

namespace BayesianNetworksProofs

noncomputable section

namespace FiniteDistribution

variable {A B : Type} [Fintype A] [Fintype B] [DecidableEq B]

def mass (w : A → ℝ) : ℝ := ∑ a, w a

structure Distribution (A : Type) [Fintype A] where
  pmf : A → ℝ
  nonneg : ∀ a, 0 ≤ pmf a
  normalized : ∑ a, pmf a = 1

def normalize (w : A → ℝ) (hw : ∀ a, 0 ≤ w a) : Option (Distribution A) :=
  if h : 0 < mass w then some {
    pmf a := w a / mass w
    nonneg a := div_nonneg (hw a) h.le
    normalized := by
      simp only [div_eq_mul_inv]
      rw [← Finset.sum_mul]
      exact mul_inv_cancel₀ (ne_of_gt h)
  } else none

theorem mass_nonneg (w : A → ℝ) (hw : ∀ a, 0 ≤ w a) : 0 ≤ mass w :=
  Finset.sum_nonneg fun a _ => hw a

theorem mass_zero_iff (w : A → ℝ) (hw : ∀ a, 0 ≤ w a) :
    mass w = 0 ↔ ∀ a, w a = 0 := by
  simpa [mass] using Finset.sum_eq_zero_iff_of_nonneg (s := Finset.univ) (fun a _ => hw a)

theorem mass_pos_iff (w : A → ℝ) (hw : ∀ a, 0 ≤ w a) :
    0 < mass w ↔ ∃ a, 0 < w a := by
  simpa [mass] using Finset.sum_pos_iff_of_nonneg (s := Finset.univ) (fun a _ => hw a)

theorem normalize_none_iff (w : A → ℝ) (hw : ∀ a, 0 ≤ w a) :
    normalize w hw = none ↔ mass w = 0 := by
  unfold normalize
  by_cases hp : 0 < mass w
  · simp [hp, ne_of_gt hp]
  · have hz := le_antisymm (le_of_not_gt hp) (mass_nonneg w hw)
    simp [hz]

theorem normalize_value (w : A → ℝ) (hw : ∀ a, 0 ≤ w a) (d : Distribution A)
    (h : normalize w hw = some d) : ∀ a, d.pmf a = w a / mass w := by
  unfold normalize at h
  split_ifs at h with hp
  · cases Option.some.inj h
    exact fun _ => rfl

def pushWeight (f : A → B) (w : A → ℝ) (b : B) : ℝ :=
  ∑ a, if f a = b then w a else 0

omit [Fintype B] in
theorem pushWeight_nonneg (f : A → B) (w : A → ℝ) (hw : ∀ a, 0 ≤ w a) :
    ∀ b, 0 ≤ pushWeight f w b := by
  intro b
  apply Finset.sum_nonneg
  intro a _
  split_ifs
  · exact hw a
  · exact le_refl 0

theorem mass_pushWeight (f : A → B) (w : A → ℝ) :
    mass (pushWeight f w) = mass w := by
  unfold mass pushWeight
  rw [Finset.sum_comm]
  apply Finset.sum_congr rfl
  intro a _
  simp

end FiniteDistribution

namespace FinBayesNet

open FiniteDistribution

variable {bn : FinBayesNet}

def likelihoodWeight (p : bn.Assignment → ℝ) (E : Finset bn.V) (observed x : bn.Assignment) : ℝ :=
  p x * indicator E observed x

theorem likelihoodWeight_nonneg (p : bn.Assignment → ℝ) (hp : ∀ x, 0 ≤ p x)
    (E : Finset bn.V) (observed : bn.Assignment) : ∀ x, 0 ≤ likelihoodWeight p E observed x := by
  intro x
  unfold likelihoodWeight indicator
  split_ifs <;> simp_all

def posterior (Q E : Finset bn.V) (observed : bn.Assignment)
    (p : bn.Assignment → ℝ) (hp : ∀ x, 0 ≤ p x) :
    Option (Distribution (PartialAssignment bn Q)) :=
  normalize (pushWeight (restrictTo Q) (likelihoodWeight p E observed))
    (pushWeight_nonneg _ _ (likelihoodWeight_nonneg p hp E observed))

/-- Impossible evidence is rejected even for an empty query or a query consisting entirely
of observed variables; feasibility concerns the whole joint, not just the requested component. -/
theorem posterior_none_iff (Q E : Finset bn.V) (observed : bn.Assignment)
    (p : bn.Assignment → ℝ) (hp : ∀ x, 0 ≤ p x) :
    posterior Q E observed p hp = none ↔ ¬∃ x, agrees E observed x ∧ 0 < p x := by
  rw [posterior, normalize_none_iff, mass_pushWeight]
  have hmass := mass_nonneg _ (likelihoodWeight_nonneg p hp E observed)
  have hz : mass (likelihoodWeight p E observed) = 0 ↔
      ¬0 < mass (likelihoodWeight p E observed) :=
    ⟨fun he => by rw [he]; simp, fun he => le_antisymm (le_of_not_gt he) hmass⟩
  rw [hz, mass_pos_iff _ (likelihoodWeight_nonneg p hp E observed)]
  apply not_congr
  constructor
  · rintro ⟨x, hx⟩
    by_cases he : agrees E observed x
    · have hi : indicator E observed x = 1 := if_pos he
      exact ⟨x, he, by simpa only [likelihoodWeight, hi, mul_one] using hx⟩
    · have hi : indicator E observed x = 0 := if_neg he
      simp only [likelihoodWeight, hi, mul_zero, lt_self_iff_false] at hx
  · rintro ⟨x, he, hp⟩
    have hi : indicator E observed x = 1 := if_pos he
    exact ⟨x, by simpa only [likelihoodWeight, hi, mul_one] using hp⟩

theorem fibre_query (Q : Finset bn.V) (x : bn.Assignment) :
    fibre Qᶜ x = Finset.univ.filter (fun y => restrictTo Q y = restrictTo Q x) := by
  ext y
  simp only [mem_fibre, Finset.mem_filter, Finset.mem_univ, true_and]
  constructor
  · intro h
    funext v
    exact h v.val (by simp)
  · intro h v hv
    exact congrFun h ⟨v, by simpa using hv⟩

theorem marginal_eq_query_weight (Q : Finset bn.V) (p : bn.Assignment → ℝ) (x : bn.Assignment) :
    marg Qᶜ p x = pushWeight (restrictTo Q) p (restrictTo Q x) := by
  rw [marg, fibre_query, Finset.sum_filter]
  rfl

def evidenceFactor (E : Finset bn.V) (observed : bn.Assignment) : Factor bn ℝ where
  scope := E
  value := indicator E observed
  dependsOn x y h := by
    have he : agrees E observed x ↔ agrees E observed y := by
      constructor
      · intro hx v hv
        rw [← h v hv]
        exact hx v hv
      · intro hy v hv
        rw [h v hv]
        exact hy v hv
    simp only [indicator, he]

theorem joint_nonneg (κ : bn.Kernel ℝ) (hκ : ∀ m x a, 0 ≤ κ m x a) (x : bn.Assignment) :
    0 ≤ joint κ x := Finset.prod_nonneg fun m _ => hκ m x _

/-- The already-defined VE driver, with a real evidence indicator factor, computes the
unnormalized numerator of the genuine query posterior. -/
theorem ve_posterior_numerator (κ : bn.Kernel ℝ) (hloc : ∀ m, Local κ m)
    (Q E : Finset bn.V) (observed : bn.Assignment) (vs : List bn.V)
    (hvs : vs.Nodup) (hset : vs.toFinset = Qᶜ) (x : bn.Assignment) :
    Factor.product (Factor.eliminateAll (evidenceFactor E observed :: Factor.ofKernel κ hloc) vs) x =
      pushWeight (restrictTo Q) (likelihoodWeight (joint κ) E observed) (restrictTo Q x) := by
  rw [Factor.eliminateAll_correct _ vs hvs, hset]
  have he : Factor.product (evidenceFactor E observed :: Factor.ofKernel κ hloc) =
      likelihoodWeight (joint κ) E observed := by
    funext y
    rw [Factor.product_cons, Factor.product_ofKernel]
    exact mul_comm _ _
  rw [he, marginal_eq_query_weight]

/-- Dividing the actual VE numerator by positive evidence mass gives the normalized posterior
entry. A returned Distribution supplies nonnegativity and total mass one. -/
theorem ve_normalized_posterior (κ : bn.Kernel ℝ) (hloc : ∀ m, Local κ m)
    (hκ : ∀ m x a, 0 ≤ κ m x a) (Q E : Finset bn.V) (observed : bn.Assignment)
    (vs : List bn.V) (hvs : vs.Nodup) (hset : vs.toFinset = Qᶜ)
    (d : Distribution (PartialAssignment bn Q))
    (hd : posterior Q E observed (joint κ) (joint_nonneg κ hκ) = some d) (x : bn.Assignment) :
    Factor.product (Factor.eliminateAll (evidenceFactor E observed :: Factor.ofKernel κ hloc) vs) x /
        mass (likelihoodWeight (joint κ) E observed) = d.pmf (restrictTo Q x) := by
  rw [ve_posterior_numerator κ hloc Q E observed vs hvs hset]
  have h := normalize_value _ _ d hd (restrictTo Q x)
  rw [mass_pushWeight] at h
  exact h.symm

namespace Factor

def condition (E : Finset bn.V) (observed : bn.Assignment) (f : Factor bn ℝ) : Factor bn ℝ where
  scope := f.scope \ E
  value x := f.value (clamp E observed x)
  dependsOn x y h := by
    apply f.dependsOn
    intro v hv
    by_cases he : v ∈ E
    · simp [clamp, he]
    · simpa [clamp, he] using h v (Finset.mem_sdiff.2 ⟨hv, he⟩)

theorem product_condition (fs : List (Factor bn ℝ)) (E : Finset bn.V) (observed : bn.Assignment) :
    product (fs.map (condition E observed)) = fun x => product fs (clamp E observed x) := by
  funext x
  simp [product, condition, List.map_map, Function.comp_def]

theorem explicit_conditioning_elimination (fs : List (Factor bn ℝ)) (E : Finset bn.V)
    (observed : bn.Assignment) (vs : List bn.V) (hvs : vs.Nodup) (hd : Disjoint E vs.toFinset)
    (x : bn.Assignment) :
    product (eliminateAll (fs.map (condition E observed)) vs) x =
      marg (vs.toFinset ∪ E) (fun y => product fs y * indicator E observed y) x := by
  rw [eliminateAll_correct _ vs hvs, product_condition]
  exact (marg_indicator_eq_clamp hd (product fs) observed x).symm

end Factor
end FinBayesNet
end
end BayesianNetworksProofs
