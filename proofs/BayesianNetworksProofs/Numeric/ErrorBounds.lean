import BayesianNetworksProofs.Numeric.Binary64
import BayesianNetworksProofs.Finite.Posterior
import Mathlib.Algebra.Order.BigOperators.GroupWithZero.List
import Mathlib.Data.Nat.Lattice
import Mathlib.Analysis.SpecialFunctions.Log.Basic

/-!
# Forward error bounds for the floating-point paths

The inference engines compute in Float64. `Numeric/Binary64.lean` proves that the exact
fallback's final rounding is correct; this module bounds the error of the ordinary
floating-point paths, as theorems about an abstract rounding model applied to the factor
algebra of `Finite/VariableElimination.lean` and `Finite/Posterior.lean`.

**The standard model.** `Rounded u x c` says that `c` is a computed result of an operation
whose exact result is `x`: `c = x * (1 + δ)` with `|δ| ≤ u`. For binary64, `u = 2 ^ -53`
(`binary64Unit`). `γ n = (1 + u) ^ n - 1` (`gamma`) bounds the relative error of `n` roundings,
and `RelWithin e y x` (`|x - y| ≤ e * y`) is relative error against a nonnegative exact value.
Relative errors of nonnegative quantities compose without any cancellation argument:
`RelWithin.mul`, `RelWithin.add` and `RelWithin.round`.

**The bridge to binary64** (`roundsTo_relative`, `roundsTo_subnormal`, `roundsTo_rounded`, and
`nearestBinary64_relative`, `nearestBinary64_subnormal`, `nearestBinary64_rounded` for the
transcription of `_nearest_binary64`). A word `w` with `RoundsTo q w` (IEEE 754
round-to-nearest, ties-to-even, of the rational `q`) satisfies `|value w - q| ≤ 2 ^ -53 |q|`
when `2 ^ -1022 ≤ |q| < overflowThreshold`, and `|value w - q| ≤ 2 ^ -1075` when
`|q| < 2 ^ -1022`. The relative bound is derived from `RoundsTo.nearest` by exhibiting a finite
word within `2 ^ -53 |q|` of `q`. So `Rounded binary64Unit` holds for correct rounding of an
exact result that is zero or in the normal range. That Julia's Float64 `+`, `*`, `-` and `/`
deliver the correctly rounded result of their exact real operation is IEEE 754 together with
Julia's and the hardware's semantics: it is **assumed, not proved**. Julia's `exp` and `log`
are not correctly rounded; the log-sum-exp theorem takes their relative error `u` as a
hypothesis.

**What is proved.**

* `compProd_forward_error`: a product of `k` nonnegative numbers computed in any order and
  association is within relative `γ (k - 1)` of the exact product.
* `sumRun_forward_error`: a sum of `n` nonnegative numbers computed along any association tree
  `t` (`Assoc`, `SumRun`) is within relative `γ (height t)`, hence `γ (n - 1)`, of the exact
  sum. The tree is a universally quantified argument: the bound does not depend on the order.
* `eliminateAll_forward_error`: an approximate run of variable elimination (`Run`) pairs each
  exact factor of `eliminateAll` with a computed table. Each step computes every entry of the
  bucket's sum-out as a sum, in any association, over the states of `v` of products, in any
  association, of the bucket's computed tables, every operation rounded in the standard model.
  For nonnegative input factors `fs` and an elimination list `vs`, every entry of every computed
  factor, and of any computed product of the remaining factors, is within relative `γ N` of the
  exact entry, with the explicit index `N = veIndex fs.length vs = |fs| + Σ_{v ∈ vs} |states v| - 1`.
  `eliminateAll_marg_forward_error` restates it against `marg vs.toFinset (product fs)`, and
  `conditioned_forward_error` covers evidence by slicing (`condition`), the shape of the Julia
  engine.
* `normalize_forward_error` and `ve_posterior_forward_error`: with the evidence indicator and
  the compiled CPT factors, `vs = Qᶜ`, the mass `Z` summed in any association and each posterior
  entry the rounded quotient `num q / Z`, let `K = posteriorIndex bn Q vs =
  (|M| + 1) + Σ_{v ∈ vs} |states v| - 1 + |query assignments|`. When the evidence mass is
  positive and `γ K < 1`, the computed mass is within relative `γ (K - 1)` of the evidence mass
  and every computed posterior entry is within relative `(1 + γ K) / (1 - γ K) - 1` (about
  `2 K u`) of the exact posterior entry.
* `logSumExp_forward_error`: `m + log Σ exp (x i - m)`, with the subtraction, each `exp`, each
  addition, the `log` and the final addition rounded with relative error `u`, and the spread
  `m - x i ≤ D`, is within `u |exact| + (1 + u) (u (log n + λ) + λ)` of the exact value, where
  `λ = -log (1 - ((1 + u) ^ n exp (u D) - 1))`.

**Scope.** The model has no absolute term: the VE, posterior and log-sum-exp theorems assume
that every operation's result satisfies `Rounded u`, which for binary64 the bridge discharges
only when each exact intermediate result is zero or in the normal range. **Underflow and overflow
are excluded**; only the bridge's `roundsTo_subnormal` and `roundsTo_error` carry the absolute
term `2 ^ -1075`. The Julia engines do not rely on these theorems at small mass: an evidence mass
below `floatmin(Float64)` sends the query to the exact fallback (ADR 0014, ADR 0016), which
`Binary64.lean` covers. Intermediate products that underflow while the final mass stays above
`floatmin` are outside both. These are theorems about the factor algebra under an abstract
rounding model, with order and association universally quantified; they are not about Julia's
loop order, SIMD reassociation, array layout or execution, nor about the junction-tree,
belief-propagation or brute-force paths. The run starts from the CPT entries as given (the
Float64 inputs are the exact data), and the indices are worst-case bounds, not estimates.
-/

set_option autoImplicit false

namespace BayesianNetworksProofs.ErrorBounds

/-! ## The standard model of rounding -/

/-- The standard model with unit roundoff `u`: `c` is a computed result of an operation whose
exact result is `x` when `c = x * (1 + δ)` for some `|δ| ≤ u`. -/
def Rounded (u x c : ℝ) : Prop := ∃ δ : ℝ, |δ| ≤ u ∧ c = x * (1 + δ)

theorem rounded_iff {u : ℝ} (hu : 0 ≤ u) (x c : ℝ) : Rounded u x c ↔ |c - x| ≤ u * |x| := by
  constructor
  · rintro ⟨δ, hδ, rfl⟩
    rw [show x * (1 + δ) - x = x * δ by ring, abs_mul, mul_comm]
    exact mul_le_mul_of_nonneg_right hδ (abs_nonneg x)
  · intro h
    by_cases hx : x = 0
    · subst hx
      refine ⟨0, by simpa using hu, ?_⟩
      have : |c| ≤ 0 := by simpa using h
      simpa using abs_nonpos_iff.mp this
    · refine ⟨(c - x) / x, ?_, by field_simp; ring⟩
      rw [abs_div]
      exact (div_le_iff₀ (abs_pos.mpr hx)).mpr h

/-- An exact operation satisfies the model. -/
theorem rounded_exact {u : ℝ} (hu : 0 ≤ u) (x : ℝ) : Rounded u x x := ⟨0, by simpa using hu, by ring⟩

/-- `γ n = (1 + u) ^ n - 1`, the relative error bound after `n` roundings. -/
def gamma (u : ℝ) (n : ℕ) : ℝ := (1 + u) ^ n - 1

variable {u : ℝ}

theorem gamma_zero : gamma u 0 = 0 := by simp [gamma]

theorem one_add_gamma (n : ℕ) : 1 + gamma u n = (1 + u) ^ n := by simp [gamma]

theorem gamma_nonneg (hu : 0 ≤ u) (n : ℕ) : 0 ≤ gamma u n := by
  unfold gamma
  linarith [one_le_pow₀ (n := n) (show (1 : ℝ) ≤ 1 + u by linarith)]

theorem gamma_mono (hu : 0 ≤ u) {m n : ℕ} (h : m ≤ n) : gamma u m ≤ gamma u n := by
  unfold gamma
  linarith [pow_le_pow_right₀ (show (1 : ℝ) ≤ 1 + u by linarith) h]

theorem gamma_add (a b : ℕ) : (1 + gamma u a) * (1 + gamma u b) = 1 + gamma u (a + b) := by
  simp only [one_add_gamma, pow_add]

/-! ## Relative error of nonnegative quantities -/

/-- `x` approximates the exact value `y` to relative error `e`: `|x - y| ≤ e * y`. Used only for
`0 ≤ y`, where it says `x ∈ [(1 - e) y, (1 + e) y]`. -/
def RelWithin (e y x : ℝ) : Prop := |x - y| ≤ e * y

theorem relWithin_refl (y : ℝ) {e : ℝ} (he : 0 ≤ e) (hy : 0 ≤ y) : RelWithin e y y := by
  simp [RelWithin]; positivity

theorem RelWithin.mono {e e' y x : ℝ} (h : RelWithin e y x) (he : e ≤ e') (hy : 0 ≤ y) :
    RelWithin e' y x := h.trans (mul_le_mul_of_nonneg_right he hy)

theorem RelWithin.abs_le {e y x : ℝ} (h : RelWithin e y x) (hy : 0 ≤ y) : |x| ≤ (1 + e) * y := by
  have h' : |x - y| ≤ e * y := h
  calc |x| = |(x - y) + y| := by ring_nf
    _ ≤ |x - y| + |y| := abs_add_le _ _
    _ ≤ e * y + y := by rw [abs_of_nonneg hy]; linarith
    _ = _ := by ring

/-- Relative errors of a product of nonnegative exact values compose multiplicatively. -/
theorem RelWithin.mul {a b y y' x x' : ℝ} (h : RelWithin a y x) (h' : RelWithin b y' x')
    (ha : 0 ≤ a) (hy : 0 ≤ y) (hy' : 0 ≤ y') :
    RelWithin ((1 + a) * (1 + b) - 1) (y * y') (x * x') := by
  unfold RelWithin at *
  have he : x * x' - y * y' = (x - y) * (x' - y') + y * (x' - y') + y' * (x - y) := by ring
  rw [he]
  calc _ ≤ |(x - y) * (x' - y')| + |y * (x' - y')| + |y' * (x - y)| := abs_add_three _ _ _
    _ = |x - y| * |x' - y'| + y * |x' - y'| + y' * |x - y| := by
        rw [abs_mul, abs_mul, abs_mul, abs_of_nonneg hy, abs_of_nonneg hy']
    _ ≤ (a * y) * (b * y') + y * (b * y') + y' * (a * y) := by
        gcongr
    _ = _ := by ring

/-- Relative errors of a sum of nonnegative exact values do not grow beyond the larger. -/
theorem RelWithin.add {e y y' x x' : ℝ} (h : RelWithin e y x) (h' : RelWithin e y' x') :
    RelWithin e (y + y') (x + x') := by
  unfold RelWithin at *
  calc |x + x' - (y + y')| = |(x - y) + (x' - y')| := by ring_nf
    _ ≤ |x - y| + |x' - y'| := abs_add_le _ _
    _ ≤ e * y + e * y' := add_le_add h h'
    _ = _ := by ring

/-- One rounding in the standard model multiplies the error budget by `1 + u`. -/
theorem RelWithin.round {e y x c : ℝ} (h : RelWithin e y x) (hy : 0 ≤ y) (hu : 0 ≤ u)
    (hc : Rounded u x c) : RelWithin ((1 + u) * (1 + e) - 1) y c := by
  rw [rounded_iff hu] at hc
  have hx := h.abs_le hy
  unfold RelWithin at *
  calc |c - y| = |(c - x) + (x - y)| := by ring_nf
    _ ≤ |c - x| + |x - y| := abs_add_le _ _
    _ ≤ u * ((1 + e) * y) + e * y := add_le_add (hc.trans (mul_le_mul_of_nonneg_left hx hu)) h
    _ = _ := by ring

theorem RelWithin.mul_gamma (hu : 0 ≤ u) {a b : ℕ} {y y' x x' : ℝ}
    (h : RelWithin (gamma u a) y x) (h' : RelWithin (gamma u b) y' x')
    (hy : 0 ≤ y) (hy' : 0 ≤ y') : RelWithin (gamma u (a + b)) (y * y') (x * x') := by
  have := h.mul h' (gamma_nonneg hu a) hy hy'
  rwa [gamma_add, add_sub_cancel_left] at this

theorem RelWithin.round_gamma (hu : 0 ≤ u) {a : ℕ} {y x c : ℝ} (h : RelWithin (gamma u a) y x)
    (hy : 0 ≤ y) (hc : Rounded u x c) : RelWithin (gamma u (a + 1)) y c := by
  have := h.round hy hu hc
  rwa [show (1 + u) * (1 + gamma u a) - 1 = gamma u (a + 1) by
    rw [one_add_gamma]; unfold gamma; ring] at this

/-! ## Association trees -/

/-- A binary association: the shape of a computation that combines its leaves pairwise. Any
parenthesisation of a sum or product of `n ≥ 1` terms is such a tree. -/
inductive Assoc (ι : Type) where
  | leaf (i : ι)
  | node (l r : Assoc ι)

namespace Assoc

variable {ι : Type}

/-- The leaves, left to right. -/
def leaves : Assoc ι → List ι
  | leaf i => [i]
  | node l r => leaves l ++ leaves r

/-- The number of operations along the longest root-to-leaf path. -/
def height : Assoc ι → ℕ
  | leaf _ => 0
  | node l r => max (height l) (height r) + 1

/-- The number of internal nodes: the number of operations the tree performs. -/
def nodes : Assoc ι → ℕ
  | leaf _ => 0
  | node l r => nodes l + nodes r + 1

theorem nodes_add_one (t : Assoc ι) : t.nodes + 1 = t.leaves.length := by
  induction t with
  | leaf i => rfl
  | node l r ihl ihr => simp only [nodes, leaves, List.length_append]; omega

theorem height_le_nodes (t : Assoc ι) : t.height ≤ t.nodes := by
  induction t with
  | leaf i => exact le_rfl
  | node l r ihl ihr => simp only [height, nodes]; omega

theorem height_add_one_le (t : Assoc ι) : t.height + 1 ≤ t.leaves.length := by
  have := t.nodes_add_one; have := t.height_le_nodes; omega

end Assoc

/-- `c` is a value computed for the sum of the leaf values `x i` of `t`, combined in the
association `t` with every addition rounded in the standard model. -/
inductive SumRun (u : ℝ) {ι : Type} (x : ι → ℝ) : Assoc ι → ℝ → Prop
  | leaf (i : ι) : SumRun u x (.leaf i) (x i)
  | node {l r : Assoc ι} {cl cr c : ℝ} : SumRun u x l cl → SumRun u x r cr →
      Rounded u (cl + cr) c → SumRun u x (.node l r) c

/-- `c` is a value computed for the product of the leaf values of `t`, combined in the
association `t` with every multiplication rounded in the standard model. -/
inductive ProdRun (u : ℝ) {ι : Type} (x : ι → ℝ) : Assoc ι → ℝ → Prop
  | leaf (i : ι) : ProdRun u x (.leaf i) (x i)
  | node {l r : Assoc ι} {cl cr c : ℝ} : ProdRun u x l cl → ProdRun u x r cr →
      Rounded u (cl * cr) c → ProdRun u x (.node l r) c

variable {ι : Type}

theorem sum_map_nonneg {l : List ι} {y : ι → ℝ} (h : ∀ i ∈ l, 0 ≤ y i) : 0 ≤ (l.map y).sum :=
  List.sum_nonneg (fun _ hz => by
    obtain ⟨i, hi, rfl⟩ := List.mem_map.mp hz
    exact h i hi)

theorem prod_map_nonneg {l : List ι} {y : ι → ℝ} (h : ∀ i ∈ l, 0 ≤ y i) : 0 ≤ (l.map y).prod :=
  List.prod_nonneg (fun _ hz => by
    obtain ⟨i, hi, rfl⟩ := List.mem_map.mp hz
    exact h i hi)

/-- **Computed sums.** If every leaf approximates a nonnegative exact value to relative
`γ a`, a sum computed in the association `t` approximates the exact sum to relative
`γ (a + height t)`. -/
theorem SumRun.within (hu : 0 ≤ u) {x y : ι → ℝ} {a : ℕ} {t : Assoc ι} {c : ℝ}
    (h : SumRun u x t c) (hy : ∀ i ∈ t.leaves, 0 ≤ y i ∧ RelWithin (gamma u a) (y i) (x i)) :
    RelWithin (gamma u (a + t.height)) (t.leaves.map y).sum c := by
  induction h with
  | leaf i =>
    simpa [Assoc.leaves, Assoc.height] using (hy i (by simp [Assoc.leaves])).2
  | @node l r cl cr c _ _ hc ihl ihr =>
    have hl := ihl (fun i hi => hy i (by simp [Assoc.leaves, hi]))
    have hr := ihr (fun i hi => hy i (by simp [Assoc.leaves, hi]))
    have nl : 0 ≤ (l.leaves.map y).sum :=
      sum_map_nonneg fun i hi => (hy i (by simp [Assoc.leaves, hi])).1
    have nr : 0 ≤ (r.leaves.map y).sum :=
      sum_map_nonneg fun i hi => (hy i (by simp [Assoc.leaves, hi])).1
    have hsum := (hl.mono (gamma_mono hu (show a + l.height ≤ a + max l.height r.height by omega))
      nl).add (hr.mono (gamma_mono hu (show a + r.height ≤ a + max l.height r.height by omega)) nr)
    have := hsum.round_gamma hu (add_nonneg nl nr) hc
    simpa [Assoc.leaves, Assoc.height, List.map_append, List.sum_append, add_assoc] using this

/-- **Computed products.** If leaf `i` approximates a nonnegative exact value to relative
`γ (e i)`, a product computed in the association `t` approximates the exact product to relative
`γ (Σ e i + nodes t)`, whatever the association. -/
theorem ProdRun.within (hu : 0 ≤ u) {x y : ι → ℝ} {e : ι → ℕ} {t : Assoc ι} {c : ℝ}
    (h : ProdRun u x t c) (hy : ∀ i ∈ t.leaves, 0 ≤ y i ∧ RelWithin (gamma u (e i)) (y i) (x i)) :
    RelWithin (gamma u ((t.leaves.map e).sum + t.nodes)) (t.leaves.map y).prod c := by
  induction h with
  | leaf i =>
    simpa [Assoc.leaves, Assoc.nodes] using (hy i (by simp [Assoc.leaves])).2
  | @node l r cl cr c _ _ hc ihl ihr =>
    have hl := ihl (fun i hi => hy i (by simp [Assoc.leaves, hi]))
    have hr := ihr (fun i hi => hy i (by simp [Assoc.leaves, hi]))
    have nl : 0 ≤ (l.leaves.map y).prod :=
      prod_map_nonneg fun i hi => (hy i (by simp [Assoc.leaves, hi])).1
    have nr : 0 ≤ (r.leaves.map y).prod :=
      prod_map_nonneg fun i hi => (hy i (by simp [Assoc.leaves, hi])).1
    have := (hl.mul_gamma hu hr nl nr).round_gamma hu (mul_nonneg nl nr) hc
    convert this using 2
    · simp only [Assoc.leaves, Assoc.nodes, List.map_append, List.sum_append]; ring
    · simp [Assoc.leaves, List.map_append, List.prod_append]

/-! ## Sums and products of lists, in any order and association -/

/-- `c` is a computed sum of the values `x i`, `i ∈ l`: `0` for the empty list, and otherwise a
`SumRun` over some association of some reordering of `l`. -/
def CompSum (u : ℝ) (x : ι → ℝ) (l : List ι) (c : ℝ) : Prop :=
  (l = [] ∧ c = 0) ∨ ∃ t : Assoc ι, t.leaves.Perm l ∧ SumRun u x t c

/-- `c` is a computed product of the values `x i`, `i ∈ l`: `1` for the empty list, and
otherwise a `ProdRun` over some association of some reordering of `l`. -/
def CompProd (u : ℝ) (x : ι → ℝ) (l : List ι) (c : ℝ) : Prop :=
  (l = [] ∧ c = 1) ∨ ∃ t : Assoc ι, t.leaves.Perm l ∧ ProdRun u x t c

theorem CompSum.within (hu : 0 ≤ u) {x y : ι → ℝ} {a : ℕ} {l : List ι} {c : ℝ}
    (h : CompSum u x l c) (hy : ∀ i ∈ l, 0 ≤ y i ∧ RelWithin (gamma u a) (y i) (x i)) :
    RelWithin (gamma u (a + (l.length - 1))) (l.map y).sum c := by
  rcases h with ⟨rfl, rfl⟩ | ⟨t, hp, ht⟩
  · simp [RelWithin]
  · have h1 := ht.within hu (fun i hi => hy i (hp.subset hi))
    have hlen := t.height_add_one_le
    rw [hp.length_eq] at hlen
    rw [← (hp.map y).sum_eq]
    exact h1.mono (gamma_mono hu (by omega))
      (sum_map_nonneg fun i hi => (hy i (hp.subset hi)).1)

theorem CompProd.within (hu : 0 ≤ u) {x y : ι → ℝ} {e : ι → ℕ} {l : List ι} {c : ℝ}
    (h : CompProd u x l c) (hy : ∀ i ∈ l, 0 ≤ y i ∧ RelWithin (gamma u (e i)) (y i) (x i)) :
    RelWithin (gamma u ((l.map e).sum + (l.length - 1))) (l.map y).prod c := by
  rcases h with ⟨rfl, rfl⟩ | ⟨t, hp, ht⟩
  · simp [RelWithin, gamma_zero]
  · have h1 := ht.within hu (e := e) (fun i hi => hy i (hp.subset hi))
    have hlen := t.nodes_add_one
    rw [hp.length_eq] at hlen
    rw [← (hp.map y).prod_eq, ← (hp.map e).sum_eq]
    rwa [show t.nodes = l.length - 1 by omega] at h1

/-- **Products.** A product of `k` nonnegative numbers computed in any order and association
under the standard model is within relative `γ (k - 1)` of the exact product. -/
theorem compProd_forward_error (hu : 0 ≤ u) {y : ι → ℝ} {l : List ι} {c : ℝ}
    (hy : ∀ i ∈ l, 0 ≤ y i) (h : CompProd u y l c) :
    RelWithin (gamma u (l.length - 1)) (l.map y).prod c := by
  have := h.within hu (e := fun _ => 0)
    (fun i hi => ⟨hy i hi, relWithin_refl _ (by simp [gamma_zero]) (hy i hi)⟩)
  simpa using this

/-- **Sums, in any association.** For every association tree `t` with `n` leaves, a sum of
nonnegative numbers computed along `t` under the standard model is within relative `γ (n - 1)`
of the exact sum; more sharply, within `γ (height t)`. -/
theorem sumRun_forward_error (hu : 0 ≤ u) {y : ι → ℝ} (t : Assoc ι) {c : ℝ}
    (hy : ∀ i ∈ t.leaves, 0 ≤ y i) (h : SumRun u y t c) :
    RelWithin (gamma u t.height) (t.leaves.map y).sum c ∧
      RelWithin (gamma u (t.leaves.length - 1)) (t.leaves.map y).sum c := by
  have h1 := h.within hu (a := 0)
    (fun i hi => ⟨hy i hi, relWithin_refl _ (by simp [gamma_zero]) (hy i hi)⟩)
  rw [zero_add] at h1
  have hn : 0 ≤ (t.leaves.map y).sum := sum_map_nonneg hy
  exact ⟨h1, h1.mono (gamma_mono hu (by have := t.height_add_one_le; omega)) hn⟩

/-! ## The bridge to binary64 -/

section Bridge

open Binary64

/-- The unit roundoff of binary64, `2 ^ -53`. -/
noncomputable def binary64Unit : ℝ := 2 ^ (-53 : ℤ)

theorem binary64Unit_nonneg : 0 ≤ binary64Unit := by unfold binary64Unit; positivity

/-- A finite word with the sign of `q` and magnitude `M * 2 ^ (E - 52)`, for a 53-bit `M` and a
normal exponent `E`, or `M ≤ 2 ^ 52` at the subnormal exponent `E = -1022`. -/
private theorem finite_word (q : ℚ) (M : ℕ) (E : ℤ) (hE : -1022 ≤ E) (hE' : E ≤ 1023)
    (hM : M ≤ 2 ^ 53) (hsub : M < 2 ^ 52 → E = -1022) (hno : ¬(M = 2 ^ 53 ∧ E = 1023)) :
    ∃ W, IsFinite W ∧ |value W - q| = abs ((M : ℚ) * 2 ^ (E - 52) - |q|) := by
  have hsub' : M < 2 ^ 52 → max (E - 52) (-1074) = -1074 := fun h => by rw [hsub h]; norm_num
  obtain ⟨hlt, -, hfin⟩ := packWord_spec M E hE' hM hsub'
  obtain ⟨hf, hmag, -⟩ := hfin hno
  rw [show max (E - 52) (-1074) = E - 52 by omega] at hmag
  obtain ⟨h64, -, hfield, -, -, hval⟩ := signed_word (q < 0) (packWord M E) hlt
  refine ⟨_, ⟨h64, by rw [hfield]; exact hf⟩, ?_⟩
  rw [hval, hmag]
  by_cases hq : q < 0
  · rw [if_pos hq, abs_of_neg hq, show -((M : ℚ) * 2 ^ (E - 52)) - q =
      -((M : ℚ) * 2 ^ (E - 52) - -q) by ring, abs_neg]
  · rw [if_neg hq, abs_of_nonneg (not_lt.mp hq)]

/-- Rounding `t` to the nearest integer: the floor of `t + 1/2` is within `1/2` of `t`. -/
private theorem floor_half (t : ℚ) (ht : 0 ≤ t) :
    |((⌊t + 1 / 2⌋₊ : ℕ) : ℚ) - t| ≤ 1 / 2 ∧ ((⌊t + 1 / 2⌋₊ : ℕ) : ℚ) ≤ t + 1 / 2 := by
  have h1 := Nat.floor_le (show 0 ≤ t + 1 / 2 by linarith)
  have h2 := Nat.lt_floor_add_one (t + 1 / 2)
  exact ⟨abs_le.mpr ⟨by linarith, by linarith⟩, h1⟩

set_option exponentiation.threshold 1100 in
/-- **The bridge, normal range.** A word that IEEE 754 round-to-nearest delivers for a rational
`q` with `2 ^ -1022 ≤ |q| < overflowThreshold` has relative error at most `2 ^ -53`. The proof
exhibits a finite word within `2 ^ -53 |q|` of `q` and applies `RoundsTo.nearest`. -/
theorem roundsTo_relative (q : ℚ) (w : ℕ) (hw : RoundsTo q w)
    (hlo : (2 : ℚ) ^ (-1022 : ℤ) ≤ |q|) (hhi : |q| < overflowThreshold) :
    |value w - q| ≤ 2 ^ (-53 : ℤ) * |q| := by
  set a := |q| with ha
  have hapos : 0 < a := lt_of_lt_of_le (by positivity) hlo
  set E := Int.log 2 a with hEdef
  have l1 : (2 : ℚ) ^ E ≤ a := Int.zpow_log_le_self (b := 2) (by norm_num) hapos
  have l2 : a < (2 : ℚ) ^ (E + 1) := Int.lt_zpow_succ_log_self (b := 2) (by norm_num) a
  have hthr : overflowThreshold = (2 ^ 53 - 1 / 2) * 2 ^ (971 : ℤ) := by
    norm_num [overflowThreshold]
  have hE : -1022 ≤ E := by
    by_contra h
    have : (2 : ℚ) ^ (E + 1) ≤ 2 ^ (-1022 : ℤ) := zpow_le_zpow_right₀ (by norm_num) (by omega)
    linarith
  have hE' : E ≤ 1023 := by
    by_contra h
    have : (2 : ℚ) ^ (1024 : ℤ) ≤ 2 ^ E := zpow_le_zpow_right₀ (by norm_num) (by omega)
    have h2 : overflowThreshold < (2 : ℚ) ^ (1024 : ℤ) := by rw [hthr]; norm_num
    linarith
  set s : ℤ := E - 52 with hs
  have hp : (0 : ℚ) < 2 ^ s := by positivity
  set t := a / 2 ^ s with ht
  have hta : a = t * 2 ^ s := by rw [ht]; field_simp
  have ht52 : (2 : ℚ) ^ 52 ≤ t := by
    rw [ht, le_div_iff₀ hp]
    calc (2 : ℚ) ^ 52 * 2 ^ s = 2 ^ E := by
          rw [show (2 : ℚ) ^ 52 = 2 ^ (52 : ℤ) by norm_num, ← zpow_add₀ two_ne_zero]
          congr 1; omega
      _ ≤ a := l1
  have ht53 : t < 2 ^ 53 := by
    rw [ht, div_lt_iff₀ hp]
    calc a < 2 ^ (E + 1) := l2
      _ = 2 ^ 53 * 2 ^ s := by
          rw [show (2 : ℚ) ^ 53 = 2 ^ (53 : ℤ) by norm_num, ← zpow_add₀ two_ne_zero]
          congr 1; omega
  obtain ⟨hM, hMle⟩ := floor_half t (by linarith)
  set M := ⌊t + 1 / 2⌋₊ with hMdef
  have hM52 : 2 ^ 52 ≤ M := Nat.le_floor (by push_cast; linarith)
  have hM53 : M ≤ 2 ^ 53 := by
    have : (M : ℚ) < 2 ^ 53 + 1 := by linarith
    exact_mod_cast Nat.lt_succ_iff.mp (by exact_mod_cast this)
  have hno : ¬(M = 2 ^ 53 ∧ E = 1023) := by
    rintro ⟨h1, h2⟩
    have : (2 : ℚ) ^ 53 - 1 / 2 ≤ t := by
      have : ((2 ^ 53 : ℕ) : ℚ) ≤ t + 1 / 2 := h1 ▸ hMle
      push_cast at this; linarith
    have hs' : s = 971 := by omega
    rw [hs'] at hta
    have : overflowThreshold ≤ a := by
      rw [hthr, hta]; exact mul_le_mul_of_nonneg_right this (by positivity)
    linarith
  obtain ⟨W, hW, hdist⟩ := finite_word q M E hE hE' hM53 (fun h => absurd h (by omega)) hno
  refine le_trans (hw.nearest hhi W hW) ?_
  rw [hdist, ← ha, hta, ← sub_mul, abs_mul, abs_of_pos hp]
  calc |(M : ℚ) - t| * 2 ^ s ≤ 1 / 2 * 2 ^ s := mul_le_mul_of_nonneg_right hM hp.le
    _ = 2 ^ (-53 : ℤ) * 2 ^ E := by
        rw [← zpow_add₀ two_ne_zero, show (1 : ℚ) / 2 = 2 ^ (-1 : ℤ) by norm_num,
          ← zpow_add₀ two_ne_zero]
        congr 1; omega
    _ ≤ 2 ^ (-53 : ℤ) * (t * 2 ^ s) := by rw [← hta]; gcongr

set_option exponentiation.threshold 1100 in
/-- **The bridge, subnormal range.** Below `2 ^ -1022` the error is at most half the subnormal
spacing, `2 ^ -1075`: an absolute, not a relative, bound. -/
theorem roundsTo_subnormal (q : ℚ) (w : ℕ) (hw : RoundsTo q w)
    (hq : |q| < (2 : ℚ) ^ (-1022 : ℤ)) : |value w - q| ≤ 2 ^ (-1075 : ℤ) := by
  have hthr : (2 : ℚ) ^ (-1022 : ℤ) < overflowThreshold := by
    norm_num [overflowThreshold]
  set a := |q| with ha
  have ha0 : 0 ≤ a := abs_nonneg q
  have hp : (0 : ℚ) < 2 ^ (-1074 : ℤ) := by positivity
  set t := a / 2 ^ (-1074 : ℤ) with ht
  have hta : a = t * 2 ^ (-1074 : ℤ) := by rw [ht]; field_simp
  have ht52 : t < 2 ^ 52 := by
    rw [ht, div_lt_iff₀ hp]
    calc a < 2 ^ (-1022 : ℤ) := hq
      _ = 2 ^ 52 * 2 ^ (-1074 : ℤ) := by
          rw [show (2 : ℚ) ^ 52 = 2 ^ (52 : ℤ) by norm_num, ← zpow_add₀ two_ne_zero]; norm_num
  obtain ⟨hM, hMle⟩ := floor_half t (div_nonneg ha0 hp.le)
  set M := ⌊t + 1 / 2⌋₊ with hMdef
  have hM52 : M ≤ 2 ^ 52 := by
    have : (M : ℚ) < 2 ^ 52 + 1 := by linarith
    exact_mod_cast Nat.lt_succ_iff.mp (by exact_mod_cast this)
  obtain ⟨W, hW, hdist⟩ := finite_word q M (-1022) le_rfl (by norm_num) (by omega)
    (fun _ => rfl) (by omega)
  refine le_trans (hw.nearest (lt_trans hq hthr) W hW) ?_
  rw [hdist, ← ha, hta, show (-1022 : ℤ) - 52 = -1074 by norm_num, ← sub_mul, abs_mul,
    abs_of_pos hp]
  calc |(M : ℚ) - t| * 2 ^ (-1074 : ℤ) ≤ 1 / 2 * 2 ^ (-1074 : ℤ) :=
        mul_le_mul_of_nonneg_right hM hp.le
    _ = _ := by
        rw [show (-1074 : ℤ) = 1 + (-1075) by norm_num, zpow_add₀ two_ne_zero]; norm_num

/-- Both ranges at once: below the overflow threshold, `|value w - q| ≤ 2 ^ -53 |q| + 2 ^ -1075`. -/
theorem roundsTo_error (q : ℚ) (w : ℕ) (hw : RoundsTo q w) (hhi : |q| < overflowThreshold) :
    |value w - q| ≤ 2 ^ (-53 : ℤ) * |q| + 2 ^ (-1075 : ℤ) := by
  by_cases h : (2 : ℚ) ^ (-1022 : ℤ) ≤ |q|
  · have := roundsTo_relative q w hw h hhi
    have : (0 : ℚ) ≤ 2 ^ (-1075 : ℤ) := by positivity
    linarith
  · have := roundsTo_subnormal q w hw (not_le.mp h)
    have : (0 : ℚ) ≤ 2 ^ (-53 : ℤ) * |q| := by positivity
    linarith

set_option exponentiation.threshold 1100 in
/-- A correctly rounded zero is exactly zero. -/
theorem roundsTo_zero (w : ℕ) (hw : RoundsTo 0 w) : value w = 0 := by
  have hthr : |(0 : ℚ)| < overflowThreshold := by norm_num [overflowThreshold]
  have h0 : IsFinite 0 := ⟨by norm_num, by simp [field]⟩
  have hv0 : value 0 = 0 := by simp [value, magnitude, signBit, field, fraction]
  have := hw.nearest hthr 0 h0
  rw [hv0, sub_zero, sub_zero, abs_zero] at this
  exact abs_nonpos_iff.mp this

/-- **The standard model holds for IEEE 754 binary64 rounding** away from underflow and
overflow: when the exact result is zero or has magnitude in `[2 ^ -1022, overflowThreshold)`,
its correctly rounded value is `Rounded binary64Unit`. -/
theorem roundsTo_rounded (q : ℚ) (w : ℕ) (hw : RoundsTo q w)
    (hq : q = 0 ∨ ((2 : ℚ) ^ (-1022 : ℤ) ≤ |q| ∧ |q| < overflowThreshold)) :
    Rounded binary64Unit (q : ℝ) (value w : ℝ) := by
  rw [rounded_iff binary64Unit_nonneg]
  rcases hq with rfl | ⟨hlo, hhi⟩
  · simp [roundsTo_zero w hw]
  · have h := roundsTo_relative q w hw hlo hhi
    have h' : ((|value w - q| : ℚ) : ℝ) ≤ ((2 ^ (-53 : ℤ) * |q| : ℚ) : ℝ) := by exact_mod_cast h
    push_cast at h'
    simpa [binary64Unit] using h'

/-- The same for the transcription of `_nearest_binary64`, through `nearestBinary64_roundsTo`. -/
theorem nearestBinary64_rounded (q : ℚ)
    (hq : q = 0 ∨ ((2 : ℚ) ^ (-1022 : ℤ) ≤ |q| ∧ |q| < overflowThreshold)) :
    Rounded binary64Unit (q : ℝ) (value (nearestBinary64 q) : ℝ) :=
  roundsTo_rounded q _ (nearestBinary64_roundsTo q) hq

/-- `_nearest_binary64` in the normal range: relative error at most `2 ^ -53`. -/
theorem nearestBinary64_relative (q : ℚ) (hlo : (2 : ℚ) ^ (-1022 : ℤ) ≤ |q|)
    (hhi : |q| < overflowThreshold) :
    |value (nearestBinary64 q) - q| ≤ 2 ^ (-53 : ℤ) * |q| :=
  roundsTo_relative q _ (nearestBinary64_roundsTo q) hlo hhi

/-- `_nearest_binary64` in the subnormal range: absolute error at most `2 ^ -1075`. -/
theorem nearestBinary64_subnormal (q : ℚ) (hq : |q| < (2 : ℚ) ^ (-1022 : ℤ)) :
    |value (nearestBinary64 q) - q| ≤ 2 ^ (-1075 : ℤ) :=
  roundsTo_subnormal q _ (nearestBinary64_roundsTo q) hq

end Bridge

/-! ## Normalisation -/

/-- **Quotients.** If `x` approximates `y ≥ 0` to relative `α ≤ 1` and `X` approximates `Y > 0`
to relative `β < 1`, then `x / X` approximates `y / Y` to relative `(1 + α) / (1 - β) - 1`. -/
theorem RelWithin.div {α β y Y x X : ℝ} (h : RelWithin α y x) (H : RelWithin β Y X)
    (hα : 0 ≤ α) (hα1 : α ≤ 1) (hβ : 0 ≤ β) (hβ1 : β < 1) (hy : 0 ≤ y) (hY : 0 < Y) :
    RelWithin ((1 + α) / (1 - β) - 1) (y / Y) (x / X) := by
  unfold RelWithin at *
  obtain ⟨hX1, hX2⟩ := _root_.abs_le.mp H
  obtain ⟨hx1, hx2⟩ := _root_.abs_le.mp h
  have hb : 0 < 1 - β := by linarith
  have hXpos : 0 < X := by nlinarith
  have hr : 0 ≤ y / Y := div_nonneg hy hY.le
  have up : x / X ≤ (1 + α) / (1 - β) * (y / Y) := by
    calc x / X ≤ (1 + α) * y / X := div_le_div_of_nonneg_right (by linarith) hXpos.le
      _ ≤ (1 + α) * y / ((1 - β) * Y) :=
          div_le_div_of_nonneg_left (by positivity) (by positivity) (by linarith)
      _ = _ := by field_simp
  have key : 2 - (1 + α) / (1 - β) ≤ (1 - α) / (1 + β) := by
    have h1 : (0 : ℝ) < 1 + β := by linarith
    rw [sub_le_iff_le_add, div_add_div _ _ h1.ne' hb.ne', le_div_iff₀ (by positivity)]
    nlinarith [mul_nonneg hα hβ, sq_nonneg β]
  have lo : (2 - (1 + α) / (1 - β)) * (y / Y) ≤ x / X := by
    calc (2 - (1 + α) / (1 - β)) * (y / Y) ≤ (1 - α) / (1 + β) * (y / Y) :=
          mul_le_mul_of_nonneg_right key hr
      _ = (1 - α) * y / ((1 + β) * Y) := by field_simp
      _ ≤ (1 - α) * y / X :=
          div_le_div_of_nonneg_left (mul_nonneg (by linarith) hy) hXpos (by linarith)
      _ ≤ x / X := div_le_div_of_nonneg_right (by linarith) hXpos.le
  rw [_root_.abs_le]
  constructor <;> nlinarith

open FiniteDistribution in
/-- **Normalisation.** Exact nonnegative weights `w` with positive mass; computed weights within
relative `γ N`; a computed mass `Z`, summed in any order and association; and each posterior
entry the rounded quotient `wc a / Z`. With `K = N + |A|` and `γ K < 1`, the computed mass is
within relative `γ (K - 1)` of the exact mass, and every computed posterior entry within
relative `(1 + γ K) / (1 - γ K) - 1` of the exact one. -/
theorem normalize_forward_error {A : Type} [Fintype A] (hu : 0 ≤ u) (w wc : A → ℝ)
    (hw : ∀ a, 0 ≤ w a) (N : ℕ) (hwc : ∀ a, RelWithin (gamma u N) (w a) (wc a)) (Z : ℝ)
    (hZ : CompSum u wc Finset.univ.toList Z) (post : A → ℝ)
    (hpost : ∀ a, Rounded u (wc a / Z) (post a)) (hmass : 0 < mass w)
    (hsmall : gamma u (N + Fintype.card A) < 1) :
    RelWithin (gamma u (N + Fintype.card A - 1)) (mass w) Z ∧
      ∀ a, RelWithin ((1 + gamma u (N + Fintype.card A)) / (1 - gamma u (N + Fintype.card A)) - 1)
        (w a / mass w) (post a) := by
  set K := N + Fintype.card A with hK
  have hcard : 0 < Fintype.card A := by
    obtain ⟨a, -⟩ := Finset.exists_ne_zero_of_sum_ne_zero (s := Finset.univ) (f := w)
      (by rw [← mass]; exact hmass.ne')
    exact Fintype.card_pos_iff.mpr ⟨a⟩
  have hZ' := hZ.within hu (y := w) (fun a _ => ⟨hw a, hwc a⟩)
  rw [Finset.sum_map_toList, Finset.length_toList, Finset.card_univ] at hZ'
  have hmassZ : RelWithin (gamma u (K - 1)) (mass w) Z := by
    rw [show K - 1 = N + (Fintype.card A - 1) by omega]; exact hZ'
  refine ⟨hmassZ, fun a => ?_⟩
  have g1 : gamma u N ≤ gamma u K := gamma_mono hu (by omega)
  have g2 : gamma u (K - 1) ≤ gamma u K := gamma_mono hu (by omega)
  have g3 : gamma u (N + 1) ≤ gamma u K := gamma_mono hu (by omega)
  have hq := (hwc a).div hmassZ (gamma_nonneg hu N) (by linarith) (gamma_nonneg hu _)
    (by linarith) (hw a) hmass
  have hr := hq.round (div_nonneg (hw a) hmass.le) hu (hpost a)
  refine hr.mono ?_ (div_nonneg (hw a) hmass.le)
  have hb : 0 < 1 - gamma u K := by linarith
  have hb' : 1 - gamma u K ≤ 1 - gamma u (K - 1) := by linarith
  have hb'' : 0 < 1 - gamma u (K - 1) := by linarith
  have h1 : (1 + u) * (1 + gamma u N) = 1 + gamma u (N + 1) := by
    rw [one_add_gamma, one_add_gamma, pow_succ]; ring
  rw [show (1 + u) * (1 + ((1 + gamma u N) / (1 - gamma u (K - 1)) - 1)) - 1 =
      (1 + u) * (1 + gamma u N) / (1 - gamma u (K - 1)) - 1 by ring, h1]
  gcongr ?_ - 1
  calc (1 + gamma u (N + 1)) / (1 - gamma u (K - 1)) ≤ (1 + gamma u K) / (1 - gamma u (K - 1)) :=
        div_le_div_of_nonneg_right (by linarith) hb''.le
    _ ≤ _ := div_le_div_of_nonneg_left (by linarith [gamma_nonneg hu K]) hb hb'

/-! ## Variable elimination under the standard model -/

open FinBayesNet FinBayesNet.Factor FiniteDistribution

variable {bn : FinBayesNet}

/-- A factor of the exact algebra paired with the table a floating-point run computed for it. -/
abbrev Computed (bn : FinBayesNet) := Factor bn ℝ × (bn.Assignment → ℝ)

/-- The computed factors in the bucket of `v`, selected by the exact scopes as in `bucket`. -/
def cbucket (v : bn.V) (ps : List (Computed bn)) : List (Computed bn) :=
  ps.filter (fun p => decide (v ∈ p.1.scope))

/-- The computed factors outside the bucket of `v`, as in `outside`. -/
def coutside (v : bn.V) (ps : List (Computed bn)) : List (Computed bn) :=
  ps.filter (fun p => decide (v ∉ p.1.scope))

theorem cbucket_fst (v : bn.V) (ps : List (Computed bn)) :
    (cbucket v ps).map Prod.fst = bucket v (ps.map Prod.fst) := by
  induction ps with
  | nil => rfl
  | cons p ps ih =>
    by_cases h : v ∈ p.1.scope <;> simp_all [cbucket, bucket]

theorem coutside_fst (v : bn.V) (ps : List (Computed bn)) :
    (coutside v ps).map Prod.fst = outside v (ps.map Prod.fst) := by
  induction ps with
  | nil => rfl
  | cons p ps ih =>
    by_cases h : v ∈ p.1.scope <;> simp_all [coutside, outside]

/-- One computed sum-out: every entry of `g` is a sum, computed in some order and association,
over the states `a` of `v` of values `c a`, each a product, computed in some order and
association, of the bucket's computed tables at `x` updated to `v = a`. -/
def SumOutStep (u : ℝ) (v : bn.V) (ps : List (Computed bn)) (g : bn.Assignment → ℝ) : Prop :=
  ∀ x, ∃ c : bn.states v → ℝ, CompSum u c Finset.univ.toList (g x) ∧
    ∀ a, CompProd u (fun p : Computed bn => p.2 (Function.update x v a)) (cbucket v ps) (c a)

/-- **An approximate elimination run**, step for step beside `eliminateAll`: each step replaces
the bucket of `v` by the exact `sumBucket` paired with a computed table `g` satisfying
`SumOutStep`, and keeps every factor outside the bucket with its table unchanged. -/
inductive Run (u : ℝ) : List (Computed bn) → List bn.V → List (Computed bn) → Prop
  | nil (ps : List (Computed bn)) : Run u ps [] ps
  | cons {v : bn.V} {vs : List bn.V} {ps out : List (Computed bn)} {g : bn.Assignment → ℝ} :
      SumOutStep u v ps g →
      Run u ((sumBucket v (bucket v (ps.map Prod.fst)), g) :: coutside v ps) vs out →
      Run u ps (v :: vs) out

/-- The input factors, with their exact tables: the run starts from the CPT entries as given. -/
def inputs (fs : List (Factor bn ℝ)) : List (Computed bn) := fs.map fun f => (f, f.value)

/-- The run's exact half is `eliminateAll`. -/
theorem Run.fst {ps : List (Computed bn)} {vs : List bn.V} {out : List (Computed bn)}
    (h : Run u ps vs out) : out.map Prod.fst = eliminateAll (ps.map Prod.fst) vs := by
  induction h with
  | nil ps => rfl
  | @cons v vs ps out g _ _ ih =>
    rw [ih, List.map_cons, coutside_fst]
    rfl

/-- The explicit index: `m` input factors and the summed domain sizes of the eliminated
variables, less one. -/
def veIndex (m : ℕ) (vs : List bn.V) : ℕ :=
  m + (vs.map fun v => Fintype.card (bn.states v)).sum - 1

/-- A computed factor with nonnegative exact entries and some uniform relative bound. -/
def Good (u : ℝ) (p : Computed bn) : Prop :=
  (∀ x, 0 ≤ p.1.value x) ∧ ∃ n : ℕ, ∀ x, RelWithin (gamma u n) (p.1.value x) (p.2 x)

/-- The least `n` with every computed entry within relative `γ n`. -/
noncomputable def errIndex (u : ℝ) (p : Computed bn) : ℕ :=
  sInf {n : ℕ | ∀ x, RelWithin (gamma u n) (p.1.value x) (p.2 x)}

theorem Good.within {p : Computed bn} (h : Good u p) :
    ∀ x, RelWithin (gamma u (errIndex u p)) (p.1.value x) (p.2 x) :=
  Nat.sInf_mem (s := {n : ℕ | ∀ x, RelWithin (gamma u n) (p.1.value x) (p.2 x)}) h.2

theorem errIndex_le {p : Computed bn} {n : ℕ}
    (h : ∀ x, RelWithin (gamma u n) (p.1.value x) (p.2 x)) : errIndex u p ≤ n :=
  Nat.sInf_le h

/-- The potential `Σ (errIndex + 1)`: a step raises it by at most the domain size. -/
noncomputable def potential (u : ℝ) (ps : List (Computed bn)) : ℕ :=
  (ps.map fun p => errIndex u p + 1).sum

theorem potential_eq (ps : List (Computed bn)) :
    potential u ps = (ps.map (errIndex u)).sum + ps.length := by
  induction ps with
  | nil => rfl
  | cons p ps ih => simp only [potential, List.map_cons, List.sum_cons, List.length_cons] at *; omega

theorem potential_split (v : bn.V) (ps : List (Computed bn)) :
    potential u ps = potential u (cbucket v ps) + potential u (coutside v ps) := by
  induction ps with
  | nil => rfl
  | cons p ps ih =>
    by_cases h : v ∈ p.1.scope <;>
      simp_all [potential, cbucket, coutside] <;> omega

theorem product_eq_map (fs : List (Factor bn ℝ)) (x : bn.Assignment) :
    product fs x = (fs.map fun f => f.value x).prod := rfl

/-- One step: the new computed factor is good, and its index plus one is at most the bucket's
potential plus the domain size of `v`. -/
theorem sumOutStep_good (hu : 0 ≤ u) {v : bn.V} {ps : List (Computed bn)}
    {g : bn.Assignment → ℝ} (hgood : ∀ p ∈ ps, Good u p) (hstep : SumOutStep u v ps g) :
    Good u (sumBucket v (bucket v (ps.map Prod.fst)), g) ∧
      errIndex u (sumBucket v (bucket v (ps.map Prod.fst)), g) + 1 ≤
        potential u (cbucket v ps) + Fintype.card (bn.states v) := by
  have hb : ∀ p ∈ cbucket v ps, Good u p := fun p hp => hgood p (List.mem_filter.mp hp).1
  have hexact : ∀ z, product (bucket v (ps.map Prod.fst)) z =
      ((cbucket v ps).map fun p : Computed bn => p.1.value z).prod := by
    intro z
    rw [product_eq_map, ← cbucket_fst, List.map_map]
    rfl
  have hnn : ∀ z, 0 ≤ product (bucket v (ps.map Prod.fst)) z := fun z => by
    rw [hexact]; exact prod_map_nonneg fun p hp => (hb p hp).1 z
  set n := ((cbucket v ps).map (errIndex u)).sum + ((cbucket v ps).length - 1) +
    (Fintype.card (bn.states v) - 1) with hn
  have hwithin : ∀ x, RelWithin (gamma u n) ((sumBucket v (bucket v (ps.map Prod.fst))).value x)
      (g x) := by
    intro x
    obtain ⟨c, hsum, hprod⟩ := hstep x
    have hc : ∀ a, RelWithin (gamma u (((cbucket v ps).map (errIndex u)).sum +
        ((cbucket v ps).length - 1))) (product (bucket v (ps.map Prod.fst))
          (Function.update x v a)) (c a) := by
      intro a
      rw [hexact]
      exact (hprod a).within hu (y := fun p : Computed bn => p.1.value (Function.update x v a))
        (fun p hp => ⟨(hb p hp).1 _, (hb p hp).within _⟩)
    have := hsum.within hu (y := fun a => product (bucket v (ps.map Prod.fst))
      (Function.update x v a)) (fun a _ => ⟨hnn _, hc a⟩)
    rw [Finset.sum_map_toList, Finset.length_toList, Finset.card_univ] at this
    exact this
  have hcard : 0 < Fintype.card (bn.states v) := Fintype.card_pos
  refine ⟨⟨fun x => Finset.sum_nonneg fun a _ => hnn _, n, hwithin⟩, ?_⟩
  have := errIndex_le (p := (sumBucket v (bucket v (ps.map Prod.fst)), g)) hwithin
  rw [potential_eq]
  omega

/-- The invariant of a run: every computed factor stays good, and the potential grows by at most
the domain size of each eliminated variable. -/
theorem Run.good (hu : 0 ≤ u) {ps : List (Computed bn)} {vs : List bn.V}
    {out : List (Computed bn)} (h : Run u ps vs out) (hgood : ∀ p ∈ ps, Good u p) :
    (∀ p ∈ out, Good u p) ∧
      potential u out ≤ potential u ps + (vs.map fun v => Fintype.card (bn.states v)).sum := by
  induction h with
  | nil ps => exact ⟨hgood, by simp⟩
  | @cons v vs ps out g hstep _ ih =>
    obtain ⟨hnew, hle⟩ := sumOutStep_good hu hgood hstep
    obtain ⟨hout, hpot⟩ := ih (by
      intro p hp
      rcases List.mem_cons.mp hp with rfl | hp
      · exact hnew
      · exact hgood p (List.mem_filter.mp hp).1)
    refine ⟨hout, ?_⟩
    have hsplit := potential_split (u := u) v ps
    simp only [potential, List.map_cons, List.sum_cons] at hpot hle hsplit ⊢
    omega

theorem inputs_good (fs : List (Factor bn ℝ)) (hfs : ∀ f ∈ fs, ∀ x, 0 ≤ f.value x) :
    (∀ p ∈ inputs fs, Good u p) ∧ potential u (inputs fs) = fs.length := by
  have h0 : ∀ f ∈ fs, ∀ x, RelWithin (gamma u 0) (f.value x) (f.value x) := fun f hf x =>
    relWithin_refl _ (by rw [gamma_zero]) (hfs f hf x)
  refine ⟨fun p hp => ?_, ?_⟩
  · obtain ⟨f, hf, rfl⟩ := List.mem_map.mp hp
    exact ⟨hfs f hf, 0, h0 f hf⟩
  · have : ∀ f ∈ fs, errIndex u ((f, f.value) : Computed bn) = 0 := fun f hf =>
      Nat.le_zero.mp (errIndex_le (h0 f hf))
    unfold potential inputs
    rw [List.map_map]
    induction fs with
    | nil => rfl
    | cons f fs ih =>
      simp only [List.map_cons, List.sum_cons, List.length_cons, Function.comp_apply]
      rw [this f (by simp), ih (fun g hg => hfs g (by simp [hg])) (fun g hg x => h0 g (by simp [hg]) x)
        (fun g hg => this g (by simp [hg]))]
      ring

/-- **Forward error of variable elimination.** Let `fs` be nonnegative factors, `vs` an
elimination order, and `out` the result of any approximate run under the standard model with
unit roundoff `u ≥ 0`. Then the exact half of `out` is `eliminateAll fs vs`; every entry of every
computed factor in `out` is within relative `γ N` of the exact entry; and so is any product of the
remaining computed factors, in any order and association, with
`N = veIndex fs.length vs = |fs| + Σ_{v ∈ vs} |states v| - 1`. -/
theorem eliminateAll_forward_error (hu : 0 ≤ u) (fs : List (Factor bn ℝ))
    (hfs : ∀ f ∈ fs, ∀ x, 0 ≤ f.value x) (vs : List bn.V) (out : List (Computed bn))
    (hrun : Run u (inputs fs) vs out) :
    out.map Prod.fst = eliminateAll fs vs ∧
      (∀ p ∈ out, ∀ x, RelWithin (gamma u (veIndex fs.length vs)) (p.1.value x) (p.2 x)) ∧
      ∀ x c, CompProd u (fun p : Computed bn => p.2 x) out c →
        RelWithin (gamma u (veIndex fs.length vs)) (product (eliminateAll fs vs) x) c := by
  have hfst : out.map Prod.fst = eliminateAll fs vs := by
    rw [hrun.fst]; simp [inputs, Function.comp_def]
  obtain ⟨hgood0, hpot0⟩ := inputs_good (u := u) fs hfs
  obtain ⟨hgood, hpot⟩ := hrun.good hu hgood0
  rw [hpot0] at hpot
  have hpe := potential_eq (u := u) out
  refine ⟨hfst, fun p hp x => ?_, fun x c hc => ?_⟩
  · have hle : errIndex u p + 1 ≤ potential u out :=
      List.le_sum_of_mem (List.mem_map.mpr ⟨p, hp, rfl⟩)
    have hidx : errIndex u p ≤ veIndex fs.length vs := by unfold veIndex; omega
    exact ((hgood p hp).within x).mono (gamma_mono hu hidx) ((hgood p hp).1 x)
  · have := hc.within hu (y := fun p : Computed bn => p.1.value x) (e := errIndex u)
      (fun p hp => ⟨(hgood p hp).1 x, (hgood p hp).within x⟩)
    rw [← hfst, product_eq_map, List.map_map]
    have hidx : (out.map (errIndex u)).sum + (out.length - 1) ≤ veIndex fs.length vs := by
      have h0 : out.length = 0 → (out.map (errIndex u)).sum = 0 := fun h => by
        rw [List.length_eq_zero_iff.mp h]; rfl
      unfold veIndex; omega
    refine this.mono (gamma_mono hu hidx) ?_
    exact prod_map_nonneg fun p hp => (hgood p hp).1 x

/-- With a duplicate-free order, the computed result approximates the exact marginal
`marg vs.toFinset (product fs)` (`eliminateAll_correct`). -/
theorem eliminateAll_marg_forward_error (hu : 0 ≤ u) (fs : List (Factor bn ℝ))
    (hfs : ∀ f ∈ fs, ∀ x, 0 ≤ f.value x) (vs : List bn.V) (hvs : vs.Nodup)
    (out : List (Computed bn)) (hrun : Run u (inputs fs) vs out) (x : bn.Assignment) (c : ℝ)
    (hc : CompProd u (fun p : Computed bn => p.2 x) out c) :
    RelWithin (gamma u (veIndex fs.length vs)) (marg vs.toFinset (product fs) x) c := by
  rw [← eliminateAll_correct fs vs hvs x]
  exact (eliminateAll_forward_error hu fs hfs vs out hrun).2.2 x c hc

/-- Evidence by slicing, the shape of the Julia engine: eliminating over factors conditioned on
the evidence (`condition`, `explicit_conditioning_elimination`) gives the same bound, with the
evidence variables neither factors nor eliminated. -/
theorem conditioned_forward_error (hu : 0 ≤ u) (fs : List (Factor bn ℝ))
    (hfs : ∀ f ∈ fs, ∀ x, 0 ≤ f.value x) (E : Finset bn.V) (observed : bn.Assignment)
    (vs : List bn.V) (hvs : vs.Nodup) (hd : Disjoint E vs.toFinset) (out : List (Computed bn))
    (hrun : Run u (inputs (fs.map (condition E observed))) vs out) (x : bn.Assignment) (c : ℝ)
    (hc : CompProd u (fun p : Computed bn => p.2 x) out c) :
    RelWithin (gamma u (veIndex fs.length vs))
      (marg (vs.toFinset ∪ E) (fun y => product fs y * indicator E observed y) x) c := by
  rw [← explicit_conditioning_elimination fs E observed vs hvs hd x]
  have h := (eliminateAll_forward_error hu (fs.map (condition E observed))
    (fun f hf y => by
      obtain ⟨g, hg, rfl⟩ := List.mem_map.mp hf
      exact hfs g hg _) vs out hrun).2.2 x c hc
  rwa [List.length_map] at h

theorem length_inputs_posterior (κ : bn.Kernel ℝ) (hloc : ∀ m, Local κ m) (E : Finset bn.V)
    (observed : bn.Assignment) :
    (evidenceFactor E observed :: ofKernel κ hloc).length = Fintype.card bn.M + 1 := by
  simp [ofKernel, Finset.length_toList]

/-- The explicit index of the posterior bound: `N = veIndex (|M| + 1) vs` for the CPT factors
and the evidence indicator, plus the number of query assignments. -/
def posteriorIndex (bn : FinBayesNet) (Q : Finset bn.V) (vs : List bn.V) : ℕ :=
  veIndex (Fintype.card bn.M + 1) vs + Fintype.card (PartialAssignment bn Q)

/-- **Forward error of the posterior.** Run variable elimination under the standard model on
the compiled CPT factors and the evidence indicator, eliminating `vs = Qᶜ`; compute each
query entry `num q` as a product of the remaining tables at a query assignment, the mass `Z`
as a sum of the `num q` in any order and association, and each posterior entry as the rounded
quotient `num q / Z`. Whenever the exact posterior exists (positive evidence mass) and
`γ K < 1` with `K = posteriorIndex bn Q vs`, the computed mass is within relative `γ (K - 1)`
of the evidence mass, and every computed posterior entry is within relative
`(1 + γ K) / (1 - γ K) - 1` of the exact posterior entry. -/
theorem ve_posterior_forward_error (hu : 0 ≤ u) (κ : bn.Kernel ℝ) (hloc : ∀ m, Local κ m)
    (hκ : ∀ m x a, 0 ≤ κ m x a) (Q E : Finset bn.V) (observed : bn.Assignment)
    (vs : List bn.V) (hvs : vs.Nodup) (hset : vs.toFinset = Qᶜ) (out : List (Computed bn))
    (hrun : Run u (inputs (evidenceFactor E observed :: ofKernel κ hloc)) vs out)
    (base : bn.Assignment) (num : PartialAssignment bn Q → ℝ)
    (hnum : ∀ q, CompProd u (fun p : Computed bn => p.2 (patch Q base q)) out (num q))
    (Z : ℝ) (hZ : CompSum u num Finset.univ.toList Z)
    (post : PartialAssignment bn Q → ℝ) (hpost : ∀ q, Rounded u (num q / Z) (post q))
    (d : Distribution (PartialAssignment bn Q))
    (hd : posterior Q E observed (joint κ) (joint_nonneg κ hκ) = some d)
    (hsmall : gamma u (posteriorIndex bn Q vs) < 1) :
    RelWithin (gamma u (posteriorIndex bn Q vs - 1)) (mass (likelihoodWeight (joint κ) E observed))
        Z ∧
      ∀ q, RelWithin ((1 + gamma u (posteriorIndex bn Q vs)) /
        (1 - gamma u (posteriorIndex bn Q vs)) - 1) (d.pmf q) (post q) := by
  set fs := evidenceFactor E observed :: ofKernel κ hloc with hfsdef
  have hfs : ∀ f ∈ fs, ∀ x, 0 ≤ f.value x := by
    intro f hf x
    rcases List.mem_cons.mp hf with rfl | hf
    · change 0 ≤ indicator E observed x
      unfold indicator; split_ifs <;> norm_num
    · obtain ⟨m, -, rfl⟩ := List.mem_map.mp hf
      exact hκ m x _
  set w := pushWeight (restrictTo Q) (likelihoodWeight (joint κ) E observed) with hw
  have hwn : ∀ q, 0 ≤ w q :=
    pushWeight_nonneg _ _ (likelihoodWeight_nonneg _ (joint_nonneg κ hκ) E observed)
  have hwc : ∀ q, RelWithin (gamma u (veIndex (Fintype.card bn.M + 1) vs)) (w q) (num q) := by
    intro q
    have h := (eliminateAll_forward_error hu fs hfs vs out hrun).2.2 _ _ (hnum q)
    rw [ve_posterior_numerator κ hloc Q E observed vs hvs hset, restrict_patch] at h
    rwa [hfsdef, length_inputs_posterior] at h
  have hmass : 0 < mass w := by
    have hne : posterior Q E observed (joint κ) (joint_nonneg κ hκ) ≠ none := by rw [hd]; simp
    rw [posterior, Ne, normalize_none_iff] at hne
    exact lt_of_le_of_ne (mass_nonneg _ hwn) (Ne.symm hne)
  obtain ⟨hZm, hpq⟩ := normalize_forward_error hu w num hwn _ hwc Z hZ post hpost hmass hsmall
  have hmw : mass w = mass (likelihoodWeight (joint κ) E observed) := mass_pushWeight _ _
  refine ⟨by rw [← hmw]; exact hZm, fun q => ?_⟩
  have hdq : d.pmf q = w q / mass w := by
    have := normalize_value _ _ d hd q
    rw [this]
  rw [hdq]
  exact hpq q

/-! ## Log-sum-exp -/

section LogSumExp

open Real

/-- Sums with an arbitrary leaf bound `e`: along `t`, the bound becomes
`(1 + u) ^ height t * (1 + e) - 1`. -/
theorem SumRun.within_rel (hu : 0 ≤ u) {ι : Type} {x y : ι → ℝ} {e : ℝ} (he : 0 ≤ e)
    {t : Assoc ι} {c : ℝ} (h : SumRun u x t c)
    (hy : ∀ i ∈ t.leaves, 0 ≤ y i ∧ RelWithin e (y i) (x i)) :
    RelWithin ((1 + u) ^ t.height * (1 + e) - 1) (t.leaves.map y).sum c := by
  have h1u : (1 : ℝ) ≤ 1 + u := by linarith
  induction h with
  | leaf i =>
    simpa [Assoc.leaves, Assoc.height] using (hy i (by simp [Assoc.leaves])).2
  | @node l r cl cr c _ _ hc ihl ihr =>
    have hl := ihl (fun i hi => hy i (by simp [Assoc.leaves, hi]))
    have hr := ihr (fun i hi => hy i (by simp [Assoc.leaves, hi]))
    have nl : 0 ≤ (l.leaves.map y).sum :=
      sum_map_nonneg fun i hi => (hy i (by simp [Assoc.leaves, hi])).1
    have nr : 0 ≤ (r.leaves.map y).sum :=
      sum_map_nonneg fun i hi => (hy i (by simp [Assoc.leaves, hi])).1
    have mono : ∀ k, k ≤ max l.height r.height →
        (1 + u) ^ k * (1 + e) - 1 ≤ (1 + u) ^ (max l.height r.height) * (1 + e) - 1 :=
      fun k hk => by gcongr
    have hsum := (hl.mono (mono _ (le_max_left _ _)) nl).add (hr.mono (mono _ (le_max_right _ _)) nr)
    have := hsum.round (add_nonneg nl nr) hu hc
    simp only [Assoc.leaves, Assoc.height, List.map_append, List.sum_append]
    convert this using 2
    rw [pow_succ]; ring

theorem abs_exp_sub_one_le (t : ℝ) : |exp t - 1| ≤ exp |t| - 1 := by
  have h1 := add_one_le_exp t
  have h2 := add_one_le_exp (-t)
  rcases le_total 0 t with ht | ht
  · rw [abs_of_nonneg ht, abs_of_nonneg (by linarith)]
  · rw [abs_of_nonpos ht, abs_of_nonpos (by linarith [exp_le_one_iff.mpr ht])]
    have : exp t * exp (-t) = 1 := by rw [← exp_add]; simp
    nlinarith [exp_pos t, exp_pos (-t)]

/-- **Log-sum-exp.** The `_LogDomain` sum-out computes `m + log Σ exp (x i - m)` with `m` the
largest `x i`. Model each `x i - m`, each `exp`, each addition of the sum (in any order and
association), the `log` and the final `m + _` as one rounding with relative error `u`, and let
every `x i` lie within `D` of `m`. With `n` terms, `ρ = (1 + u) ^ n * exp (u D) - 1 < 1` and
`λ = -log (1 - ρ)`, the computed value is within
`u |exact| + (1 + u) (u (log n + λ) + λ)` of the exact one: an absolute bound on the log scale,
which is a relative bound of about `exp` of it on the probability scale. -/
theorem logSumExp_forward_error (hu : 0 ≤ u) {ι : Type} (l : List ι) (x : ι → ℝ) (m D : ℝ)
    (hm : ∀ i ∈ l, x i ≤ m) (hpeak : ∃ i ∈ l, x i = m) (hD : ∀ i ∈ l, m - x i ≤ D)
    (d e : ι → ℝ) (hd : ∀ i ∈ l, Rounded u (x i - m) (d i))
    (he : ∀ i ∈ l, Rounded u (exp (d i)) (e i)) (S : ℝ) (hS : CompSum u e l S)
    (L : ℝ) (hL : Rounded u (log S) L) (r : ℝ) (hr : Rounded u (m + L) r)
    (hρ : (1 + u) ^ l.length * exp (u * D) - 1 < 1) :
    |r - (m + log (l.map fun i => exp (x i - m)).sum)| ≤
      u * |m + log (l.map fun i => exp (x i - m)).sum| +
        (1 + u) * (u * (log l.length + -log (1 - ((1 + u) ^ l.length * exp (u * D) - 1))) +
          -log (1 - ((1 + u) ^ l.length * exp (u * D) - 1))) := by
  set n := l.length with hn
  set ρ := (1 + u) ^ n * exp (u * D) - 1 with hρdef
  set lam := -log (1 - ρ) with hlam
  set T := (l.map fun i => exp (x i - m)).sum with hT
  obtain ⟨i0, hi0, hxi0⟩ := hpeak
  have hD0 : 0 ≤ D := by have := hD i0 hi0; rw [hxi0] at this; linarith
  have hne : l ≠ [] := List.ne_nil_of_mem hi0
  have hn1 : 1 ≤ n := List.length_pos_iff.mpr hne
  -- the exact sum lies in `[1, n]`
  have hT1 : 1 ≤ T := by
    have := List.single_le_sum (l := l.map fun i => exp (x i - m))
      (fun z hz => by obtain ⟨i, -, rfl⟩ := List.mem_map.mp hz; exact (exp_pos _).le)
      (exp (x i0 - m)) (List.mem_map.mpr ⟨i0, hi0, rfl⟩)
    rw [hxi0, sub_self, exp_zero] at this; exact this
  have hTn : T ≤ n := by
    have := List.sum_le_card_nsmul (l.map fun i => exp (x i - m)) 1
      (fun z hz => by
        obtain ⟨i, hi, rfl⟩ := List.mem_map.mp hz
        exact exp_le_one_iff.mpr (by linarith [hm i hi]))
    simpa [hn] using this
  -- each computed term
  have hterm : ∀ i ∈ l, RelWithin ((1 + u) * exp (u * D) - 1) (exp (x i - m)) (e i) := by
    intro i hi
    have hdi := (rounded_iff hu _ _).mp (hd i hi)
    have hlocal : RelWithin (exp (u * D) - 1) (exp (x i - m)) (exp (d i)) := by
      unfold RelWithin
      rw [show exp (d i) - exp (x i - m) = exp (x i - m) * (exp (d i - (x i - m)) - 1) by
        rw [mul_sub, ← exp_add]; ring_nf, abs_mul, abs_of_pos (exp_pos _), mul_comm]
      apply mul_le_mul_of_nonneg_right _ (exp_pos _).le
      refine (abs_exp_sub_one_le _).trans ?_
      have : |d i - (x i - m)| ≤ u * D := by
        refine hdi.trans (mul_le_mul_of_nonneg_left ?_ hu)
        rw [abs_of_nonpos (by linarith [hm i hi])]; linarith [hD i hi]
      linarith [exp_le_exp.mpr this]
    have := hlocal.round (exp_pos _).le hu (he i hi)
    simpa [add_sub_cancel] using this
  have he0 : 0 ≤ (1 + u) * exp (u * D) - 1 := by
    have : 1 ≤ exp (u * D) := one_le_exp (mul_nonneg hu hD0)
    nlinarith
  -- the computed sum
  have hsum : RelWithin ρ T S := by
    rcases hS with ⟨rfl, -⟩ | ⟨t, hp, ht⟩
    · exact absurd rfl hne
    · have h1 := ht.within_rel hu he0 (y := fun i => exp (x i - m))
        (fun i hi => ⟨(exp_pos _).le, hterm i (hp.subset hi)⟩)
      rw [(hp.map _).sum_eq] at h1
      have hlen := t.height_add_one_le
      rw [hp.length_eq] at hlen
      refine h1.mono ?_ (by linarith)
      rw [hρdef, show (1 + u) ^ n * exp (u * D) = (1 + u) ^ (n - 1) * ((1 + u) * exp (u * D)) by
        rw [← mul_assoc, ← pow_succ, Nat.sub_add_cancel hn1]]
      have : (1 + u) ^ t.height ≤ (1 + u) ^ (n - 1) :=
        pow_le_pow_right₀ (by linarith) (by omega)
      have h2 : 0 ≤ 1 + ((1 + u) * exp (u * D) - 1) := by linarith
      nlinarith
  -- the log of the computed sum
  have hρ0 : 0 ≤ ρ := by
    have : 1 ≤ (1 + u) ^ n := one_le_pow₀ (by linarith)
    have : 1 ≤ exp (u * D) := one_le_exp (mul_nonneg hu hD0)
    rw [hρdef]; nlinarith
  obtain ⟨hS1, hS2⟩ := abs_le.mp hsum
  have hSpos : 0 < S := by nlinarith
  have hlog : |log S - log T| ≤ lam := by
    have hTpos : 0 < T := by linarith
    have h1ρ : 0 < 1 - ρ := by linarith
    rw [← log_div hSpos.ne' hTpos.ne']
    have hlo : 1 - ρ ≤ S / T := by rw [le_div_iff₀ hTpos]; linarith
    have hhi : S / T ≤ 1 + ρ := by rw [div_le_iff₀ hTpos]; linarith
    have hl1 : log (1 - ρ) ≤ -ρ := by linarith [log_le_sub_one_of_pos h1ρ]
    rw [abs_le]
    constructor
    · rw [hlam]; linarith [log_le_log h1ρ hlo]
    · have := log_le_sub_one_of_pos (show 0 < S / T by positivity)
      rw [hlam]; linarith
  have hlogT : 0 ≤ log T ∧ log T ≤ log n := ⟨log_nonneg hT1, log_le_log (by linarith) hTn⟩
  have hL' := (rounded_iff hu _ _).mp hL
  have hLT : |L - log T| ≤ u * (log n + lam) + lam := by
    calc |L - log T| ≤ |L - log S| + |log S - log T| := abs_sub_le _ _ _
      _ ≤ u * |log S| + lam := add_le_add hL' hlog
      _ ≤ u * (log n + lam) + lam := by
          gcongr
          calc |log S| ≤ |log T| + |log S - log T| := by
                have := abs_add_le (log T) (log S - log T); simpa using this
            _ ≤ log n + lam := by rw [abs_of_nonneg hlogT.1]; linarith [hlogT.2]
  have hr' := (rounded_iff hu _ _).mp hr
  calc |r - (m + log T)| ≤ |r - (m + L)| + |L - log T| := by
        have := abs_add_le (r - (m + L)) (L - log T); ring_nf at this ⊢; linarith
    _ ≤ u * |m + L| + |L - log T| := by linarith
    _ ≤ u * (|m + log T| + |L - log T|) + |L - log T| := by
        gcongr
        have := abs_add_le (m + log T) (L - log T); ring_nf at this ⊢; linarith
    _ = u * |m + log T| + (1 + u) * |L - log T| := by ring
    _ ≤ _ := by gcongr

end LogSumExp

end BayesianNetworksProofs.ErrorBounds
