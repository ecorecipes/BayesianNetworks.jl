import BayesianNetworksProofs.Finite.JunctionTree

/-!
# SA-Pass shadow module: cached Shafer-Shenoy calibration

Claim `bn.junction-tree`, from `calibrate_eq_ve` and `queryPosterior_value`. Both keep the
hypotheses the README names next to the claim: structural running intersection (`Good`),
complete factor assignment (`hassign`) and variable coverage (`hvars`); the posterior also
needs nonnegative factors.
-/

namespace BayesianNetworksProofs.Shadows.JunctionTree

open BayesianNetworksProofs BayesianNetworksProofs.FinBayesNet BayesianNetworksProofs.Junction

/-- The two cited theorems, restated abstractly with every hypothesis. -/
abbrev Candidate : Prop :=
  (∀ (bn : FinBayesNet) (I : Type) [Fintype I] (F : I → Factor bn ℝ) (t : Tree bn.V I),
      Good F t → t.indices.Perm Finset.univ.toList → (∀ v, ∃ i, v ∈ (F i).scope) →
      ∀ (b : Finset bn.V × Factor bn ℝ), b ∈ calibrate F t →
      ∀ (vs : List bn.V), vs.Nodup → vs.toFinset = b.1ᶜ → ∀ x : bn.Assignment,
        b.2.value x = Factor.product (Factor.eliminateAll (Finset.univ.toList.map F) vs) x) ∧
    ∀ (bn : FinBayesNet) (I : Type) [Fintype I] (F : I → Factor bn ℝ) (t : Tree bn.V I)
      (ht : Good F t) (hassign : t.indices.Perm Finset.univ.toList)
      (hvars : ∀ v, ∃ i, v ∈ (F i).scope) (hF : ∀ i x, 0 ≤ (F i).value x)
      (b : Finset bn.V × Factor bn ℝ) (hb : b ∈ calibrate F t)
      (Q : Finset bn.V) (hQ : Q ⊆ b.1) (base : bn.Assignment)
      (d : FiniteDistribution.Distribution (PartialAssignment bn Q)),
      queryPosterior F t ht hassign hvars hF b hb Q hQ base = some d →
      ∀ q, d.pmf q =
        FiniteDistribution.pushWeight (restrictTo Q)
            (Factor.product (Finset.univ.toList.map F)) q /
          FiniteDistribution.mass (Factor.product (Finset.univ.toList.map F))

/-- "clique ... agreement with VE": every calibrated clique belief equals variable
elimination of the other variables, in any duplicate-free order. -/
abbrev Shadow1 : Prop :=
  ∀ (bn : FinBayesNet) (I : Type) [Fintype I] (F : I → Factor bn ℝ) (t : Tree bn.V I),
    Good F t → t.indices.Perm Finset.univ.toList → (∀ v, ∃ i, v ∈ (F i).scope) →
    ∀ (b : Finset bn.V × Factor bn ℝ), b ∈ calibrate F t →
    ∀ (vs : List bn.V), vs.Nodup → vs.toFinset = b.1ᶜ → ∀ x : bn.Assignment,
      b.2.value x = Factor.product (Factor.eliminateAll (Finset.univ.toList.map F) vs) x

/-- "query agreement with ... the joint posterior": a returned query posterior read off a
calibrated clique is the exhaustive joint posterior of the query. -/
abbrev Shadow2 : Prop :=
  ∀ (bn : FinBayesNet) (I : Type) [Fintype I] (F : I → Factor bn ℝ) (t : Tree bn.V I)
    (ht : Good F t) (hassign : t.indices.Perm Finset.univ.toList)
    (hvars : ∀ v, ∃ i, v ∈ (F i).scope) (hF : ∀ i x, 0 ≤ (F i).value x)
    (b : Finset bn.V × Factor bn ℝ) (hb : b ∈ calibrate F t)
    (Q : Finset bn.V) (hQ : Q ⊆ b.1) (base : bn.Assignment)
    (d : FiniteDistribution.Distribution (PartialAssignment bn Q)),
    queryPosterior F t ht hassign hvars hF b hb Q hQ base = some d →
    ∀ q, d.pmf q =
      FiniteDistribution.pushWeight (restrictTo Q)
          (Factor.product (Finset.univ.toList.map F)) q /
        FiniteDistribution.mass (Factor.product (Finset.univ.toList.map F))

theorem forward1 : Candidate → Shadow1 := fun h => h.1

theorem forward2 : Candidate → Shadow2 := fun h => h.2

theorem backward : Shadow1 → Shadow2 → Candidate := fun h1 h2 => ⟨h1, h2⟩

/-- SA-Pass anchor: the cited theorems prove `Candidate` as stated, so a restatement that
drifts from the proved theorems stops compiling. -/
theorem anchor : Candidate :=
  ⟨fun _ _ _ F t ht hassign hvars b hb vs hvs hset x =>
      calibrate_eq_ve F t ht hassign hvars b hb vs hvs hset x,
   fun _ _ _ F t ht hassign hvars hF b hb Q hQ base d hd q =>
      queryPosterior_value F t ht hassign hvars hF b hb Q hQ base d hd q⟩

end BayesianNetworksProofs.Shadows.JunctionTree
