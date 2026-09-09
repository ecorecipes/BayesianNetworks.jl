import Mathlib.CategoryTheory.MarkovCategory.Basic

/-!
# BayesianNetworksProofs

Lean 4 / Mathlib formalisation accompanying `BayesianNetworks.jl` (toolchain
`leanprover/lean4:v4.30.0`, Mathlib tag `v4.30.0`; ADR 0005). This document is generated from
the Lean sources by [mdgen](https://github.com/Seasawher/mdgen): the prose is the module
docstrings and the code blocks are the verbatim, machine-checked sources. Every library module
is built by `lake build --wfail`; `Audit.lean` prints the axioms of the headline results
(only `propext`, `Classical.choice`, `Quot.sound`). The Roadmap has no remaining proof holes.

## What is formalised

`BayesianNetworks.jl` represents a Bayesian network as an ACSet on the schema `SchBayesNet`
(SPEC §8) whose semantics is a finite stochastic state `p_G : I → ⨂_v X_v` computed by
`joint_distribution` (SPEC §5, §10), with hard interventions `do_intervention` (SPEC §21–§22)
and the tensor `otimes` of open networks (SPEC §13). Three layers are formalised:

* **Schema layer** (`Schema/`, Mathlib-free): the ACSet schemas as Lean terms, their
  well-formedness, and the JSON writer behind `lake exe emit_schema`. The Julia test compares
  `generate_json_acset_schema(SchBayesNet)` with the committed `schemas/*.schema.json`.
  The Lean terms and the Julia ACSets `BasicSchema` values are two independent definitions that
  `emit_schema --check` and a Julia test check to agree; neither is generated from the other.
* **Finite model** (`Finite/`): `FinBayesNet` (finite variables and mechanisms, finite state
  spaces, `target`, `parents`), kernel families over an arbitrary commutative semiring `R`
  (instantiated at `ℝ≥0` in `Finite/Probability.lean`), Propositions 1, 2, 3 and 4 of SPEC §61,
  and the open-network closure theorem of SPEC §13 (`Finite/Open.lean`). Ordered-parent
  refinement and exact bucket variable elimination now connect further parts of the finite
  model, but neither is a theorem about Julia arrays or ACSet attribute operations.
* **Abstract layer** (`Markov/`): the generic consequences of Mathlib's `MarkovCategory` /
  `CopyDiscardCategory` axioms that the Julia tests check on the finite-stochastic instance.

* `Schema/Desc.lean`: `SchemaDesc`, decidable `WF`, `Sub`, `NoOutgoing`, `extend`, and
  `toACSetsJson` in ACSets.jl's schema format.
* `Schema/BayesNet.lean`: the three schemas and their checked structural properties.
* `Finite/BayesNet.lean`: the finite shape, assignments, local/normalised kernels, closedness,
  topological order and joint.
* `Finite/Evaluation.lean`: Proposition 1, through fibres and marginalisation.
* `Finite/OrderedParents.lean`: contiguous positions, ordered CPT/local-kernel equivalence,
  coherent axis reindexing and joint normalisation.
* `Finite/VariableElimination.lean`: scoped factors, bucket elimination, exact joint
  marginalisation and elimination-order independence.
* `Finite/Intervention.lean` and `Finite/Tensor.lean`: Propositions 4 and 2.
* `Finite/Open.lean`: the typed-interface rule, open-network closure and split composition.
* `Finite/OpenSemantics.lean`: own-variable open semantics under partial gluing; the original
  `osem_compose` and a stronger theorem without locality, normalisation or total matching.
* `Finite/BoundaryCases.lean`: pass-through counterexample and mechanism-free copying
  limitation of subset feet.
* `Markov/Basic.lean`: consequences of Mathlib's abstract Markov/copy-discard classes.
* `Finite/Probability.lean`: Propositions 1 and 4 at `R := ℝ≥0`.
* `Roadmap.lean`: remaining categorical and representation questions; no unproved declarations.

### New implementation-facing mathematics

* `Finite/RawRecords.lean` and `ReferenceTables.lean`: concrete finite records, references and
  checked positions, with repeated slots interpreted diagonally. Boolean checks imply the
  compiled local/normalized model; a Julia/JSON translation proof is not asserted.
* `Finite/Assignments.lean` and `Posterior.lean`: explicit conditioning equals indicator
  likelihood, genuine query distributions, positive normalization and exact zero feasibility.
* `Finite/FactorMarginal.lean` and `JunctionTree.lean`: actual collect/distribute messages,
  side-of-cut projections, calibrated beliefs and posterior agreement with VE. Structural
  running intersection and exact factor assignment are the hypotheses, not correct messages.
  Arbitrary branching and disconnected components have proved working encodings.
* `Finite/ConditionalIndependence.lean` and `DSeparation.lean`: soundness of graph separation in
  the moralized ancestral DAG. No path separation is defined in terms of numerical independence.
  The boundary to a concrete Bayes-ball implementation remains explicit.
* `Finite/NumericalContracts.lean`: finite product and posterior error bounds, with a positive
  evidence-mass floor, and rounded products under local arithmetic contracts.
* `Finite/RefinementExamples.lean`: nonvacuous repeated-slot, graph and disconnected zero-support
  fixtures, checked without native proof shortcuts.

## SPEC §61 propositions

| SPEC §61 | Lean | Julia (`BayesianNetworks.jl`) |
|:--------------|:-------------------|:---------------|
| Prop 1 — BN evaluation, `⟦G⟧(x) = ∏_v κ_v(x_v ∣ x_pa(v))` | `sum_joint_eq_one` (the product is a distribution), `evalSeq_eq_joint` (the sequential evaluator computes it) | `joint_distribution(bn)`, `validate(bn; closed=true)`, `topological_order` |
| Prop 2 — tensor compositionality, `⟦A ⊗ B⟧ = ⟦A⟧ ⊗ ⟦B⟧` | `joint_tensor`, `closed_tensor`, `normalised_tensor`, `local_tensor`, `TopoOrder.tensor` | `otimes(A, B)` of `OpenBayesNet`s |
| Prop 3 — sequential compositionality, `⟦B ∘ A⟧ = ⟦B⟧ ∘ ⟦A⟧` | `marg_joint_compose_split`, `osem_compose`, `osem_compose_glue`; the own-variable formulas require disjoint inputs/outputs on both networks | `compose(A, B)`, `glue(A, B; along)` in the categorical package |
| SPEC §13 revision note — pushout composition preserves "at most one mechanism per variable" | `composeNet_target_injective`, `compose_input_exogenous`, `compose_exogenous_input`, `composeTopo`, `compose` | `Open(bn; inputs, outputs)`, `validate(::OpenBayesNet)`, `compose`, `glue` |
| Prop 4 — hard intervention, truncated factorisation of `do(X = x)` | `joint_intervene`, `normalised_intervene`, `local_cut`, `sum_joint_intervene_eq_one` | `do_intervention(bn, :X => x)` |
| Props 5–7 — influence diagrams | `InfluenceDiagrams.jl/proofs` (depends on this project by path) | `InfluenceDiagrams.jl` |

The Markov-category laws of the kernel calculus itself (`compose`, `otimes`, `mcopy`, `delete`)
and the concrete Mathlib `FinStoch` instances are proved in `FiniteKernels.jl/proofs`.

Over a general semiring, the sum-to-one results establish normalisation, not positivity.
The probability interpretation additionally requires nonnegative entries (automatic over
`ℝ≥0`). Inference results here are unnormalised marginal identities and do not authorise
conditioning on zero-probability evidence.
-/

namespace BayesianNetworksProofs

/-- Smoke lemma so that an empty project builds and the axiom audit has something to print. -/
theorem smoke : (1 : Nat) + 1 = 2 := rfl

end BayesianNetworksProofs
