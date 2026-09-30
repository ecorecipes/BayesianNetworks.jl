import BayesianNetworksProofs.Finite.NumericalContracts

/-!
# SA-Pass shadow module: the posterior input-perturbation contract

Claim `bn.posterior-error`, from `kernel_query_posterior_error`. The quoted prose promises
"input-perturbation and posterior L1 bounds with an explicit evidence-mass floor" without
saying how the bound scales. The theorem's bound and its smallness hypothesis both carry
`Fintype.card bn.Assignment`, the number of joint assignments (exponential in the number of
variables). A bound without that factor, `2 * (∑ m, ε m) / η`, does not follow: the forward
check leaves `2 * (card * ∑ m, ε m) / η ≤ 2 * (∑ m, ε m) / η` open. The shadows state the
bound as proved.
-/

namespace BayesianNetworksProofs.Shadows.PosteriorError

open BayesianNetworksProofs BayesianNetworksProofs.FinBayesNet BayesianNetworksProofs.Numerical
open BayesianNetworksProofs.FiniteDistribution

/-- The query posterior of `κ` under evidence `E = observed`, as an unnormalised weight over
the retained assignments divided by the evidence mass. -/
noncomputable abbrev post {bn : FinBayesNet} (κ : bn.Kernel ℝ) (Q E : Finset bn.V) (observed : bn.Assignment) :
    PartialAssignment bn Q → ℝ :=
  fun q => pushWeight (restrictTo Q) (likelihoodWeight (joint κ) E observed) q /
    mass (likelihoodWeight (joint κ) E observed)

/-- `kernel_query_posterior_error`, restated abstractly with every hypothesis. -/
abbrev Candidate : Prop :=
  ∀ (bn : FinBayesNet) (κ κ' : bn.Kernel ℝ),
    (∀ m x a, 0 ≤ κ m x a ∧ κ m x a ≤ 1) → (∀ m x a, 0 ≤ κ' m x a ∧ κ' m x a ≤ 1) →
    ∀ (ε : bn.M → ℝ), (∀ m x a, |κ m x a - κ' m x a| ≤ ε m) →
    ∀ (Q E : Finset bn.V) (observed : bn.Assignment) (η : ℝ), 0 < η →
    η ≤ mass (likelihoodWeight (joint κ) E observed) →
    (Fintype.card bn.Assignment : ℝ) * (∑ m, ε m) < η →
      0 < mass (likelihoodWeight (joint κ') E observed) ∧
        l1 (post κ Q E observed) (post κ' Q E observed) ≤
          2 * ((Fintype.card bn.Assignment : ℝ) * ∑ m, ε m) / η

/-- "with an explicit evidence-mass floor": when the exact evidence mass is at least `η` and
the kernel perturbation is small beside it, the perturbed evidence mass stays positive, so
the perturbed posterior exists. -/
abbrev Shadow1 : Prop :=
  ∀ (bn : FinBayesNet) (κ κ' : bn.Kernel ℝ),
    (∀ m x a, 0 ≤ κ m x a ∧ κ m x a ≤ 1) → (∀ m x a, 0 ≤ κ' m x a ∧ κ' m x a ≤ 1) →
    ∀ (ε : bn.M → ℝ), (∀ m x a, |κ m x a - κ' m x a| ≤ ε m) →
    ∀ (Q E : Finset bn.V) (observed : bn.Assignment) (η : ℝ), 0 < η →
    η ≤ mass (likelihoodWeight (joint κ) E observed) →
    (Fintype.card bn.Assignment : ℝ) * (∑ m, ε m) < η →
      0 < mass (likelihoodWeight (joint κ') E observed)

/-- "input-perturbation and posterior L1 bounds": per-mechanism kernel errors `ε m` bound the
L1 distance between the two query posteriors by `2 * card * ∑ ε / η`. -/
abbrev Shadow2 : Prop :=
  ∀ (bn : FinBayesNet) (κ κ' : bn.Kernel ℝ),
    (∀ m x a, 0 ≤ κ m x a ∧ κ m x a ≤ 1) → (∀ m x a, 0 ≤ κ' m x a ∧ κ' m x a ≤ 1) →
    ∀ (ε : bn.M → ℝ), (∀ m x a, |κ m x a - κ' m x a| ≤ ε m) →
    ∀ (Q E : Finset bn.V) (observed : bn.Assignment) (η : ℝ), 0 < η →
    η ≤ mass (likelihoodWeight (joint κ) E observed) →
    (Fintype.card bn.Assignment : ℝ) * (∑ m, ε m) < η →
      l1 (post κ Q E observed) (post κ' Q E observed) ≤
        2 * ((Fintype.card bn.Assignment : ℝ) * ∑ m, ε m) / η

theorem forward1 : Candidate → Shadow1 := by
  intro h bn κ κ' hκ hκ' ε herr Q E observed η hη hfloor hsmall
  exact (h bn κ κ' hκ hκ' ε herr Q E observed η hη hfloor hsmall).1

theorem forward2 : Candidate → Shadow2 := by
  intro h bn κ κ' hκ hκ' ε herr Q E observed η hη hfloor hsmall
  exact (h bn κ κ' hκ hκ' ε herr Q E observed η hη hfloor hsmall).2

theorem backward : Shadow1 → Shadow2 → Candidate := by
  intro h1 h2 bn κ κ' hκ hκ' ε herr Q E observed η hη hfloor hsmall
  exact ⟨h1 bn κ κ' hκ hκ' ε herr Q E observed η hη hfloor hsmall,
    h2 bn κ κ' hκ hκ' ε herr Q E observed η hη hfloor hsmall⟩

/-- SA-Pass anchor: the cited theorem proves `Candidate` as stated, so a restatement that
drifts from the proved theorem stops compiling. -/
theorem anchor : Candidate := fun _ κ κ' hκ hκ' ε herr Q E observed η hη hfloor hsmall =>
  kernel_query_posterior_error κ κ' hκ hκ' ε herr Q E observed η hη hfloor hsmall

end BayesianNetworksProofs.Shadows.PosteriorError
