import BayesianNetworksProofs.Finite.Open

/-!
# SA-Pass shadow module: the open-network closure theorem, rule 1

Claim `bn.closure`, from `composeNet_target_injective`.
-/

namespace BayesianNetworksProofs.Shadows.Closure

open BayesianNetworksProofs BayesianNetworksProofs.OpenFinBayesNet
open BayesianNetworksProofs.OpenFinBayesNet.Composable

/-- `composeNet_target_injective`, restated abstractly. -/
abbrev Candidate : Prop :=
  ∀ (A B : OpenFinBayesNet) (c : Composable A B),
    Function.Injective (composeNet c).target

/-- No two mechanisms inherited from `A` generate the same composite variable. -/
abbrev Shadow1 : Prop :=
  ∀ (A B : OpenFinBayesNet) (c : Composable A B) (m m' : A.M),
    (composeNet c).target (Sum.inl m) = (composeNet c).target (Sum.inl m') → m = m'

/-- Nor two inherited from `B`. -/
abbrev Shadow2 : Prop :=
  ∀ (A B : OpenFinBayesNet) (c : Composable A B) (m m' : B.M),
    (composeNet c).target (Sum.inr m) = (composeNet c).target (Sum.inr m') → m = m'

/-- And the two families never collide: a mechanism of `B` never targets a glued variable. -/
abbrev Shadow3 : Prop :=
  ∀ (A B : OpenFinBayesNet) (c : Composable A B) (m : A.M) (m' : B.M),
    (composeNet c).target (Sum.inl m) ≠ (composeNet c).target (Sum.inr m')

theorem forward1 : Candidate → Shadow1 := by
  intro h A B c m m' hm
  exact Sum.inl_injective (h A B c hm)

theorem forward2 : Candidate → Shadow2 := by
  intro h A B c m m' hm
  exact Sum.inr_injective (h A B c hm)

theorem forward3 : Candidate → Shadow3 := by
  intro h A B c m m' hm
  exact Sum.inl_ne_inr (h A B c hm)

theorem backward : Shadow1 → Shadow2 → Shadow3 → Candidate := by
  intro h1 h2 h3 A B c
  rintro (m | m) (m' | m') hm
  · exact congrArg Sum.inl (h1 A B c m m' hm)
  · exact absurd hm (h3 A B c m m')
  · exact absurd hm.symm (h3 A B c m' m)
  · exact congrArg Sum.inr (h2 A B c m m' hm)

end BayesianNetworksProofs.Shadows.Closure
