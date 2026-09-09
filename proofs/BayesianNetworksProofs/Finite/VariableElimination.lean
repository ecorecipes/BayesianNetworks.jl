import BayesianNetworksProofs.Finite.Evaluation
import Mathlib.Data.List.Pairwise

/-!
# BayesianNetworksProofs.Finite.VariableElimination

**Bucket variable elimination preserves the exact marginal** (SPEC §15–§17, §55.3).

A factor has a finite scope and a value depending only on that scope. Eliminating a variable
multiplies only the factors whose scopes contain it, sums that bucket over the variable, and
retains all other factors. We prove this actual bucket operation equals the full-enumeration
one-variable marginal. Iteration along a duplicate-free list equals the marginal over the
whole list, so elimination order does not change the result.

The arithmetic is over any commutative semiring. No positivity or division is used. The
result is an **unnormalised** marginal: normalising evidence of zero total weight remains
undefined in probability theory and is not justified by this theorem.

This is a scoped finite-function algorithm and an oracle theorem, not a verified Julia array
implementation, not a junction-tree theorem, and not decision-variable elimination.
-/

set_option autoImplicit false

namespace BayesianNetworksProofs.FinBayesNet

variable {bn : FinBayesNet} {R : Type} [CommSemiring R]

/-- A scalar factor together with a sufficient (not necessarily minimal) dependency scope. -/
structure Factor (bn : FinBayesNet) (R : Type) where
  scope : Finset bn.V
  value : bn.Assignment → R
  dependsOn : ∀ x y, (∀ v ∈ scope, x v = y v) → value x = value y

namespace Factor

/-- Product of a list of factors, keeping repeated factors and their multiplicities. -/
def product (fs : List (Factor bn R)) (x : bn.Assignment) : R :=
  (fs.map fun f => f.value x).prod

theorem product_nil (x : bn.Assignment) : product ([] : List (Factor bn R)) x = 1 := rfl

theorem product_cons (f : Factor bn R) (fs : List (Factor bn R)) (x : bn.Assignment) :
    product (f :: fs) x = f.value x * product fs x := rfl

/-- The union of all factor scopes. -/
def jointScope (fs : List (Factor bn R)) : Finset bn.V :=
  fs.foldr (fun f S => f.scope ∪ S) ∅

theorem product_local (fs : List (Factor bn R)) (x y : bn.Assignment)
    (h : ∀ v ∈ jointScope fs, x v = y v) : product fs x = product fs y := by
  induction fs with
  | nil => rfl
  | cons f fs ih =>
    rw [product_cons, product_cons, f.dependsOn x y (fun v hv => h v (Finset.mem_union_left _ hv)),
      ih (fun v hv => h v (Finset.mem_union_right _ hv))]

/-- Multiply an entire bucket and sum its distinguished variable out. -/
def sumBucket (v : bn.V) (fs : List (Factor bn R)) : Factor bn R where
  scope := (jointScope fs).erase v
  value x := ∑ a : bn.states v, product fs (Function.update x v a)
  dependsOn x y h := by
    refine Finset.sum_congr rfl fun a _ => ?_
    apply product_local
    intro w hw
    by_cases he : w = v
    · subst w
      simp
    · simp only [Function.update_of_ne he]
      exact h w (Finset.mem_erase.2 ⟨he, hw⟩)

/-- The bucket is selected by membership in a factor's scope, not by factor position. -/
def bucket (v : bn.V) (fs : List (Factor bn R)) : List (Factor bn R) :=
  fs.filter (fun f => decide (v ∈ f.scope))

/-- Factors not containing the eliminated variable. -/
def outside (v : bn.V) (fs : List (Factor bn R)) : List (Factor bn R) :=
  fs.filter (fun f => decide (v ∉ f.scope))

theorem product_partition (v : bn.V) (fs : List (Factor bn R)) (x : bn.Assignment) :
    product fs x = product (outside v fs) x * product (bucket v fs) x := by
  induction fs with
  | nil => simp [outside, bucket, product]
  | cons f fs ih =>
    by_cases hv : v ∈ f.scope <;>
      simp [outside, bucket, product, hv] at * <;> rw [ih] <;> ac_rfl

theorem outside_update (v : bn.V) (fs : List (Factor bn R))
    (x : bn.Assignment) (a : bn.states v) :
    product (outside v fs) (Function.update x v a) = product (outside v fs) x := by
  unfold product
  apply congrArg List.prod
  apply List.map_congr_left
  intro f hf
  have hv : v ∉ f.scope := by simpa [outside] using (List.mem_filter.1 hf).2
  apply f.dependsOn
  intro w hw
  have hne : w ≠ v := fun he => hv (he ▸ hw)
  rw [Function.update_of_ne hne]

/-- Replace one bucket by its marginal, preserving every factor outside it. -/
def eliminate (v : bn.V) (fs : List (Factor bn R)) : List (Factor bn R) :=
  sumBucket v (bucket v fs) :: outside v fs

/-- **One elimination step equals brute-force marginalisation**, even with overlapping scopes,
repeated factors, and variables absent from all scopes. -/
theorem eliminate_correct (v : bn.V) (fs : List (Factor bn R)) (x : bn.Assignment) :
    product (eliminate v fs) x = marg {v} (product fs) x := by
  rw [show ({v} : Finset bn.V) = insert v ∅ from rfl, marg_insert (by simp)]
  simp only [marg_empty]
  change (∑ a : bn.states v, product (bucket v fs) (Function.update x v a)) *
    product (outside v fs) x = _
  rw [Finset.sum_mul]
  refine Finset.sum_congr rfl fun a _ => ?_
  rw [product_partition v fs, outside_update, mul_comm]

/-- Successive bucket eliminations. -/
def eliminateAll (fs : List (Factor bn R)) : List bn.V → List (Factor bn R)
  | [] => fs
  | v :: vs => eliminateAll (eliminate v fs) vs

/-- **Variable-elimination oracle theorem.** A duplicate-free elimination order computes exactly
the full joint product summed over those variables. -/
theorem eliminateAll_correct (fs : List (Factor bn R)) (vs : List bn.V) (hvs : vs.Nodup)
    (x : bn.Assignment) :
    product (eliminateAll fs vs) x = marg vs.toFinset (product fs) x := by
  induction vs generalizing fs with
  | nil => simp [eliminateAll, marg_empty]
  | cons v vs ih =>
    have hv : v ∉ vs.toFinset := by simpa using (List.nodup_cons.1 hvs).1
    rw [eliminateAll, ih _ (List.nodup_cons.1 hvs).2]
    have he : product (eliminate v fs) = marg {v} (product fs) :=
      funext (eliminate_correct v fs)
    rw [he, ← marg_union_disjoint (Finset.disjoint_singleton_right.2 hv)]
    simp

/-- Any two duplicate-free orders eliminating the same variables have the same marginal. -/
theorem eliminateAll_order_independent (fs : List (Factor bn R)) (vs ws : List bn.V)
    (hvs : vs.Nodup) (hws : ws.Nodup) (hset : vs.toFinset = ws.toFinset) :
    product (eliminateAll fs vs) = product (eliminateAll fs ws) := by
  funext x
  rw [eliminateAll_correct fs vs hvs, eliminateAll_correct fs ws hws, hset]

/-- Compile one local mechanism into a factor on its parents and child. -/
def mechanism (κ : bn.Kernel R) (hloc : ∀ m, Local κ m) (m : bn.M) : Factor bn R where
  scope := insert (bn.target m) (bn.parents m)
  value x := κ m x (x (bn.target m))
  dependsOn x y h := by
    rw [hloc m x y (fun v hv => h v (Finset.mem_insert_of_mem hv)),
      h (bn.target m) (Finset.mem_insert_self _ _)]

/-- Compile all mechanisms, retaining each mechanism exactly once. -/
noncomputable def ofKernel (κ : bn.Kernel R) (hloc : ∀ m, Local κ m) : List (Factor bn R) :=
  Finset.univ.toList.map (mechanism κ hloc)

theorem product_ofKernel (κ : bn.Kernel R) (hloc : ∀ m, Local κ m) :
    product (ofKernel κ hloc) = joint κ := by
  funext x
  simp [product, ofKernel, mechanism, joint, List.map_map]

/-- The bucket algorithm on compiled Bayesian-network factors computes the exact joint
marginal. Closedness and stochasticity are needed for a probability interpretation, not for
this semiring identity. -/
theorem eliminateAll_joint (κ : bn.Kernel R) (hloc : ∀ m, Local κ m)
    (vs : List bn.V) (hvs : vs.Nodup) (x : bn.Assignment) :
    product (eliminateAll (ofKernel κ hloc) vs) x = marg vs.toFinset (joint κ) x := by
  rw [eliminateAll_correct _ vs hvs, product_ofKernel]

end Factor

end BayesianNetworksProofs.FinBayesNet
