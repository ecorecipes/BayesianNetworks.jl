import BayesianNetworksProofs.Finite.VariableElimination

/-!
# SA-Pass shadow module: variable elimination, compilation and order independence

Claim `bn.ve-order`, from `eliminateAll_joint` and `eliminateAll_order_independent`.
-/

namespace BayesianNetworksProofs.Shadows.VEOrder

open BayesianNetworksProofs BayesianNetworksProofs.FinBayesNet
open BayesianNetworksProofs.FinBayesNet.Factor

/-- The two cited theorems, restated abstractly with every hypothesis. -/
abbrev Candidate : Prop :=
  (∀ (bn : FinBayesNet) (R : Type) [CommSemiring R] (κ : bn.Kernel R)
      (hloc : ∀ m, Local κ m) (vs : List bn.V), vs.Nodup → ∀ x : bn.Assignment,
      product (eliminateAll (ofKernel κ hloc) vs) x = marg vs.toFinset (joint κ) x) ∧
    ∀ (bn : FinBayesNet) (R : Type) [CommSemiring R] (fs : List (Factor bn R))
      (vs ws : List bn.V), vs.Nodup → ws.Nodup → vs.toFinset = ws.toFinset →
      product (eliminateAll fs vs) = product (eliminateAll fs ws)

/-- "agreement with the existing joint marginal, including compilation of local mechanisms":
eliminating a duplicate-free list from the compiled local mechanisms gives the joint's
marginal over those variables. -/
abbrev Shadow1 : Prop :=
  ∀ (bn : FinBayesNet) (R : Type) [CommSemiring R] (κ : bn.Kernel R)
    (hloc : ∀ m, Local κ m) (vs : List bn.V), vs.Nodup → ∀ x : bn.Assignment,
    product (eliminateAll (ofKernel κ hloc) vs) x = marg vs.toFinset (joint κ) x

/-- "independence of a duplicate-free elimination order": any two duplicate-free orders of the
same variables give the same result, for any factor list. -/
abbrev Shadow2 : Prop :=
  ∀ (bn : FinBayesNet) (R : Type) [CommSemiring R] (fs : List (Factor bn R))
    (vs ws : List bn.V), vs.Nodup → ws.Nodup → vs.toFinset = ws.toFinset →
    product (eliminateAll fs vs) = product (eliminateAll fs ws)

theorem forward1 : Candidate → Shadow1 := fun h => h.1

theorem forward2 : Candidate → Shadow2 := fun h => h.2

theorem backward : Shadow1 → Shadow2 → Candidate := fun h1 h2 => ⟨h1, h2⟩

/-- SA-Pass anchor: the cited theorems prove `Candidate` as stated, so a restatement that
drifts from the proved theorems stops compiling. -/
theorem anchor : Candidate :=
  ⟨fun _ _ _ κ hloc vs hvs x => eliminateAll_joint κ hloc vs hvs x,
   fun _ _ _ fs vs ws hvs hws hset => eliminateAll_order_independent fs vs ws hvs hws hset⟩

end BayesianNetworksProofs.Shadows.VEOrder
