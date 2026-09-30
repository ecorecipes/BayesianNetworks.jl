import BayesianNetworksProofs.Finite.Posterior

/-!
# SA-Pass shadow module: impossible evidence is rejected, and only impossible evidence

Claim `bn.zero-mass`, from `posterior_none_iff`. The quoted prose ("zero global mass is
rejected even for empty or observed queries") gives only one direction of the theorem: with
Shadow1 and Shadow2 alone the backward check leaves
`posterior Q E observed p hp = none → ¬∃ x, agrees E observed x ∧ 0 < p x` open. Shadow3 is
that converse, that a posterior is returned whenever the evidence has positive mass; the
prose must say it for the claim to align.
-/

namespace BayesianNetworksProofs.Shadows.ZeroMass

open BayesianNetworksProofs BayesianNetworksProofs.FinBayesNet

/-- `posterior_none_iff`, restated abstractly with every hypothesis. -/
abbrev Candidate : Prop :=
  ∀ (bn : FinBayesNet) (Q E : Finset bn.V) (observed : bn.Assignment)
    (p : bn.Assignment → ℝ) (hp : ∀ x, 0 ≤ p x),
    posterior Q E observed p hp = none ↔ ¬∃ x, agrees E observed x ∧ 0 < p x

/-- "zero global mass is rejected": no posterior when no assignment agreeing with the
evidence has positive mass, whatever the query. -/
abbrev Shadow1 : Prop :=
  ∀ (bn : FinBayesNet) (Q E : Finset bn.V) (observed : bn.Assignment)
    (p : bn.Assignment → ℝ) (hp : ∀ x, 0 ≤ p x),
    (¬∃ x, agrees E observed x ∧ 0 < p x) → posterior Q E observed p hp = none

/-- "even for empty or observed queries": in particular for the empty query and for a query
of observed variables only. -/
abbrev Shadow2 : Prop :=
  ∀ (bn : FinBayesNet) (Q E : Finset bn.V) (observed : bn.Assignment)
    (p : bn.Assignment → ℝ) (hp : ∀ x, 0 ≤ p x), (Q = ∅ ∨ Q ⊆ E) →
    (¬∃ x, agrees E observed x ∧ 0 < p x) → posterior Q E observed p hp = none

/-- The converse the prose must add: a posterior is returned whenever some assignment agreeing
with the evidence has positive mass. -/
abbrev Shadow3 : Prop :=
  ∀ (bn : FinBayesNet) (Q E : Finset bn.V) (observed : bn.Assignment)
    (p : bn.Assignment → ℝ) (hp : ∀ x, 0 ≤ p x),
    (∃ x, agrees E observed x ∧ 0 < p x) → posterior Q E observed p hp ≠ none

theorem forward1 : Candidate → Shadow1 := by
  intro h bn Q E observed p hp hz
  exact (h bn Q E observed p hp).2 hz

theorem forward2 : Candidate → Shadow2 := by
  intro h bn Q E observed p hp _ hz
  exact (h bn Q E observed p hp).2 hz

theorem forward3 : Candidate → Shadow3 := by
  intro h bn Q E observed p hp hpos hn
  exact (h bn Q E observed p hp).1 hn hpos

theorem backward : Shadow1 → Shadow2 → Shadow3 → Candidate := by
  intro h1 _ h3 bn Q E observed p hp
  constructor
  · intro hn hpos
    exact h3 bn Q E observed p hp hpos hn
  · exact h1 bn Q E observed p hp

/-- SA-Pass anchor: the cited theorem proves `Candidate` as stated, so a restatement that
drifts from the proved theorem stops compiling. -/
theorem anchor : Candidate := fun _ Q E observed p hp =>
  posterior_none_iff Q E observed p hp

end BayesianNetworksProofs.Shadows.ZeroMass
