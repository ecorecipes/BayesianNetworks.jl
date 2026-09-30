import BayesianNetworksProofs.Finite.DSeparation

/-!
# SA-Pass shadow module: d-separation soundness

Claim `bn.dsep`, from `d_separation_sound`. Read literally, the quoted sentence ("the
moralized-ancestral graph path criterion implies the conditional-independence event
identity") promises the identity for any kernel. The forward check of that reading leaves
`bn.Closed`, `bn.TopoOrder`, locality and normalisation open, so the theorem needs all four,
and normalisation is a hypothesis of the identity itself, not only of its probability
reading. The shadow below keeps them; the prose must state them for the claim to align.
-/

namespace BayesianNetworksProofs.Shadows.DSeparation

open BayesianNetworksProofs BayesianNetworksProofs.FinBayesNet

/-- `d_separation_sound`, restated abstractly with every hypothesis. -/
abbrev Candidate : Prop :=
  ∀ (bn : FinBayesNet) (κ : bn.Kernel ℝ), bn.Closed → bn.TopoOrder →
    (∀ m, Local κ m) → (∀ m, Normalised κ m) →
    ∀ (A B C : Finset bn.V), Disjoint A C → Disjoint B C →
      DSeparated A B C → ConditionalIndependent (joint κ) A B C

/-- For a closed network with a topological order and local normalised kernels, and `A`, `B`
disjoint from `C`: no path from `A` to `B` in the moral graph of the ancestors of `A ∪ B ∪ C`
with `C` cut out (the graph path criterion) implies the event identity
`P(A,B,C)·P(C) = P(A,C)·P(B,C)` for every assignment. -/
abbrev Shadow1 : Prop :=
  ∀ (bn : FinBayesNet) (κ : bn.Kernel ℝ), bn.Closed → bn.TopoOrder →
    (∀ m, Local κ m) → (∀ m, Normalised κ m) →
    ∀ (A B C : Finset bn.V), Disjoint A C → Disjoint B C →
      (∀ a ∈ A, ∀ b ∈ B, ¬(cutMoral (ancestors ((A ∪ B) ∪ C)) C).Reachable a b) →
      ∀ a b c, eventMass (joint κ) A B C a b c * eventMass (joint κ) ∅ ∅ C a b c =
        eventMass (joint κ) A ∅ C a b c * eventMass (joint κ) ∅ B C a b c

theorem forward1 : Candidate → Shadow1 := by
  intro h bn κ hc ord hloc hnorm A B C hAC hBC hsep
  exact h bn κ hc ord hloc hnorm A B C hAC hBC hsep

theorem backward : Shadow1 → Candidate := by
  intro h bn κ hc ord hloc hnorm A B C hAC hBC hsep
  exact h bn κ hc ord hloc hnorm A B C hAC hBC hsep

/-- SA-Pass anchor: the cited theorem proves `Candidate` as stated, so a restatement that
drifts from the proved theorem stops compiling. -/
theorem anchor : Candidate := fun _ κ hc ord hloc hnorm A B C hAC hBC hsep =>
  d_separation_sound κ hc ord hloc hnorm A B C hAC hBC hsep

end BayesianNetworksProofs.Shadows.DSeparation
