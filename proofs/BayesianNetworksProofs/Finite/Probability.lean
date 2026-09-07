import BayesianNetworksProofs.Finite.Intervention
import BayesianNetworksProofs.Finite.Tensor
import Mathlib.Data.NNReal.Defs

/-!
# BayesianNetworksProofs.Finite.Probability

The finite model instantiated at `ℝ≥0`, the value semiring of `FiniteKernel{Float64}` tables in
`MarkovCategories.jl` (non-negative weights). Everything in `Finite/` is proved for an arbitrary
commutative semiring; these corollaries just fix `R := ℝ≥0` so that the statements read as
statements about probability distributions.
-/

namespace BayesianNetworksProofs

namespace FinBayesNet

open scoped NNReal

/-- A family of non-negative real conditional kernels. -/
abbrev ProbKernel (bn : FinBayesNet) := bn.Kernel ℝ≥0

variable {bn : FinBayesNet}

/-- Proposition 1a over `ℝ≥0`: the joint of a closed, acyclic network with normalised local
kernels is a probability distribution on assignments. -/
theorem sum_joint_eq_one_nnreal (κ : bn.ProbKernel) (hclosed : bn.Closed) (ord : bn.TopoOrder)
    (hloc : ∀ m, Local κ m) (hnorm : ∀ m, Normalised κ m) : ∑ x, joint κ x = 1 :=
  sum_joint_eq_one κ hclosed ord hloc hnorm

/-- Proposition 4 over `ℝ≥0`: `do(target m₀ = a)` truncates the factorisation. -/
theorem joint_intervene_nnreal (κ : bn.ProbKernel) (m₀ : bn.M) (a : bn.states (bn.target m₀))
    (x : bn.Assignment) :
    joint (intervene κ m₀ a) x =
      (if x (bn.target m₀) = a then 1 else 0) *
        ∏ m ∈ Finset.univ.erase m₀, κ m x (x (bn.target m)) :=
  joint_intervene κ m₀ a x

end FinBayesNet

end BayesianNetworksProofs
