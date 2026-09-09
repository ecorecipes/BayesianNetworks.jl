import Mathlib.CategoryTheory.MarkovCategory.Basic
import Mathlib.CategoryTheory.CopyDiscardCategory.Deterministic

/-!
# BayesianNetworksProofs.Markov.Basic

Generic lemmas about Mathlib's abstract `CopyDiscardCategory` / `MarkovCategory` that the
`MarkovCategories.jl` / `BayesianNetworks.jl` tests mirror for the concrete finite-stochastic
instance (`@instance ThMarkovCategory{FiniteSpace,FiniteKernel}`):

* `discard_natural` — `f ≫ ε[Y] = ε[X]`: composing a kernel with `delete` is `delete`. In Julia
  this is the test "discard naturality holds iff the kernel is normalised"; it is the axiom that
  `ThMarkovCategory` adds on top of `ThMonoidalCategoryWithDiagonals`.
* `deterministic_comp` — the composite of two deterministic (copy-preserving) kernels is
  deterministic; in Julia, point-mass kernels compose to point-mass kernels.
* `state_discard` — a state `p : I → X` composed with discard is the identity of the unit
  (a normalised distribution has total mass one).

The concrete finite-stochastic instance is in the sibling `FiniteKernels.jl` proof project,
module `Theory/FinStoch.lean`; this module only uses Mathlib's abstract classes.
Mathlib's `Deterministic` is `IsComonHom`, whose composition instance already exists; the
theorem below simply names it.
-/

namespace BayesianNetworksProofs.Markov

open CategoryTheory MonoidalCategory CopyDiscardCategory ComonObj

universe v u

variable {C : Type u} [Category.{v} C] [MonoidalCategory.{v} C]

section Markov

variable [MarkovCategory C]

/-- Discard is natural: every morphism of a Markov category is "normalised". -/
theorem discard_natural {X Y : C} (f : X ⟶ Y) : f ≫ ε[Y] = ε[X] :=
  MarkovCategory.discard_natural f

/-- A state has total mass one: composing `p : I ⟶ X` with discard is the identity on `I`. -/
theorem state_discard {X : C} (p : 𝟙_ C ⟶ X) : p ≫ ε[X] = 𝟙 (𝟙_ C) := by
  rw [MarkovCategory.discard_natural, discard_unit]

end Markov

section CopyDiscard

variable [CopyDiscardCategory C]

/-- The composite of two deterministic morphisms is deterministic (Mathlib's `IsComonHom`
composition instance, named here for the Julia test `compose(δ_a, δ_b)` is a point mass). -/
theorem deterministic_comp {X Y Z : C} (f : X ⟶ Y) (g : Y ⟶ Z) [Deterministic f]
    [Deterministic g] : Deterministic (f ≫ g) :=
  inferInstance

/-- Identities are deterministic. -/
theorem deterministic_id (X : C) : Deterministic (𝟙 X) :=
  inferInstance

/-- Deterministic morphisms commute with copy: `f ≫ Δ = Δ ≫ (f ⊗ f)`. -/
theorem deterministic_copy {X Y : C} (f : X ⟶ Y) [Deterministic f] :
    f ≫ Δ[Y] = Δ[X] ≫ (f ⊗ₘ f) :=
  Deterministic.copy_natural f

/-- The comonoid laws every object satisfies (the Julia comonoid-law tests). -/
example (X : C) : Δ[X] ≫ (ε[X] ▷ X) = (λ_ X).inv := counit_comul X
example (X : C) : Δ[X] ≫ (X ◁ ε[X]) = (ρ_ X).inv := comul_counit X
example (X : C) : Δ[X] ≫ (X ◁ Δ[X]) = Δ[X] ≫ (Δ[X] ▷ X) ≫ (α_ X X X).hom := comul_assoc X

end CopyDiscard

end BayesianNetworksProofs.Markov
