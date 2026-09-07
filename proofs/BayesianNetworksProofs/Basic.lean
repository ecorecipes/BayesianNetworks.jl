import Mathlib.CategoryTheory.MarkovCategory.Basic

/-!
# BayesianNetworksProofs

Lean 4 / Mathlib formalisation accompanying `BayesianNetworks.jl` (toolchain
`leanprover/lean4:v4.30.0`, Mathlib tag `v4.30.0`; ADR 0005). This document is generated from
the Lean sources by [mdgen](https://github.com/Seasawher/mdgen): the prose is the module
docstrings and the code blocks are the verbatim, machine-checked sources. Every declaration
outside the final "Roadmap" section is built by `lake build --wfail` and its axioms are printed
by `Audit.lean` (only `propext`, `Classical.choice`, `Quot.sound`).

## What is formalised

`BayesianNetworks.jl` represents a Bayesian network as an ACSet on the schema `SchBayesNet`
(SPEC §8) whose semantics is a finite stochastic state `p_G : I → ⨂_v X_v` computed by
`joint_distribution` (SPEC §5, §10), with hard interventions `do_intervention` (SPEC §21–§22)
and the tensor `otimes` of open networks (SPEC §13). Three layers are formalised:

* **Schema layer** (`Schema/`, Mathlib-free): the ACSet schemas as Lean terms, their
  well-formedness, and the JSON writer behind `lake exe emit_schema`. The Julia test compares
  `generate_json_acset_schema(SchBayesNet)` with the committed `schemas/*.schema.json`, so the
  The Lean terms and the Julia `@present` schemas are two independent definitions that
  `emit_schema --check` and a Julia test check to agree; neither is generated from the other.
* **Finite model** (`Finite/`): `FinBayesNet` (finite variables and mechanisms, finite state
  spaces, `target`, `parents`), kernel families over an arbitrary commutative semiring `R`
  (instantiated at `ℝ≥0` in `Finite/Probability.lean`), Propositions 1, 2, 3 and 4 of SPEC §61,
  and the open-network closure theorem of SPEC §13 (`Finite/Open.lean`).
* **Abstract layer** (`Markov/`): the generic consequences of Mathlib's `MarkovCategory` /
  `CopyDiscardCategory` axioms that the Julia tests check on the finite-stochastic instance.

| Part | Module | Content |
|:--|:-----------------|:-----------------------------------|
| 1 | `Schema/Desc.lean` | `SchemaDesc`, decidable `WF`, `Sub`, `NoOutgoing`, `extend`, `toACSetsJson` (ACSets.jl's `generate_json_acset_schema` format). |
| 2 | `Schema/BayesNet.lean` | `schVariableSpace`, `schBayesNet`, `schInfluenceDiagram` and their `decide`d properties, including the `OpenACSetTypes` precondition. |
| 3 | `Finite/BayesNet.lean` | `FinBayesNet`, `Assignment`, `Kernel R`, `LocalOn`, `Local`, `Normalised`, `Closed`, `TopoOrder`, `joint`. |
| 4 | `Finite/Evaluation.lean` | Proposition 1: `sum_joint_eq_one` (1a) and `evalSeq_eq_joint` (1b), via fibres and marginalisation. |
| 5 | `Finite/Intervention.lean` | Proposition 4: `cut`, `intervene`, `joint_intervene`, `sum_joint_intervene_eq_one`. |
| 6 | `Finite/Tensor.lean` | Proposition 2: `tensor`, `tensorKernel`, `joint_tensor`, `TopoOrder.tensor`. |
| 7 | `Finite/Open.lean` | `OpenFinBayesNet` (the typed-interface rule), `Composable`, `compose` — the open-network closure theorem — and Proposition 3: `joint_compose`, `marg_joint_compose`, `marg_joint_compose_split`. |
| 8 | `Markov/Basic.lean` | `discard_natural`, `state_discard`, `deterministic_comp`, `deterministic_copy` for Mathlib's abstract classes. |
| 9 | `Finite/Probability.lean` | Propositions 1 and 4 at `R := ℝ≥0`. |
| — | `Roadmap.lean` | Proposition 3 in interface form (`osem_compose`, `sorry`); not in the default target. |

## SPEC §61 propositions

| SPEC §61 | Lean | Julia (`BayesianNetworks.jl`) |
|:--------------|:-------------------|:---------------|
| Prop 1 — BN evaluation, `⟦G⟧(x) = ∏_v κ_v(x_v ∣ x_pa(v))` | `sum_joint_eq_one` (the product is a distribution), `evalSeq_eq_joint` (the sequential evaluator computes it) | `joint_distribution(bn)`, `validate(bn; closed=true)`, `topological_order` |
| Prop 2 — tensor compositionality, `⟦A ⊗ B⟧ = ⟦A⟧ ⊗ ⟦B⟧` | `joint_tensor`, `closed_tensor`, `normalised_tensor`, `local_tensor`, `TopoOrder.tensor` | `otimes(A, B)` of `OpenBayesNet`s |
| Prop 3 — sequential compositionality, `⟦B ∘ A⟧ = ⟦B⟧ ∘ ⟦A⟧` | `marg_joint_upstream` (closed-world shadow), `joint_compose`, `marg_joint_compose`, `marg_joint_compose_split` (open networks); `Roadmap.osem_compose` restates the last one in terms of the interface sets and is still unproved | `compose(A, B)`, `glue(A, B; along)` of `OpenBayesNet`s |
| SPEC §13 revision note — pushout composition preserves "at most one mechanism per variable" | `composeNet_target_injective`, `compose_input_exogenous`, `compose_exogenous_input`, `composeTopo`, `compose` | `Open(bn; inputs, outputs)`, `validate(::OpenBayesNet)`, `compose`, `glue` |
| Prop 4 — hard intervention, truncated factorisation of `do(X = x)` | `joint_intervene`, `normalised_intervene`, `local_cut`, `sum_joint_intervene_eq_one` | `do_intervention(bn, :X => x)` |
| Props 5–7 — influence diagrams | `InfluenceDiagrams.jl/proofs` (depends on this project by path) | `InfluenceDiagrams.jl` |

The Markov-category laws of the kernel calculus itself (`compose`, `otimes`, `mcopy`, `delete`)
are proved in `MarkovCategories.jl/proofs`.
-/

namespace BayesianNetworksProofs

/-- Smoke lemma so that an empty project builds and the axiom audit has something to print. -/
theorem smoke : (1 : Nat) + 1 = 2 := rfl

end BayesianNetworksProofs
