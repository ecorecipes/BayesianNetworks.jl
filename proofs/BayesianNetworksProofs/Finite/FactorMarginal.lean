import BayesianNetworksProofs.Finite.Assignments
import BayesianNetworksProofs.Finite.VariableElimination
import Mathlib.Data.List.Forall2
import Mathlib.Algebra.Order.BigOperators.Group.Finset

/-!
# Scoped factor marginalization

`project` sums only the factor coordinates being removed, not the full joint state space.
The private-variable replacement law is the algebra used in junction-tree message passing.
It permits arbitrary real entries; nonnegativity is needed later only for posterior semantics.
-/

set_option autoImplicit false

namespace BayesianNetworksProofs.FinBayesNet.Factor

noncomputable section
variable {bn : FinBayesNet}

def unit : Factor bn ℝ where
  scope := ∅
  value _ := 1
  dependsOn := fun _ _ _ => rfl

def multiply (f g : Factor bn ℝ) : Factor bn ℝ where
  scope := f.scope ∪ g.scope
  value x := f.value x * g.value x
  dependsOn x y h := by
    rw [f.dependsOn x y (fun v hv => h v (Finset.mem_union_left _ hv)),
      g.dependsOn x y (fun v hv => h v (Finset.mem_union_right _ hv))]

def combine : List (Factor bn ℝ) → Factor bn ℝ
  | [] => unit
  | f :: fs => multiply f (combine fs)

@[ext] theorem ext {f g : Factor bn ℝ} (hs : f.scope = g.scope) (hv : f.value = g.value) :
    f = g := by
  cases f
  cases g
  cases hs
  cases hv
  rfl

theorem multiply_comm (f g : Factor bn ℝ) : multiply f g = multiply g f := by
  apply ext
  · exact Finset.union_comm _ _
  · funext x
    exact mul_comm _ _

theorem multiply_assoc (f g h : Factor bn ℝ) :
    multiply (multiply f g) h = multiply f (multiply g h) := by
  apply ext
  · exact Finset.union_assoc _ _ _
  · funext x
    exact mul_assoc _ _ _

theorem unit_multiply (f : Factor bn ℝ) : multiply unit f = f := by
  apply ext
  · simp [multiply, unit]
  · funext x
    simp [multiply, unit]

theorem multiply_unit (f : Factor bn ℝ) : multiply f unit = f := by
  rw [multiply_comm, unit_multiply]

theorem multiply_left_comm (f g h : Factor bn ℝ) :
    multiply f (multiply g h) = multiply g (multiply f h) := by
  rw [← multiply_assoc, multiply_comm f g, multiply_assoc]

instance : Std.Associative (multiply (bn := bn)) := ⟨multiply_assoc⟩
instance : Std.Commutative (multiply (bn := bn)) := ⟨multiply_comm⟩

theorem combine_value (fs : List (Factor bn ℝ)) : (combine fs).value = product fs := by
  induction fs with
  | nil => rfl
  | cons f fs ih =>
    funext x
    change f.value x * (combine fs).value x = f.value x * product fs x
    rw [ih]

theorem combine_scope (fs : List (Factor bn ℝ)) : (combine fs).scope = jointScope fs := by
  induction fs with
  | nil => rfl
  | cons f fs ih => exact congrArg (fun S => f.scope ∪ S) ih

def project (Q : Finset bn.V) (f : Factor bn ℝ) : Factor bn ℝ where
  scope := f.scope ∩ Q
  value x := ∑ a : PartialAssignment bn (f.scope \ Q), f.value (patch (f.scope \ Q) x a)
  dependsOn x y h := by
    apply Finset.sum_congr rfl
    intro a _
    apply f.dependsOn
    intro v hv
    by_cases he : v ∈ f.scope \ Q
    · simp [patch, he]
    · have hq : v ∈ Q := by
        by_contra hq
        exact he (Finset.mem_sdiff.2 ⟨hv, hq⟩)
      simpa [patch, he] using h v (Finset.mem_inter.2 ⟨hv, hq⟩)

theorem project_value (Q : Finset bn.V) (f : Factor bn ℝ) (x : bn.Assignment) :
    (project Q f).value x = marg (f.scope \ Q) f.value x :=
  sum_partial_eq_marg _ _ _

theorem project_of_scope {Q : Finset bn.V} (f : Factor bn ℝ) (h : f.scope ⊆ Q) :
    project Q f = f := by
  apply ext
  · exact Finset.inter_eq_left.2 h
  · funext x
    rw [project_value, Finset.sdiff_eq_empty_iff_subset.2 h, marg_empty]

theorem project_nonnegative (Q : Finset bn.V) (f : Factor bn ℝ)
    (h : ∀ x, 0 ≤ f.value x) : ∀ x, 0 ≤ (project Q f).value x := by
  intro x
  exact Finset.sum_nonneg fun a _ => h _

theorem private_factor_constant (S : Finset bn.V) (g : Factor bn ℝ)
    (h : Disjoint S g.scope) (x y : bn.Assignment) (hy : y ∈ fibre S x) :
    g.value y = g.value x :=
  g.dependsOn y x (fun v hv => mem_fibre.1 hy v
    (fun hs => Finset.disjoint_left.1 h hs hv))

def marginal (S : Finset bn.V) (f : Factor bn ℝ) : Factor bn ℝ where
  scope := f.scope \ S
  value x := ∑ a : PartialAssignment bn S, f.value (patch S x a)
  dependsOn x y h := by
    apply Finset.sum_congr rfl
    intro a _
    apply f.dependsOn
    intro v hv
    by_cases hs : v ∈ S
    · simp [patch, hs]
    · simpa [patch, hs] using h v (Finset.mem_sdiff.2 ⟨hv, hs⟩)

theorem marginal_value (S : Finset bn.V) (f : Factor bn ℝ) (x : bn.Assignment) :
    (marginal S f).value x = marg S f.value x := sum_partial_eq_marg _ _ _

theorem marg_product_disjoint (S T : Finset bn.V) (f g : Factor bn ℝ)
    (hST : Disjoint S T) (hTf : Disjoint T f.scope) (hSg : Disjoint S g.scope)
    (x : bn.Assignment) :
    marg (S ∪ T) (multiply f g).value x = marg S f.value x * marg T g.value x := by
  rw [marg_union_disjoint hST]
  have hinner : ∀ y, marg T (multiply f g).value y = f.value y * (marginal T g).value y := by
    intro y
    rw [marginal_value]
    exact marg_mul_left (fun z hz => private_factor_constant T f hTf y z hz)
  simp_rw [hinner]
  have hg : Disjoint S (marginal T g).scope := hSg.mono_right Finset.sdiff_subset
  unfold marg
  rw [Finset.sum_mul]
  apply Finset.sum_congr rfl
  intro y hy
  dsimp only
  rw [private_factor_constant S (marginal T g) hg x y hy, marginal_value]
  rfl

/-- Sum private variables inside one factor before combining it with the remaining factors.
This is the actual message-passing replacement law, with only structural scope conditions. -/
theorem project_private (Q C : Finset bn.V) (f g : Factor bn ℝ)
    (h : Disjoint (f.scope \ C) (g.scope ∪ Q)) :
    project Q (multiply f g) = project Q (multiply (project C f) g) := by
  let E := f.scope \ C
  let T := ((f.scope ∩ C) ∪ g.scope) \ Q
  have he : (f.scope ∪ g.scope) \ Q = T ∪ E := by
    ext v
    have hd := Finset.disjoint_left.1 h
    by_cases hf : v ∈ f.scope <;> by_cases hg : v ∈ g.scope <;>
      by_cases hc : v ∈ C <;> by_cases hq : v ∈ Q <;> simp_all [T, E]
  have hdis : Disjoint T E := by
    rw [Finset.disjoint_left]
    intro v hv he
    have hf := Finset.mem_sdiff.1 he
    have ht := Finset.mem_union.1 (Finset.mem_sdiff.1 hv).1
    rcases ht with ht | ht
    · exact hf.2 (Finset.mem_inter.1 ht).2
    · exact Finset.disjoint_left.1 h he (Finset.mem_union_left _ ht)
  have hg : Disjoint E g.scope := h.mono_right Finset.subset_union_left
  apply ext
  · ext v
    have hd := Finset.disjoint_left.1 h
    by_cases hf : v ∈ f.scope <;> by_cases hg : v ∈ g.scope <;>
      by_cases hc : v ∈ C <;> by_cases hq : v ∈ Q <;>
      simp_all [project, multiply]
  · funext x
    rw [project_value, project_value]
    change marg ((f.scope ∪ g.scope) \ Q) (fun y => f.value y * g.value y) x =
      marg T (fun y => (project C f).value y * g.value y) x
    rw [he, marg_union_disjoint hdis]
    apply congrArg (fun F => marg T F x)
    funext y
    rw [project_value]
    unfold marg
    rw [Finset.sum_mul]
    apply Finset.sum_congr rfl
    intro z hz
    dsimp only
    rw [private_factor_constant E g hg y z hz]

theorem project_project (P Q : Finset bn.V) (f : Factor bn ℝ)
    (h : f.scope ∩ P ⊆ Q) : project P (project Q f) = project P f := by
  have hd : Disjoint (f.scope \ Q) (unit.scope ∪ P) := by
    apply Finset.disjoint_left.2
    intro v hv hp
    have hP : v ∈ P := by simpa [unit] using hp
    exact (Finset.mem_sdiff.1 hv).2 (h (Finset.mem_inter.2 ⟨(Finset.mem_sdiff.1 hv).1, hP⟩))
  have he := project_private P Q f unit hd
  simpa only [multiply_unit] using he.symm

theorem project_inter (P Q : Finset bn.V) (f : Factor bn ℝ) (h : f.scope ∩ P ⊆ Q) :
    project P f = project (P ∩ Q) f := by
  have hscope : f.scope ∩ P = f.scope ∩ (P ∩ Q) := by
    ext v
    constructor
    · intro hv
      exact Finset.mem_inter.2 ⟨(Finset.mem_inter.1 hv).1,
        Finset.mem_inter.2 ⟨(Finset.mem_inter.1 hv).2, h hv⟩⟩
    · intro hv
      exact Finset.mem_inter.2 ⟨(Finset.mem_inter.1 hv).1,
        (Finset.mem_inter.1 (Finset.mem_inter.1 hv).2).1⟩
  have he : f.scope \ P = f.scope \ (P ∩ Q) := by
    ext v
    constructor
    · intro hv
      exact Finset.mem_sdiff.2 ⟨(Finset.mem_sdiff.1 hv).1,
        fun hi => (Finset.mem_sdiff.1 hv).2 (Finset.mem_inter.1 hi).1⟩
    · intro hv
      refine Finset.mem_sdiff.2 ⟨(Finset.mem_sdiff.1 hv).1, ?_⟩
      intro hp
      exact (Finset.mem_sdiff.1 hv).2
        (Finset.mem_inter.2 ⟨hp, h (Finset.mem_inter.2 ⟨(Finset.mem_sdiff.1 hv).1, hp⟩)⟩)
  apply ext hscope
  funext x
  rw [project_value, project_value, he]

/-- Independent private coordinates can be summed in separate factors. Shared coordinates
must be retained, which is exactly the structural separator condition. -/
theorem project_multiply (Q : Finset bn.V) (f g : Factor bn ℝ)
    (h : f.scope ∩ g.scope ⊆ Q) :
    project Q (multiply f g) = multiply (project Q f) (project Q g) := by
  have hf : Disjoint (f.scope \ Q) (g.scope ∪ Q) := by
    apply Finset.disjoint_left.2
    intro v hv hg
    rcases Finset.mem_union.1 hg with hg | hq
    · exact (Finset.mem_sdiff.1 hv).2 (h (Finset.mem_inter.2 ⟨(Finset.mem_sdiff.1 hv).1, hg⟩))
    · exact (Finset.mem_sdiff.1 hv).2 hq
  have hg : Disjoint (g.scope \ Q) ((project Q f).scope ∪ Q) := by
    apply Finset.disjoint_left.2
    intro v hv hf
    have hq : v ∈ Q := (Finset.mem_union.1 hf).elim (fun h => (Finset.mem_inter.1 h).2) id
    exact (Finset.mem_sdiff.1 hv).2 hq
  rw [project_private Q Q f g hf, multiply_comm (project Q f) g,
    project_private Q Q g (project Q f) hg,
    project_of_scope _ (Finset.union_subset Finset.inter_subset_right Finset.inter_subset_right),
    multiply_comm]

end
end BayesianNetworksProofs.FinBayesNet.Factor
