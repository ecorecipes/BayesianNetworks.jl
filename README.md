# BayesianNetworks.jl

[![Build Status](https://github.com/ecorecipes/BayesianNetworks.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/ecorecipes/BayesianNetworks.jl/actions/workflows/CI.yml)
[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://ecorecipes.github.io/BayesianNetworks.jl/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Compositional Bayesian belief networks as attributed C-sets: mechanisms, interventions, dynamic
networks and reference finite-stochastic semantics.

The package needs **no Catlab** (ADR 0009): it depends on ACSets, GATlab, `FiniteKernels.jl`,
`BayesianNetworkFormats.jl`, Graphs and Graphviz_jll. Open networks as structured cospans, their
composition, the wiring-diagram view and the free Markov-category semantics live in
`CategoricalBayesianNetworks.jl`, which adds them as methods and types on top of everything here.

Part of the ecorecipes compositional Bayesian-network ecosystem:
`FiniteKernels.jl` → `BayesianNetworks.jl` → `BayesianNetworkInference.jl` →
`InfluenceDiagrams.jl`, with `MarkovCategories.jl` → `CategoricalBayesianNetworks.jl` on the
categorical side, `BayesianNetworkFormats.jl` (file formats) and
`EcologicalBayesianNetworks.jl` (model zoo).

## Features

Structural layer (available now):

- `SchVariableSpace` / `SchBayesNet` ACSet schemas and the `BayesNet` type: variables with
  ordered states, mechanisms with a target, ordered inputs; no primitive edges, no numerical
  tables in the ACSet. The Lean project in `proofs/` carries a second, hand-written
  definition of the same schema; neither side is generated from the other, and CI checks
  that the two agree (`lake exe emit_schema --check` plus a Julia test against
  `generate_json_acset_schema`).
- `KernelRef` sum type (`NamedRef`, `PointMassRef`, `PolicyRef`, `NoRef`) for the semantic
  references carried by variables and mechanisms, with JSON round-tripping.
- Builders (`bayesnet`, `add_variable!`, `add_state!`, `add_mechanism!`, `add_input!`) and
  inspection (`states`, `parents`, `children`, `mechanism_of`, `inputs`, `roots`, ...).
- Derived graphs: `variable_graph`, `topological_order`, `is_acyclic`, `moral_graph`
  (Graphs.jl `SimpleDiGraph` / `SimpleGraph`, with vertex id = variable part id).
- `validate` / `validation_errors` / `isvalid` with typed exceptions for every structural
  check of SPEC §11 (open and closed networks).
- `canonicalize` and `is_isomorphic` for order-independent comparison.
- JSON serialisation (`json_bayesnet`, `write_json_bayesnet`, ...) in a versioned envelope
  around ACSets' JSON, and `schema_json`.
- `rename_variable` on a network or a model (the spaces and the kernel axes follow).
- The `BayesModel` wrapper (syntax, spaces, kernels, evidence, history) with `observe` /
  `unobserve`, hard `do_intervention` and `soft_intervention` as local mechanism rewrites,
  and provenance (`history`, `intervened_variables`).

Semantic layer:

- `BayesModel` binds one `FiniteKernel` from FiniteKernels.jl to every mechanism
  (`bind_kernel`, `bind_cpt` with the parents-first / child-last table layout of ADR 0002),
  with typed checks of axis labels, parent order and normalisation (SPEC §11 items 8-10).
- Reference evaluation: brute-force `joint_distribution` (a composable state) and
  `joint_table`, `marginal` and `conditional` with evidence, ancestral `sample` and
  `empirical_marginal`. The categorical route to the same joint (`to_free_expression`,
  `categorical_joint`, Proposition 1) and the kernel semantics of open networks
  (`interpret`, Propositions 2 and 3) are in `CategoricalBayesianNetworks.jl`.
- `read_bayesnet` / `write_bayesnet` through BayesianNetworkFormats.jl (Netica, GeNIe,
  HUGIN, BIF, DSC, UAI) and `json_model` with a semantics sidecar.
- Dynamic networks (SPEC §43): `DynamicBayesNet(initial, transition)` templates with
  lagged inputs named `lagged(:X, k)` (`X[t-1]`), validated as templates; `unroll(dbn, h)`
  compiles a finite horizon into a closed `BayesNet` with variables `X_t` (exact boundary:
  the initial network covers the first `lags` slices), `DynamicBayesModel` unrolls kernels
  per slice, `rollout` / `filter_marginal` give per-slice marginals, and the ecological
  `vegetation_herbivore_dbn` / `vegetation_herbivore_model` example (with optional
  `Management`). Unrolling agrees with gluing slices as open networks, which
  `CategoricalBayesianNetworks.jl` checks.

Views and export:

- `proof_certificate` emits exact rational finite-model data for the separate
  Lean literal-certificate consumer, preserving raw row order, repeated parent
  slots, reference identities and evidence. See the
  [certificate guide](docs/src/certificates.md); runtime tolerance is not exact
  rational normalization, and checking data does not verify the Julia runtime.
- Graphviz drawings with `to_graphviz` (the DAG of a network or model, with evidence,
  interventions and states marked), built as a DOT syntax tree by the package's own
  `Graphviz` submodule and rendered to SVG through Graphviz_jll -- no Catlab needed to draw
  a network. `CategoricalBayesianNetworks.jl` adds the methods for open networks and for
  wiring diagrams.
- CatColab export (export-only; CatColab has no Bayesian-network theory yet):
  `catcolab_schema_document` (the schema as a `simple-schema` model document with
  deterministic UUIDs), `catcolab_instance_document` (a network as a diagram in it),
  `catcolab_model`, `parse_catcolab_schema`, and `presentation_json` for the generators
  of the free Markov-category presentation.

Reporting:

- `ModelCard` and `report`: the minimum reporting record the ecology literature asks for
  (decision context; endpoint and spatial/temporal extent; graph rationale and named
  alternative structures; state definitions; per-mechanism `ParameterProvenance` with
  source type, citation, dataset, estimator, expert, timestamp and notes, SPEC §49;
  elicitation protocol; validation summary and a `validation_scores` slot for
  BayesianNetworkInference.jl; intended use, limitations, licence and versions).
  `ModelCard(m)` prefills it from a model, `provenance!` attaches sources,
  `undocumented_mechanisms` lists the gaps, `report` writes Markdown, and
  `json_model(m; card)` / `read_json_card` carry it in the JSON envelope (files without a
  card still read exactly as before).

## Formal proofs

`proofs/` is a Lean 4 / Mathlib project (`leanprover/lean4:v4.30.0`, ADR 0005) checked by the
`Lean` workflow. What it establishes, and with what qualifications:

- Proved, `sorry`-free, on only `propext`, `Classical.choice` and `Quot.sound`: Proposition 1
  (the local product sums to one and the sequential evaluator computes it), Proposition 2
  (tensor compositionality, `⟦A ⊗ B⟧ = ⟦A⟧ ⊗ ⟦B⟧` for the disjoint union of two networks with
  no shared feet), Proposition 3 (sequential compositionality) and Proposition 4 (hard
  intervention, truncated factorisation), together with the **open-network closure theorem**:
  `composeNet_target_injective` in `Finite/Open.lean` shows that composition along a matched
  interface preserves "at most one mechanism per variable", with `compose_input_exogenous`,
  `compose_exogenous_input` and `composeTopo` (acyclicity *derived*, not assumed) giving the
  other three clauses of the typed-interface rule, so `compose` returning an `OpenFinBayesNet`
  is itself the proof.
- Proposition 3 is proved in split form, `marg (S ∪ T) ⟦B ∘ A⟧ = marg S (⟦A⟧ · marg T ⟦B⟧)`
  (`marg_joint_compose_split`), which is its mathematical content; `joint_compose`,
  `marg_joint_compose`, `local_compose`, `normalised_compose`, `closed_compose` and
  `sum_joint_compose_eq_one` come with it. The own-variable statement `osem_compose` is
  now proved in `Finite/OpenSemantics.lean`, with its original hypotheses. The stronger
  `osem_compose_glue` drops locality, normalisation and match surjectivity, but still
  requires disjoint input/output sets on both networks. Every B input is matched into
  A's outputs; unused A outputs are retained. General pass-through composition and
  arbitrary two-sided partial gluing are not covered by that formula.
- `Finite/OrderedParents.lean` proves an exact positional-CPT/local-kernel equivalence
  and coherent parent-axis reindexing for a supplied duplicate-free parent ordering.
  `Finite/VariableElimination.lean` implements scoped finite-function bucket elimination
  and proves agreement with the existing joint marginal, including compilation of local
  mechanisms and independence of a duplicate-free elimination order.
- `Finite/RawRecords.lean` and `Finite/ReferenceTables.lean` now check finite
  variable/state/mechanism/input records, derive positional bijections and topological
  order, retain attributes and resolve named, policy and point-mass references.
  Repeated input slots compile diagonally; complete raw CPT columns, ordered labels,
  nonnegative rational weights and exact normalization are checked separately.
  `proof_certificate(m)` supplies that data interface without changing bound numbers.
- `Finite/Assignments.lean` and `Finite/Posterior.lean` prove explicit
  clamping/dropping of evidence equivalent to indicator-factor elimination, and VE
  numerator/normalized-posterior correctness. Distributions live on retained
  assignments, and zero global mass is rejected even for empty or observed queries.
  Julia's empty `infer` query is instead an unnormalized evidence-mass API.
- `Finite/JunctionTree.lean` defines actual cached Shafer-Shenoy collect/distribute
  passes and proves clique/query agreement with VE and the joint posterior.
  Hypotheses are structural running intersection, complete factor assignment and
  variable coverage, not precomputed correct messages. Binary grafting represents
  arbitrary branching and empty-separator roots represent disconnected forests.
- `Finite/DSeparation.lean` proves the moralized-ancestral **graph path**
  criterion implies the conditional-independence event identity. With normalized
  nonnegative local kernels this has its probability interpretation; conditioning
  is divided out only at positive mass. `Finite/NumericalContracts.lean` supplies
  input-perturbation and posterior L1 bounds with an explicit evidence-mass floor,
  plus a rounded-product bound conditional on local arithmetic contracts.
- These are exact finite-model/data results, not verification of Julia execution.
  In particular, the new raw-record compiler feeds the existing `FinBayesNet`
  reduct, whose parent sets erase slot multiplicity only after diagonal evaluation.
  Full ACSet/JSON/array translation, CliqueTrees construction and IEEE arithmetic
  remain separate. Formal forest beliefs include outside-component scalar masses;
  Julia stores component-local beliefs and checks global mass separately. Their
  raw arrays must not be identified without that scaling relationship.
- The general category is now constructed in `CategoricalBayesianNetworks.jl/proofs/`
  (ADR 0010): explicit arbitrary output legs, ordered repeated slots, structural
  isomorphism, pushout gluing and Mathlib category/monoidal/symmetric/copy-discard
  instances. The old subset-foot cardinality obstruction explains why it needs a
  richer representation. That project also supplies the general exact FinStoch
  interpretation as a strong braided monoidal functor. The complete Julia/ACSet
  runtime refinement remains separate.
- `InfluenceDiagrams.jl/proofs/InfluenceDiagramsProofs/Finite/DVE/` proves a checked exact finite-function
  DVE algorithm, including generated no-forgetting schedules, policy reconstruction,
  global optimality and all-row diagnostic completeness. This is not a proof of
  literal floating-point backend/oracle equality.
- No default or compatibility Roadmap target contains a `sorry`. Headline results are
  included in `Audit.lean`, whose dependencies are only the three axioms listed above.
- The schemas are *checked to agree*, as described above. Neither the Lean `SchemaDesc` terms
  nor the Julia `BasicSchema` declarations are generated from the other, so neither is a source
  of truth for the other.
- `proofs/Finite/Open.lean`, which carries the open-network closure theorem and Proposition 3,
  is about the layer that now lives in `CategoricalBayesianNetworks.jl`. The Lean project has
  not moved: it also emits the `SchBayesNet` schema JSON that is compared against this
  package's own declarations.

## Installation

The ecosystem packages are not registered. Install this package and its ecosystem
dependencies by URL, in dependency order:

```julia
using Pkg
Pkg.add(url="https://github.com/ecorecipes/FiniteKernels.jl")
Pkg.add(url="https://github.com/ecorecipes/BayesianNetworkFormats.jl")
Pkg.add(url="https://github.com/ecorecipes/BayesianNetworks.jl")
```

Requires Julia ≥ 1.12.

## Quick Start

```julia
using BayesianNetworks

# SPEC §45 reference network (structure only)
bn = bayesnet(:Climate => [:dry, :normal, :wet],
              :Irrigation => [:low, :high],
              :SoilMoisture => [:low, :medium, :high],
              :GrazingPressure => [:low, :high],
              :Vegetation => [:sparse, :moderate, :dense],
              :HabitatQuality => [:poor, :good],
              :Occupancy => [:absent, :present];
              mechanisms = [:SoilMoisture => (:Climate, :Irrigation),
                            :Vegetation => (:SoilMoisture, :GrazingPressure),
                            :HabitatQuality => :Vegetation,
                            :Occupancy => :HabitatQuality])
# or simply: bn = reference_habitat_bn()

validate(bn; closed = true)                              # nothing
states(bn, :SoilMoisture)                                 # [:low, :medium, :high]
variable_name.(Ref(bn), parents(bn, :Vegetation))         # [:SoilMoisture, :GrazingPressure]
variable_name.(Ref(bn), topological_order(bn))

canonicalize(bn) == canonicalize(parse_json_bayesnet(json_bayesnet(bn)))   # true

# Bind conditional probability tables (parents first, child last; ADR 0002)
m = BayesModel(bn)
m = bind_cpt(m, :Climate => [0.3, 0.5, 0.2])
m = bind_cpt(m, :HabitatQuality => [0.85 0.15; 0.4 0.6; 0.15 0.85])   # rows = Vegetation
missing_kernels(m)                          # [:SoilMoisture, :Vegetation, :Occupancy, :Irrigation, :GrazingPressure]
m = reference_habitat_model()               # the same network with every table bound
validate(m; closed = true, semantics = true)

# Joint and marginals
J = joint_distribution(m)                   # FiniteKernel I -> Climate ⊗ ... ⊗ Occupancy
sum(J.table) ≈ 1                            # true (1.0000000000000002 in floating point)
marginal(m, :Occupancy).table               # [0.5238, 0.4762]
probability(conditional(m, :Occupancy, :Vegetation), :present, :dense)

# Observation versus intervention: seeing dense vegetation says something about the soil,
# forcing dense vegetation does not
marginal(observe(m, :Vegetation => :dense), :SoilMoisture).table
marginal(do_intervention(m, :Vegetation => :dense), :SoilMoisture) ≈ marginal(m, :SoilMoisture)   # true
sample(m, 1000)[1]                          # Dict(:Climate => :dry, ...)

# Read a Netica file (also .xdsl, .net, .bif, .dsc, .uai)
m2 = read_bayesnet(fixture_path("dne/habitat_reference.dne"))
m2 ≈ m                                      # true
marginal(read_bayesnet(fixture_path("bif/asia.bif")), :dysp).table   # [0.436, 0.564]

# Drawings (a Graphviz.Graph; shows as SVG in notebooks and quarto)
to_graphviz(m)                              # the DAG with states, evidence and interventions

# CatColab export (export-only) and the free presentation
doc = catcolab_schema_document(BayesNet)    # simple-schema model document, deterministic UUIDs
parse_catcolab_schema(doc) == acset_schema(BayesNet())   # true (acset_schema is re-exported)
presentation_json(m)                        # {"format":"markov-presentation/0.1","objects":[...],"generators":[...]}
```

## Vignettes

Rendered vignettes live in [`vignettes/`](vignettes/) and are published in the
[documentation](https://ecorecipes.github.io/BayesianNetworks.jl/): networks of mechanisms
and brute-force evaluation, observation versus intervention, serialisation and provenance,
dynamic networks, and model cards. The wiring-diagram and open-network vignettes are in
`CategoricalBayesianNetworks.jl`.

## References

The package implements known constructions rather than new theory; the works it follows
most directly are:

- Fong, B. (2012). *Causal theories: a categorical perspective on Bayesian networks*.
  MSc thesis, University of Oxford. [arXiv:1301.6201](https://arxiv.org/abs/1301.6201).
- Baez, J. C. and Courser, K. (2020). Structured cospans. *Theory and Applications of
  Categories* 35(48), 1771-1822. [arXiv:1911.04630](https://arxiv.org/abs/1911.04630).
- Jacobs, B., Kissinger, A. and Zanasi, F. (2019). Causal inference by string diagram
  surgery. *FoSSaCS 2019*, LNCS 11425, 313-329.
  [doi:10.1007/978-3-030-17127-8_18](https://doi.org/10.1007/978-3-030-17127-8_18).
- Lorenz, R. and Tull, S. (2023). Causal models in string diagrams.
  [arXiv:2304.07638](https://arxiv.org/abs/2304.07638).
- Pearl, J. (2009). *Causality: Models, Reasoning, and Inference*, 2nd ed. Cambridge
  University Press. [doi:10.1017/CBO9780511803161](https://doi.org/10.1017/CBO9780511803161).
- Fritz, T. (2020). A synthetic approach to Markov kernels, conditional independence and
  theorems on sufficient statistics. *Advances in Mathematics* 370, 107239.
  [doi:10.1016/j.aim.2020.107239](https://doi.org/10.1016/j.aim.2020.107239).
- Cho, K. and Jacobs, B. (2019). Disintegration and Bayesian inversion via string
  diagrams. *Mathematical Structures in Computer Science* 29(7), 938-971.
  [doi:10.1017/S0960129518000488](https://doi.org/10.1017/S0960129518000488).
- Lorenzin, A. and Zanasi, F. (2025). Bayesian networks, Markov networks, moralisation,
  triangulation: a categorical perspective.
  [arXiv:2512.09908](https://arxiv.org/abs/2512.09908).
- Patterson, E., Lynch, O. and Fairbanks, J. (2022). Categorical data structures for
  technical computing. *Compositionality* 4(5).
  [doi:10.32408/compositionality-4-5](https://doi.org/10.32408/compositionality-4-5).
- Libkind, S., Baas, A., Halter, M., Patterson, E. and Fairbanks, J. P. (2022). An
  algebraic framework for structured epidemic modelling. *Phil. Trans. R. Soc. A*
  380(2233), 20210309. [doi:10.1098/rsta.2021.0309](https://doi.org/10.1098/rsta.2021.0309).
- Koller, D. and Friedman, N. (2009). *Probabilistic Graphical Models: Principles and
  Techniques*. MIT Press.
- Marcot, B. G., Steventon, J. D., Sutherland, G. D. and McCann, R. K. (2006).
  Guidelines for developing and updating Bayesian belief networks applied to ecological
  modeling and conservation. *Can. J. For. Res.* 36(12), 3063-3074.
  [doi:10.1139/x06-135](https://doi.org/10.1139/x06-135).
- Chen, S. H. and Pollino, C. A. (2012). Good practice in Bayesian network modelling.
  *Environmental Modelling & Software* 37, 134-145.
  [doi:10.1016/j.envsoft.2012.03.016](https://doi.org/10.1016/j.envsoft.2012.03.016).

The full bibliography for the ecosystem is `docs/src/references.bib` (also in
`vignettes/references.bib`); the rendered list is the References page of the
[documentation](https://ecorecipes.github.io/BayesianNetworks.jl/).
