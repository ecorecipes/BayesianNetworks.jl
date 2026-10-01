import BayesianNetworksProofs.Numeric.ErrorBounds

/-!
# SA-Pass shadow module: forward error of the variable-elimination posterior

Claim `bn.posterior-forward-error`, from `ve_posterior_forward_error`. The prose promises that,
for variable elimination over the compiled nonnegative CPT factors and the evidence indicator,
with every product, sum and division rounded in the standard model with `u ≥ 0`, in any order
and association, whenever the evidence mass is positive and `γ K < 1`:

1. the computed evidence mass is within relative `γ(K-1)` of the exact evidence mass;
2. every computed posterior entry is within relative `(1 + γ K)/(1 - γ K) - 1` of the exact
   posterior entry;

where `γ n = (1 + u)^n - 1` and `K` is the number of mechanisms plus the summed state counts of
the eliminated variables plus the number of query assignments.

The candidate carries every hypothesis of the theorem: nonnegative local kernels, a
duplicate-free elimination list whose set is the complement of the query, an approximate run
`Run` (products and sums in any order and association, each operation `Rounded u`), computed
query entries, a computed mass and rounded quotients, and an existing exact posterior
(`posterior = some d`, which is positive evidence mass). It names `γ`, `RelWithin` and the index
through `gamma`, `RelWithin` and `posteriorIndex`. The shadows spell all three out:
`(1 + u) ^ n - 1`, `|x - y| ≤ e * y` and `|M| + Σ_{v ∈ vs} |states v| + |query assignments|`, so a
change to any of those definitions fails the checkers.
-/

namespace BayesianNetworksProofs.Shadows.PosteriorForwardError

open BayesianNetworksProofs BayesianNetworksProofs.ErrorBounds BayesianNetworksProofs.FinBayesNet
  BayesianNetworksProofs.FinBayesNet.Factor BayesianNetworksProofs.FiniteDistribution

/-- `ve_posterior_forward_error`, restated abstractly with all its hypotheses. -/
abbrev Candidate : Prop :=
  ∀ (bn : FinBayesNet) (u : ℝ), 0 ≤ u →
  ∀ (κ : bn.Kernel ℝ) (hloc : ∀ m, Local κ m) (hκ : ∀ m x a, 0 ≤ κ m x a)
    (Q E : Finset bn.V) (observed : bn.Assignment) (vs : List bn.V),
    vs.Nodup → vs.toFinset = Qᶜ →
  ∀ out : List (Computed bn),
    Run u (inputs (evidenceFactor E observed :: ofKernel κ hloc)) vs out →
  ∀ (base : bn.Assignment) (num : PartialAssignment bn Q → ℝ),
    (∀ q, CompProd u (fun p : Computed bn => p.2 (patch Q base q)) out (num q)) →
  ∀ Z : ℝ, CompSum u num Finset.univ.toList Z →
  ∀ post : PartialAssignment bn Q → ℝ, (∀ q, Rounded u (num q / Z) (post q)) →
  ∀ d : Distribution (PartialAssignment bn Q),
    posterior Q E observed (joint κ) (joint_nonneg κ hκ) = some d →
    gamma u (posteriorIndex bn Q vs) < 1 →
    RelWithin (gamma u (posteriorIndex bn Q vs - 1))
        (mass (likelihoodWeight (joint κ) E observed)) Z ∧
      ∀ q, RelWithin ((1 + gamma u (posteriorIndex bn Q vs)) /
        (1 - gamma u (posteriorIndex bn Q vs)) - 1) (d.pmf q) (post q)

/-- "the computed evidence mass is within relative `γ(K-1)` of the exact evidence mass", with
`γ` and `K` spelled out. -/
abbrev Shadow1 : Prop :=
  ∀ (bn : FinBayesNet) (u : ℝ), 0 ≤ u →
  ∀ (κ : bn.Kernel ℝ) (hloc : ∀ m, Local κ m) (hκ : ∀ m x a, 0 ≤ κ m x a)
    (Q E : Finset bn.V) (observed : bn.Assignment) (vs : List bn.V),
    vs.Nodup → vs.toFinset = Qᶜ →
  ∀ out : List (Computed bn),
    Run u (inputs (evidenceFactor E observed :: ofKernel κ hloc)) vs out →
  ∀ (base : bn.Assignment) (num : PartialAssignment bn Q → ℝ),
    (∀ q, CompProd u (fun p : Computed bn => p.2 (patch Q base q)) out (num q)) →
  ∀ Z : ℝ, CompSum u num Finset.univ.toList Z →
  ∀ post : PartialAssignment bn Q → ℝ, (∀ q, Rounded u (num q / Z) (post q)) →
  ∀ d : Distribution (PartialAssignment bn Q),
    posterior Q E observed (joint κ) (joint_nonneg κ hκ) = some d →
    (1 + u) ^ (Fintype.card bn.M + (vs.map fun v => Fintype.card (bn.states v)).sum +
      Fintype.card (PartialAssignment bn Q)) - 1 < 1 →
    |Z - mass (likelihoodWeight (joint κ) E observed)| ≤
      ((1 + u) ^ (Fintype.card bn.M + (vs.map fun v => Fintype.card (bn.states v)).sum +
        Fintype.card (PartialAssignment bn Q) - 1) - 1) *
        mass (likelihoodWeight (joint κ) E observed)

/-- "every computed posterior entry is within relative `(1 + γ K)/(1 - γ K) - 1` of the exact
posterior entry", with `γ` and `K` spelled out. -/
abbrev Shadow2 : Prop :=
  ∀ (bn : FinBayesNet) (u : ℝ), 0 ≤ u →
  ∀ (κ : bn.Kernel ℝ) (hloc : ∀ m, Local κ m) (hκ : ∀ m x a, 0 ≤ κ m x a)
    (Q E : Finset bn.V) (observed : bn.Assignment) (vs : List bn.V),
    vs.Nodup → vs.toFinset = Qᶜ →
  ∀ out : List (Computed bn),
    Run u (inputs (evidenceFactor E observed :: ofKernel κ hloc)) vs out →
  ∀ (base : bn.Assignment) (num : PartialAssignment bn Q → ℝ),
    (∀ q, CompProd u (fun p : Computed bn => p.2 (patch Q base q)) out (num q)) →
  ∀ Z : ℝ, CompSum u num Finset.univ.toList Z →
  ∀ post : PartialAssignment bn Q → ℝ, (∀ q, Rounded u (num q / Z) (post q)) →
  ∀ d : Distribution (PartialAssignment bn Q),
    posterior Q E observed (joint κ) (joint_nonneg κ hκ) = some d →
    (1 + u) ^ (Fintype.card bn.M + (vs.map fun v => Fintype.card (bn.states v)).sum +
      Fintype.card (PartialAssignment bn Q)) - 1 < 1 →
    ∀ q, |post q - d.pmf q| ≤
      ((1 + ((1 + u) ^ (Fintype.card bn.M + (vs.map fun v => Fintype.card (bn.states v)).sum +
          Fintype.card (PartialAssignment bn Q)) - 1)) /
        (1 - ((1 + u) ^ (Fintype.card bn.M + (vs.map fun v => Fintype.card (bn.states v)).sum +
          Fintype.card (PartialAssignment bn Q)) - 1)) - 1) * d.pmf q

/-- `posteriorIndex` is the count the prose names. -/
theorem posteriorIndex_eq (bn : FinBayesNet) (Q : Finset bn.V) (vs : List bn.V) :
    posteriorIndex bn Q vs = Fintype.card bn.M + (vs.map fun v => Fintype.card (bn.states v)).sum +
      Fintype.card (PartialAssignment bn Q) := by
  unfold posteriorIndex veIndex; omega

theorem forward1 : Candidate → Shadow1 :=
  fun h bn u hu κ hloc hκ Q E observed vs hvs hset out hrun base num hnum Z hZ post hpost d hd
    hsmall => by
  have := (h bn u hu κ hloc hκ Q E observed vs hvs hset out hrun base num hnum Z hZ post hpost d hd
    (by rw [posteriorIndex_eq]; exact hsmall)).1
  rw [posteriorIndex_eq] at this
  exact this

theorem forward2 : Candidate → Shadow2 :=
  fun h bn u hu κ hloc hκ Q E observed vs hvs hset out hrun base num hnum Z hZ post hpost d hd
    hsmall q => by
  have := (h bn u hu κ hloc hκ Q E observed vs hvs hset out hrun base num hnum Z hZ post hpost d hd
    (by rw [posteriorIndex_eq]; exact hsmall)).2 q
  rw [posteriorIndex_eq] at this
  exact this

theorem backward : Shadow1 → Shadow2 → Candidate :=
  fun s1 s2 bn u hu κ hloc hκ Q E observed vs hvs hset out hrun base num hnum Z hZ post hpost d hd
    hsmall => by
  rw [posteriorIndex_eq] at hsmall ⊢
  exact ⟨s1 bn u hu κ hloc hκ Q E observed vs hvs hset out hrun base num hnum Z hZ post hpost d hd
    hsmall, s2 bn u hu κ hloc hκ Q E observed vs hvs hset out hrun base num hnum Z hZ post hpost d hd
    hsmall⟩

/-- SA-Pass anchor: the cited theorem proves `Candidate` as stated, so a restatement that
drifts from the proved theorem stops compiling. -/
theorem anchor : Candidate :=
  fun _ _ hu κ hloc hκ Q E observed vs hvs hset out hrun base num hnum Z hZ post hpost d hd hsmall =>
    ve_posterior_forward_error hu κ hloc hκ Q E observed vs hvs hset out hrun base num hnum Z hZ
      post hpost d hd hsmall

end BayesianNetworksProofs.Shadows.PosteriorForwardError
