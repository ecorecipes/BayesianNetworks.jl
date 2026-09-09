# BayesianNetworksProofs

Lean 4 / Mathlib formalisation accompanying `BayesianNetworks.jl` (toolchain
`leanprover/lean4:v4.30.0`, Mathlib tag `v4.30.0`; ADR 0005).

```sh
cd proofs
lake exe cache get          # prebuilt Mathlib oleans (shared checkout, see below)
lake build                  # verifies every proof in the default target
make audit                 # fail-closed #print-axioms allowlist verification
lake exe emit_schema        # `make emit-schema`: regenerate schemas/*.schema.json
lake exe emit_schema --check  # `make check-schema`: exit 1 if the JSON is stale
lake build BayesianNetworksProofs.Roadmap  # `make roadmap`: remaining-work module, no sorry
```

The dependency checkout is shared with the other ecosystem `proofs/` projects through
`packagesDir = "../../.lake-packages"` (gitignored); CI rewrites it to a local `.lake/packages`.

## Documents

The proofs are also rendered as a readable document (`BayesianNetworksProofs.md`, `.html`, `.pdf`, committed
here). It is generated from the Lean sources by [mdgen](https://github.com/Seasawher/mdgen)
(Lake dependency, tag `v4.30.0`): the `/-! ... -/` module docstrings become prose and everything
else becomes a `lean` code block, so the document is the verbatim, machine-checked source.

```sh
make mdgen   # BayesianNetworksProofs.md   — lake exe mdgen, modules concatenated in import order
make html    # BayesianNetworksProofs.html — pandoc --standalone --toc --mathjax, style.css
make pdf     # BayesianNetworksProofs.pdf  — pandoc → lualatex with header.tex (STIX Two Text/Math, JuliaMono)
make docs    # all three
```

Requirements: pandoc (≥ 3.8; `lean.xml` is a minimal Lean syntax definition, pandoc has none
built in) and a TeX distribution with `lualatex` (TinyTeX or MacTeX). Fonts: STIX Two Text and
STIX Two Math (macOS system fonts, or TeX Live `stix2-otf`) for prose and mathematics, and
[JuliaMono](https://juliamono.netlify.app) (SIL OFL) for code, which covers all of Lean's
Unicode; it is read from `../../fonts/JuliaMono/` by path (`header.tex`), not installed
system-wide. `make pdf` prints the number of `Missing character` warnings in the LaTeX log
(expected 0). The documents are built locally and committed; CI does not rebuild them.

Module order (`MD_FILES` in the `Makefile`, the import order of `BayesianNetworksProofs.lean`):

1. `Basic.lean` — introduction, structure and SPEC §61 correspondence tables
2. `Schema/Desc.lean`
3. `Schema/BayesNet.lean`
4. `Finite/BayesNet.lean`
5. `Finite/Evaluation.lean`
6. `Finite/OrderedParents.lean`
7. `Finite/VariableElimination.lean`
8. `Finite/Intervention.lean`
9. `Finite/Tensor.lean`
10. `Finite/Open.lean`
11. `Finite/OpenSemantics.lean`
12. `Finite/BoundaryCases.lean`
13. `Markov/Basic.lean`
14. `Finite/Probability.lean`
15. `Roadmap.lean` — remaining categorical questions; no unproved declarations

The current default target also includes `Finite/Assignments.lean`, `Posterior.lean`,
`RawRecords.lean`, `ReferenceTables.lean`, `FactorMarginal.lean`, `JunctionTree.lean`,
`ConditionalIndependence.lean`, `DSeparation.lean`, `NumericalContracts.lean` and
`RefinementExamples.lean`. Their exact placement in the generated document is `MD_FILES`.

## What is formalised

| Module | Content |
|---|---|
| `Schema/Desc.lean` | `SchemaDesc` (obs, homs, attrtypes, attrs) with decidable `WF`, `Sub`, `NoOutgoing`, `extend`, and `toACSetsJson` reproducing ACSets.jl's `generate_json_acset_schema` format. Mathlib-free. |
| `Schema/BayesNet.lean` | `schVariableSpace`, `schBayesNet`, `schInfluenceDiagram` (SPEC §8, §24) and, by `decide`: all three `WF`; `Sub schVariableSpace schBayesNet`; `Sub schBayesNet schInfluenceDiagram`; `NoOutgoing schVariableSpace schBayesNet` and `... schInfluenceDiagram` (the precondition of Catlab's `OpenACSetTypes(BayesNet, VariableSpace)`). |
| `Finite/BayesNet.lean` | The concrete finite model `FinBayesNet` (finite `V`, `M`, finite non-empty `states v`, `target`, `parents`), kernels `Kernel R` over any commutative semiring, `Local`, `Normalised`, `Closed` (`target` bijective), `TopoOrder`, and the joint `joint κ x = ∏ m, κ m x (x (target m))`. |
| `Finite/Evaluation.lean` | **Prop 1a** `sum_joint_eq_one`: closed + topological order + local + normalised ⇒ `∑ x, joint κ x = 1`. Proved by integrating variables out along the order using `fibre`/`marg` (sums over assignments agreeing with a base point outside a set; no dependent tuples). **Prop 1b** `evalSeq_eq_joint`: the sequential evaluator along any complete duplicate-free order equals `joint`. Also the marginalisation toolkit: `marg_union_disjoint` (finite Fubini for fibres), `marg_mul_left`, `marg_joint_downstream` and **Prop 3 closed-world shadow** `marg_joint_upstream` (integrating the downstream variables out of the full joint leaves the joint of the upstream mechanisms) — formerly a `sorry` in `Roadmap.lean`, now proved. |
| `Finite/Intervention.lean` | **Prop 4** `joint_intervene`: `joint (intervene κ m₀ a) x = [x (target m₀) = a] * ∏ m ≠ m₀, κ m x (x (target m))`; the intervened kernel is normalised (`normalised_intervene`) and local with empty parents for the rewritten network `bn.cut m₀` (`local_cut`, `TopoOrder.cut`); corollary `sum_joint_intervene_eq_one`. |
| `Finite/Tensor.lean` | **Prop 2** `joint_tensor`: on `V₁ ⊕ V₂`, `M₁ ⊕ M₂` the joint of `tensorKernel κ₁ κ₂` is the product of the joints; `closed_tensor`, `normalised_tensor`, `local_tensor`, `TopoOrder.tensor`. |
| `Finite/Open.lean` | **The open-network closure theorem** and **Prop 3**. `OpenFinBayesNet` = `FinBayesNet` + `inputs`/`outputs` + the typed-interface rule (`target_inj`, `input_exogenous`, `exogenous_input`, `topo`); `Composable A B` = an injection `ι` of `B`'s inputs into `A`'s outputs plus the matching of their state spaces; `compose` = the quotient-free pushout on `A.V ⊕ {v : B.V // v ∉ B.inputs}`. See below. |
| `Finite/Probability.lean` | The above instantiated at `ℝ≥0`. |
| `Finite/OpenSemantics.lean` | `marg_restrictA` / `marg_restrictB`, the hidden-variable identification, and **Prop 3 in own-variable form**: `osem_compose_glue` and the original `osem_compose`. Partial matching is allowed; locality and normalisation are unnecessary for the algebraic equality. |
| `Finite/OrderedParents.lean` | `ParentOrder` uses a bijection from contiguous positions to parents. Ordered CPTs and local kernels are equivalent (`local_iff_ordered`, both round trips); coordinated order/CPT-axis changes preserve kernels (`toKernel_reindex`); `sum_joint_ordered` transfers joint normalisation. |
| `Finite/VariableElimination.lean` | Scoped factors, bucket multiplication/summation and mechanism compilation. `eliminateAll_joint` equals the full-enumeration marginal; `eliminateAll_order_independent` permits any duplicate-free order for the same variable set. |
| `Finite/BoundaryCases.lean` | A binary pass-through wire refutes dropping the interface-disjointness assumptions. Mechanism-free subset feet have at most as many outputs as inputs, exposing the missing noninjective output legs for copying feet. |
| `Markov/Basic.lean` | Generic Mathlib `MarkovCategory` / `CopyDiscardCategory` consequences. The concrete finite instance is now in `FiniteKernels.jl/proofs/FiniteKernelsProofs/Theory/FinStoch.lean`. |
| `Roadmap.lean` | Remaining categorical/representation questions; no unproved declarations. |

`Audit.lean` prints the axioms of every main theorem; all report a subset of
`propext`, `Classical.choice`, `Quot.sound`.

`make audit` now fails closed: the shared Python wrapper requires exactly one result for
every requested declaration, checks declaration names/order, rejects any unknown axiom and
rejects unexpected output or warnings. It does not merely print an audit to the CI log.
`python3 scripts/audit.py --self-test` verifies its rejection cases.

### Concrete data, inference, separation and numerical contracts

* `RawRecords.lean` gives finite variable/state/mechanism/input records with names, references,
  positions and a rank witness. `decodeId` checks external one-based indices. A finite Boolean
  structural check proves valid state/input positions, state-label uniqueness, closedness and
  causal ordering. Total positional coverage is **derived** from bounded unique positions.
  Repeated input variables are permitted and read diagonally.
* `ReferenceTables.lean` resolves finite named/policy bindings and point-mass labels. Boolean
  readiness/normalization gates check rational columns, coordinate coverage, dimensions and
  state-position label signatures. Their success implies local normalized compiled kernels,
  also after exact rational-to-real conversion. This is a checked data/model bridge, not a
  verified Julia exporter, JSON parser or language compiler. Space references remain metadata.
* `Assignments.lean` and `Posterior.lean` prove explicit evidence clamping equals indicator
  likelihood semantics, construct genuine finite normalized query distributions, and prove
  exact zero feasibility. The existing VE driver computes their numerator. Normalization is
  over retained partial assignments, never over duplicate eliminated coordinates.
* `JunctionTree.lean` implements cached collect/distribute messages from local factors.
  Upward messages and downward induction frames are proved to be side-of-cut projections.
  Beliefs equal the global factor product projected to their bags, and agree with VE.
  Arbitrary child lists have a proved binary working encoding with copied bags and empty
  factor lists. Empty virtual-root separators handle disconnected components; a zero-mass
  component makes every global posterior infeasible, even for another component's query.
  The hypotheses are structural tree/running-intersection and factor-cover conditions, not
  assumed correct messages. The concrete CliqueTrees builder and array implementation are
  not verified.
* `DSeparation.lean` defines real graph separation: ancestor closure in the directed parent
  graph, moralization of retained families, deletion of conditioning vertices, and absence
  of paths. It derives a factor partition and proves conditional independence for local
  normalized DAG kernels. Nonnegativity is explicit for the probability interpretation;
  positive conditioning mass is explicit when dividing. This is the moralized-ancestral
  criterion, not a proof of a concrete Bayes-ball implementation.
* `NumericalContracts.lean` proves finite product/input perturbation bounds, a mass-dependent
  posterior L1 error bound, and a recursively rounded-product bound from local multiplication
  contracts. It does not assert universal Float64 oracle identity. Evidence mass must have
  a positive floor; machine multiplication contracts and further rounding layers need their
  own validated adapters.

The examples check shuffled raw row IDs, repeated slots, reference-bound rational data,
a graphical fork and three disconnected components with globally impossible evidence.
The rational certificate flags use `decide +kernel`, **not** `native_decide`.

### Inspectable finite-data certificates

`scripts/check_certificate.py` accepts the separate `finite-bn-certificate-1` JSON contract,
emits literal Lean data, and invokes Lean to kernel-check the structural/reference gates,
the actual normalization Boolean and evidence bounds/uniqueness:

```sh
python3 scripts/check_certificate.py model.json --output certificate.lean --require-normalized
```

The certificate uses external one-based IDs/positions and exact rational numerator/denominator
strings. Repeated input variables are allowed; duplicate positions, mismatched binding labels
and unresolved references are rejected by checked data predicates. Without
`--require-normalized`, an interpretable nonnegative table with non-unit row sums is retained
and its `normalization_checked` theorem explicitly says `false`; no renormalization is hidden.
Successful proof output is axiom-whitelisted. The emitted data and its input hash are available
for inspection. This does **not** prove the Python JSON transcription or Julia exporter correct.

### Ordered parents and inference: exactly what the new bridge covers

`ParentOrder` formalises a supplied, total, duplicate-free parent ordering, and an ordered
CPT really takes a dependent tuple indexed by those positions. `toKernel_reindex` transports
the table along the parent-order change; it does **not** claim that changing the order without
changing the table preserves semantics. The construction works with different state types
for different parents. It does not yet parse or validate ACSet `Input` rows, prove a sorting
routine correct, model `state_position`, or resolve `KernelRef` attributes.

The variable-elimination algorithm is a list of scoped finite functions, not Julia arrays.
Only factors whose scopes contain the variable are multiplied into its bucket. Repeated
factors are retained with their multiplicities and overlapping scopes are permitted.
`eliminateAll_joint` connects mechanism compilation to the existing `joint` and `marg`
definitions. It proves an **unnormalised** marginal over any commutative semiring; posterior
division at zero evidence mass is not justified, and ordered array layout, junction trees,
and message passing are not verified.

Throughout the project, sum-to-one over a general semiring is a normalisation identity.
Nonnegative entries must additionally be supplied for a probability interpretation over
`ℝ`; over `ℝ≥0` that condition is automatic.

### Open networks: the closure theorem and Proposition 3 (`Finite/Open.lean`)

`OpenFinBayesNet` is the finite counterpart of `CategoricalBayesianNetworks.jl`'s
`Open(bn; inputs, outputs)` (`src/open.jl`). The feet are *subsets* of apex variables, so the
input leg is injective by construction. Attribute naturality (names, references and state
positions) is **not** proved: those attributes are erased. The other represented rules are:

| Julia (`validation_errors(::OpenBayesNet)`) | Lean field |
|---|---|
| at most one mechanism per variable (`validate(bn; closed = false)`) | `target_inj` |
| rule 1 — input-foot variables have no mechanism | `input_exogenous` |
| rule 3 — every mechanism-free apex variable is an input | `exogenous_input` |
| rule 4 — the derived graph is acyclic | `topo : TopoOrder` |

`Composable A B` (an injection `ι : B.inputs ↪ A.outputs` plus abstract state-space
equivalences `states_equiv`, not a theorem about position attributes) gives the composite **without quotient
types**: `V := A.V ⊕ {v : B.V // v ∉ B.inputs}` keeps one representative per pushout class, the
glued variables being represented on the `A` side, and `tr : B.V → V` is the right-hand pushout
leg. Proven, sorry-free:

* `composeNet_target_injective` — **at most one mechanism per variable is preserved.** This is
  the theorem the SPEC §13 revision note and `compose`'s docstring assert ("Under the
  typed-interface rule the pushout never produces two mechanisms for one variable"). The key
  step: a mechanism of `B` never targets a glued variable, because `B`'s inputs are exogenous;
  so the two mechanism families cannot collide.
* `compose_input_exogenous`, `compose_exogenous_input` — the composite's inputs are exactly
  `A.inputs`, and every variable contributed by `B` keeps its mechanism (rules 1 and 3).
* `composeTopo` — **acyclicity is preserved** (rule 4): `A`'s order followed by `B`'s order
  restricted to the non-input variables is a topological order of the composite. This is
  *derived*, not assumed as a hypothesis.
* `compose` — the four above bundled back into an `OpenFinBayesNet`, with outputs
  `(A.outputs \ glued) ∪ tr (B.outputs)` exactly as in Julia's `glue`. Producing this term
  *is* the closure theorem.
* `closed_compose`, `sum_joint_compose_eq_one` — if `A` has no inputs the composite is closed,
  so `⟦B ∘ A⟧` is a probability distribution.

Semantics (**Proposition 3**, SPEC §13.2, §55.5, §61):

* `joint_compose` — `joint (composeKernel c κA κB) x = joint κA (restrictA c x) * joint κB
  (restrictB c x)`: the joint of the composite factors as the product of the two joints. The
  sequential analogue of `joint_tensor`, and the algebraic heart of Proposition 3.
* `local_compose`, `normalised_compose` — locality and normalisation are preserved.
* `marg_joint_compose` — summing the composite joint over all values of `B`'s private variables
  returns `A`'s joint: `⟦B ∘ A⟧` marginalised back onto `A` is `⟦A⟧`. Only `B`'s kernels have to
  be normalised (`marg_partialJoint_eq_one`'s normalisation hypothesis was weakened to the
  mechanisms targeting the variables being integrated out).
* `marg_joint_compose_split` — **Proposition 3**: for `S` on the `A` side and `T` on the `B`
  side, `marg (S ∪ T) ⟦B ∘ A⟧ = marg S (⟦A⟧ · marg T ⟦B⟧)`. Taking `S` to be `A`'s hidden
  variables together with the glued interface and `T` to be `B`'s hidden variables, this is
  `⟦B ∘ A⟧ = ⟦B⟧ ∘ ⟦A⟧`: the composite semantics is the sum over the interface of the product of
  the two open semantics.

The own-variable form is now proved in `Finite/OpenSemantics.lean`: restriction transfers
each marginal across the corresponding pushout leg by induction on the summed variables.
The composite hidden set is the union of the glued variables and the two hidden sets.
`osem_compose_glue` then gives the product of the two **own** open semantics summed over
the glued interface.

This theorem requires disjoint inputs and outputs on each side, but **not** total matching,
kernel locality, or normalisation. `osem_compose` retains the original Roadmap premises as
a corollary (unused premise names have an underscore). `passthrough_formula_fails` verifies
why disjointness cannot just be removed: a binary wire has semantics one, while blindly
summing its retained interface gives two.

### General category and proof ownership (ADRs 0009 and 0010)

The general open-network category is now constructed in the separate
`CategoricalBayesianNetworks.jl/proofs/` project. It has explicit boundary maps,
ordered repeated parent slots, structural-isomorphism equality, pushout universality,
and Mathlib category/monoidal/symmetric/copy-discard instances. A general FinStoch
interpretation functor and the full Julia/ACSet representation bridge remain unproved.
`outputs_card_le_inputs_card_of_no_mechanisms` isolates the representation obstruction to
a mechanism-free copying foot with one input and two output ports in this project's
older subset-foot representation, not in the new boundary-map representation.

The shared Lean project remains in `BayesianNetworks.jl`: it supplies the
finite semantics, the schema emitter and the downstream influence-diagram dependency.
The new syntax-only categorical project currently needs Mathlib but does not import this
finite numerical core; a later numerical semantics bridge can introduce that dependency.
Schema emission stays here. Mathlib imports are not Julia dependencies and do not
violate the Catlab layering rule.

## How the schema JSON reaches Julia

The Lean terms in `Schema/BayesNet.lean` and the ACSets `BasicSchema` values in `BayesianNetworks.jl/src/schemas.jl`
are two independent hand-written definitions. Neither is generated from the other; they are *checked to agree*
by `lake exe emit_schema --check` here and by a test in the Julia package.
`lake exe emit_schema` (target `emit_schema`, root `Main.lean`; links only Lean core because the
`Schema/` modules do not import Mathlib) writes

```
schemas/variable_space.schema.json
schemas/bayesnet.schema.json
schemas/influence_diagram.schema.json
```

in exactly the shape of ACSets.jl's `generate_json_acset_schema`:
`{"version": {"ACSetSchema": "0.0.1", "ACSets": "0.2.29"}, "Ob": [{"name"}], "Hom": [{"name","dom","codom"}],
"AttrType": [{"name"}], "Attr": [{"name","dom","codom"}], "equations": []}`. Generator order is
the declaration order of the Lean terms (base schema first, then the extension). JSON object keys
are printed in Lean's fixed `Json.obj` order, so compare *structurally*: the Julia test does
`generate_json_acset_schema(SchBayesNet) == JSON3.read("proofs/schemas/bayesnet.schema.json")`
modulo the `version` object. `lake exe emit_schema --check` (run in CI after the build) exits 1
if a committed file differs from what the Lean terms would emit, so the two sides cannot drift.
