import BayesianNetworksProofs.Finite.Posterior
import Mathlib.Algebra.BigOperators.Field
import Mathlib.Tactic.FieldSimp
import Mathlib.Tactic.Linarith
import Mathlib.Tactic.Ring

/-!
# Conditional numerical error contracts

These are quantitative hypotheses and conclusions, not a universal Float64/oracle identity.
Finite product perturbations are bounded from entry errors. Normalization has an explicit
positive-mass lower bound; small evidence mass amplifies error. A separate rounded-product
model assumes local multiplication-error and range-preservation contracts and derives a
whole-product bound. No IEEE implementation of those local contracts is assumed proved here.
-/

set_option autoImplicit false

namespace BayesianNetworksProofs.Numerical

open FiniteDistribution
noncomputable section

variable {A : Type} [Fintype A]

def l1 (p q : A → ℝ) : ℝ := ∑ a, |p a - q a|

theorem l1_nonneg (p q : A → ℝ) : 0 ≤ l1 p q := Finset.sum_nonneg fun _ _ => abs_nonneg _

theorem mass_error (p q : A → ℝ) : |mass p - mass q| ≤ l1 p q := by
  rw [mass, mass, ← Finset.sum_sub_distrib]
  exact Finset.abs_sum_le_sum_abs _ _

theorem point_normalization_error (p q Z W : ℝ) (hq : 0 ≤ q) (hZ : 0 < Z) (hW : 0 < W) :
    |p / Z - q / W| ≤ |p - q| / Z + (q / W) * |W - Z| / Z := by
  have he : p / Z - q / W = (p - q) / Z + (q / W) * (W - Z) / Z := by
    field_simp
    ring
  rw [he]
  calc
    _ ≤ |(p - q) / Z| + |(q / W) * (W - Z) / Z| := abs_add_le _ _
    _ = _ := by
      rw [abs_div, abs_of_pos hZ, abs_div, abs_of_pos hZ, abs_mul,
        abs_of_nonneg (div_nonneg hq hW.le)]

/-- Exact normalization is L1-stable only relative to its mass. The comparison weight is
nonnegative and both masses are positive; no entrywise lower bound is required. -/
theorem normalization_l1 (p q : A → ℝ) (hq : ∀ a, 0 ≤ q a)
    (hZ : 0 < mass p) (hW : 0 < mass q) :
    l1 (fun a => p a / mass p) (fun a => q a / mass q) ≤ 2 * l1 p q / mass p := by
  have hmass : |mass q - mass p| ≤ l1 p q := by simpa only [abs_sub_comm] using mass_error p q
  have hsum : ∑ a, q a / mass q = 1 := by
    rw [← Finset.sum_div]
    exact div_self (ne_of_gt hW)
  calc
    _ ≤ ∑ a, (|p a - q a| / mass p + (q a / mass q) * |mass q - mass p| / mass p) :=
      Finset.sum_le_sum fun a _ => point_normalization_error _ _ _ _ (hq a) hZ hW
    _ = (l1 p q + |mass q - mass p|) / mass p := by
      rw [Finset.sum_add_distrib, ← Finset.sum_div, ← Finset.sum_div, ← Finset.sum_mul, hsum]
      simp [l1, add_div]
    _ ≤ (l1 p q + l1 p q) / mass p :=
      div_le_div_of_nonneg_right (add_le_add (le_refl _) hmass) hZ.le
    _ = _ := by ring

/-- A supplied absolute input error below a genuine evidence-mass floor guarantees positive
approximate mass and bounds posterior L1 error. This is not meaningful with η=0. -/
theorem posterior_error (p q : A → ℝ) (hq : ∀ a, 0 ≤ q a)
    (η ε : ℝ) (hη : 0 < η) (hfloor : η ≤ mass p)
    (herr : l1 p q ≤ ε) (hsmall : ε < η) :
    0 < mass q ∧ l1 (fun a => p a / mass p) (fun a => q a / mass q) ≤ 2 * ε / η := by
  have hZ : 0 < mass p := hη.trans_le hfloor
  have hm := (le_abs_self (mass p - mass q)).trans ((mass_error p q).trans herr)
  have hW : 0 < mass q := by linarith
  have hε : 0 ≤ ε := (l1_nonneg p q).trans herr
  refine ⟨hW, (normalization_l1 p q hq hZ hW).trans ?_⟩
  calc
    _ ≤ 2 * ε / mass p := div_le_div_of_nonneg_right
      (mul_le_mul_of_nonneg_left herr (by norm_num)) hZ.le
    _ ≤ _ := div_le_div_of_nonneg_left (mul_nonneg (by norm_num) hε) hη hfloor

theorem prod_unit_interval {I : Type} (S : Finset I) (p : I → ℝ)
    (hp : ∀ i ∈ S, 0 ≤ p i ∧ p i ≤ 1) : 0 ≤ ∏ i ∈ S, p i ∧ (∏ i ∈ S, p i) ≤ 1 := by
  classical
  induction S using Finset.induction_on with
  | empty => simp
  | @insert i S hi ih =>
    have hpI := hp i (Finset.mem_insert_self _ _)
    have hpS := ih (fun j hj => hp j (Finset.mem_insert_of_mem hj))
    rw [Finset.prod_insert hi]
    exact ⟨mul_nonneg hpI.1 hpS.1,
      (mul_le_mul hpI.2 hpS.2 hpS.1 zero_le_one).trans (by simp)⟩

theorem product_error {I : Type} (S : Finset I) (p q : I → ℝ)
    (hp : ∀ i ∈ S, 0 ≤ p i ∧ p i ≤ 1) (hq : ∀ i ∈ S, 0 ≤ q i ∧ q i ≤ 1) :
    |(∏ i ∈ S, p i) - ∏ i ∈ S, q i| ≤ ∑ i ∈ S, |p i - q i| := by
  classical
  induction S using Finset.induction_on with
  | empty => simp
  | @insert i S hi ih =>
    have pI := hp i (Finset.mem_insert_self _ _)
    have qI := hq i (Finset.mem_insert_self _ _)
    have hpS := fun j hj => hp j (Finset.mem_insert_of_mem hj)
    have hqS := fun j hj => hq j (Finset.mem_insert_of_mem hj)
    have pS := prod_unit_interval S p hpS
    rw [Finset.prod_insert hi, Finset.prod_insert hi, Finset.sum_insert hi]
    have he : p i * (∏ j ∈ S, p j) - q i * (∏ j ∈ S, q j) =
        (p i - q i) * (∏ j ∈ S, p j) + q i * ((∏ j ∈ S, p j) - ∏ j ∈ S, q j) := by ring
    rw [he]
    calc
      _ ≤ |(p i - q i) * (∏ j ∈ S, p j)| + |q i * ((∏ j ∈ S, p j) - ∏ j ∈ S, q j)| :=
        abs_add_le _ _
      _ = |p i - q i| * (∏ j ∈ S, p j) + q i * |(∏ j ∈ S, p j) - ∏ j ∈ S, q j| := by
        rw [abs_mul, abs_mul, abs_of_nonneg pS.1, abs_of_nonneg qI.1]
      _ ≤ |p i - q i| + |(∏ j ∈ S, p j) - ∏ j ∈ S, q j| := by
        apply add_le_add
        · simpa using mul_le_mul_of_nonneg_left pS.2 (abs_nonneg (p i - q i))
        · simpa using mul_le_mul_of_nonneg_right qI.2
            (abs_nonneg ((∏ j ∈ S, p j) - ∏ j ∈ S, q j))
      _ ≤ _ := add_le_add (le_refl _) (ih hpS hqS)

def roundedProduct (mulR : ℝ → ℝ → ℝ) : List ℝ → ℝ
  | [] => 1
  | x :: xs => mulR x (roundedProduct mulR xs)

def UnitInterval (x : ℝ) : Prop := 0 ≤ x ∧ x ≤ 1

theorem roundedProduct_range (mulR : ℝ → ℝ → ℝ)
    (hclosed : ∀ x y, UnitInterval x → UnitInterval y → UnitInterval (mulR x y))
    (xs : List ℝ) (hxs : ∀ x ∈ xs, UnitInterval x) : UnitInterval (roundedProduct mulR xs) := by
  induction xs with
  | nil => exact ⟨zero_le_one, le_rfl⟩
  | cons x xs ih =>
    exact hclosed x _ (hxs x (List.mem_cons_self ..))
      (ih (fun y hy => hxs y (List.mem_cons_of_mem x hy)))

/-- An actual recursively rounded product has a linear absolute error bound, derived from
local multiplication contracts. IEEE arithmetic is not identified with mulR without proof. -/
theorem roundedProduct_error (mulR : ℝ → ℝ → ℝ) (δ : ℝ)
    (hclosed : ∀ x y, UnitInterval x → UnitInterval y → UnitInterval (mulR x y))
    (hround : ∀ x y, UnitInterval x → UnitInterval y → |mulR x y - x * y| ≤ δ)
    (xs : List ℝ) (hxs : ∀ x ∈ xs, UnitInterval x) :
    |roundedProduct mulR xs - xs.prod| ≤ xs.length * δ := by
  induction xs with
  | nil => simp [roundedProduct]
  | cons x xs ih =>
    have hx := hxs x (List.mem_cons_self ..)
    have ht := fun y hy => hxs y (List.mem_cons_of_mem x hy)
    have hrange := roundedProduct_range mulR hclosed xs ht
    change |mulR x (roundedProduct mulR xs) - x * xs.prod| ≤ (xs.length + 1 : Nat) * δ
    calc
      _ ≤ |mulR x (roundedProduct mulR xs) - x * roundedProduct mulR xs| +
          |x * roundedProduct mulR xs - x * xs.prod| := abs_sub_le _ _ _
      _ ≤ δ + |roundedProduct mulR xs - xs.prod| := by
        apply add_le_add (hround x _ hx hrange)
        rw [← mul_sub, abs_mul, abs_of_nonneg hx.1]
        simpa using mul_le_mul_of_nonneg_right hx.2 (abs_nonneg (roundedProduct mulR xs - xs.prod))
      _ ≤ δ + xs.length * δ := add_le_add (le_refl _) (ih ht)
      _ = _ := by push_cast; ring

theorem push_l1 {B : Type} [Fintype B] [DecidableEq B] (f : A → B) (p q : A → ℝ) :
    l1 (pushWeight f p) (pushWeight f q) ≤ l1 p q := by
  have he : ∀ b, pushWeight f p b - pushWeight f q b =
      ∑ a, if f a = b then p a - q a else 0 := by
    intro b
    unfold pushWeight
    rw [← Finset.sum_sub_distrib]
    apply Finset.sum_congr rfl
    intro a _
    split_ifs <;> simp
  unfold l1
  simp_rw [he]
  calc
    _ ≤ ∑ b, ∑ a, |if f a = b then p a - q a else 0| :=
      Finset.sum_le_sum fun b _ => Finset.abs_sum_le_sum_abs _ _
    _ = _ := by
      rw [Finset.sum_comm]
      apply Finset.sum_congr rfl
      intro a _
      change (∑ b : B, |if f a = b then p a - q a else 0|) = |p a - q a|
      simp [apply_ite]

open FinBayesNet

theorem evidence_l1 {bn : FinBayesNet} (p q : bn.Assignment → ℝ)
    (E : Finset bn.V) (observed : bn.Assignment) :
    l1 (likelihoodWeight p E observed) (likelihoodWeight q E observed) ≤ l1 p q := by
  apply Finset.sum_le_sum
  intro x _
  by_cases he : agrees E observed x
  · have hi : indicator E observed x = 1 := if_pos he
    simp only [likelihoodWeight, hi, mul_one, le_refl]
  · have hi : indicator E observed x = 0 := if_neg he
    simp only [likelihoodWeight, hi, mul_zero, sub_self, abs_zero]
    exact abs_nonneg _

/-- Entrywise CPT perturbations imply a joint-weight L1 budget. This is an explicit
worst-case finite bound, not an assertion about machine arithmetic. -/
theorem joint_l1_error {bn : FinBayesNet} (κ κ' : bn.Kernel ℝ)
    (hκ : ∀ m x a, 0 ≤ κ m x a ∧ κ m x a ≤ 1)
    (hκ' : ∀ m x a, 0 ≤ κ' m x a ∧ κ' m x a ≤ 1)
    (ε : bn.M → ℝ) (herr : ∀ m x a, |κ m x a - κ' m x a| ≤ ε m) :
    l1 (joint κ) (joint κ') ≤ (Fintype.card bn.Assignment : ℝ) * ∑ m, ε m := by
  calc
    _ ≤ ∑ _x : bn.Assignment, ∑ m, ε m := by
      apply Finset.sum_le_sum
      intro x _
      exact (product_error Finset.univ (fun m => κ m x (x (bn.target m)))
        (fun m => κ' m x (x (bn.target m))) (fun m _ => hκ m x _) (fun m _ => hκ' m x _)).trans
        (Finset.sum_le_sum fun m _ => herr m x _)
    _ = _ := by simp

/-- A complete query-posterior input-perturbation contract. The exact VE/JT results inherit
this bound through their separately proved equality to the joint/query semantics. -/
theorem kernel_query_posterior_error {bn : FinBayesNet} (κ κ' : bn.Kernel ℝ)
    (hκ : ∀ m x a, 0 ≤ κ m x a ∧ κ m x a ≤ 1)
    (hκ' : ∀ m x a, 0 ≤ κ' m x a ∧ κ' m x a ≤ 1)
    (ε : bn.M → ℝ) (herr : ∀ m x a, |κ m x a - κ' m x a| ≤ ε m)
    (Q E : Finset bn.V) (observed : bn.Assignment) (η : ℝ) (hη : 0 < η)
    (hfloor : η ≤ mass (likelihoodWeight (joint κ) E observed))
    (hsmall : (Fintype.card bn.Assignment : ℝ) * (∑ m, ε m) < η) :
    0 < mass (likelihoodWeight (joint κ') E observed) ∧
      l1
        (fun q => pushWeight (restrictTo Q) (likelihoodWeight (joint κ) E observed) q /
          mass (likelihoodWeight (joint κ) E observed))
        (fun q => pushWeight (restrictTo Q) (likelihoodWeight (joint κ') E observed) q /
          mass (likelihoodWeight (joint κ') E observed)) ≤
        2 * ((Fintype.card bn.Assignment : ℝ) * ∑ m, ε m) / η := by
  have hnonneg := likelihoodWeight_nonneg (joint κ') (joint_nonneg κ' (fun m x a => (hκ' m x a).1)) E observed
  have herror := (push_l1 (restrictTo Q) (likelihoodWeight (joint κ) E observed)
    (likelihoodWeight (joint κ') E observed)).trans
    ((evidence_l1 (joint κ) (joint κ') E observed).trans (joint_l1_error κ κ' hκ hκ' ε herr))
  have h := posterior_error _ _ (pushWeight_nonneg _ _ hnonneg) η _ hη
    (by simpa only [mass_pushWeight] using hfloor) herror hsmall
  simpa only [mass_pushWeight] using h

end
end BayesianNetworksProofs.Numerical
