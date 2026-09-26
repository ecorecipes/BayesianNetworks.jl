# BayesianNetworks.jl

Compositional Bayesian belief networks as attributed C-sets: mechanisms, interventions, dynamic
networks and reference finite-stochastic semantics.

## Place in the ecosystem

Dependency order (arrows = depends on):
EcologicalBayesianNetworks → InfluenceDiagrams → BayesianNetworkInference → BayesianNetworks →
FiniteKernels, and BayesianNetworks → BayesianNetworkFormats (both Catlab-free).
This package depends on ACSets, GATlab, Graphs, Graphviz_jll, JSON3, StructTypes,
OrderedCollections, FiniteKernels (kernels) and BayesianNetworkFormats (`NetworkIR`, readers and
writers). It **must not depend on Catlab or MarkovCategories** (ADR 0009); `Pkg.status(mode =
PKGMODE_MANIFEST)` is the check. The Catlab half -- open networks as structured cospans, their
composition, the wiring-diagram view and the free Markov-category semantics -- is
`CategoricalBayesianNetworks.jl`, which sits beside this package rather than under it and
re-exports every name here. Sibling packages are expected at `../<Name>.jl`, declared via
`[sources]` in `Project.toml`.

## Invariants that must not be broken

- Structural syntax (ACSets) and numerical semantics (kernels, utilities) stay separate; CPT arrays are never ACSet attributes.
- Parent / input order is explicit (`input_position`) and total. Never rely on part-id order.
- Axis conventions: user-facing CPTs are `(parents..., child)` normalised over the last axis; FinStoch kernels internally are outputs-first. Convert with the documented `permutedims`, never by hand.
- Observation (`observe`) and intervention (`do_intervention`) are different operations and stay different.
- Every optimised path is checked against a slower oracle (`joint_distribution`, exhaustive policy search) on small models.

## Commands

```sh
julia --project -e 'using Pkg; Pkg.instantiate(); Pkg.test()'   # the test suite
julia --project=docs docs/make.jl                                 # build docs locally
cd vignettes && quarto render                                     # render vignettes to html/gfm/pdf (julia engine; PDF needs lualatex + ../fonts/JuliaMono)
julia scripts/sync_vignettes.jl [--check]                         # copy vignettes into docs/src/tutorials
```

## File layout

- `src/refs.jl`: `KernelRef` sum type and its StructTypes (JSON) definitions.
- `src/graphviz.jl`: the `Graphviz` submodule -- a minimal DOT abstract syntax tree
  (`Graph`, `Digraph`, `Node`, `Edge`, `NodeID`, `Subgraph`, `Attributes`), `pprint` and
  `run_graphviz`, which runs the `Graphviz_jll` binaries with the `Cmd`'s own environment.
  It replaces `Catlab.Graphics.Graphviz`: the names, the fields and the printed DOT are the
  same, which is what lets `InfluenceDiagrams.jl` and the tests keep working unchanged.
- `src/schemas.jl`: `SchVariableSpace`, `SchBayesNet` (ACSets.jl `BasicSchema` values, not
  Catlab `@present` presentations: `FreeSchema` is Catlab-only), abstract and concrete ACSet
  types (`BayesNet`). Normative. The generator order matches what `@present Sch <: Sch0`
  produced, so `generate_json_acset_schema` emits exactly the same JSON as before. The Lean
  project holds a second, hand-written copy of the same schema and emits it as
  `proofs/schemas/*.json`; the two are *checked to agree* (`emit_schema --check` in the Lean
  workflow, and `test_serialization.jl` in Julia). Neither is generated from the other, so
  neither is the source of truth for the other: change both together. A downstream schema
  extension is built by appending to `objects` / `homs` / `attrtypes` / `attrs` of
  `SchBayesNet` (see `InfluenceDiagrams.jl` and `test/test_interventions.jl`).
- `src/errors.jl`: typed exceptions (`BayesNetError` subtypes) with `showerror` messages.
- `src/construction.jl`: `add_*!` builders, `bayesnet` DSL, name lookups.
- `src/inspection.jl`: read-only accessors (`states`, `parents`, `inputs`, ...), ordered by positions.
- `src/graph.jl`: derived `variable_graph` (a Graphs.jl `SimpleDiGraph`), `topological_order`
  (Kahn), `moral_graph` (a `SimpleGraph`). Vertex id = variable part id.
- `src/validation.jl`: `validate`, `validation_errors`, `Base.isvalid`.
- `src/canonicalize.jl`: deterministic renumbering (`canonicalize`, built on
  `_canonical_copy(bn, variable_order)`) and `is_isomorphic`. When variable names repeat the
  canonical form is not unique, so `is_isomorphic` searches the orderings that permute equally
  named variables (`_isomorphic_by_search`, capped by `max_orderings`, `ModelTooLargeError`
  beyond it). This replaces the Catlab homomorphism search; it is exact for valid networks,
  where only variable-name ties are free (states and inputs are ordered by their `*_position`
  attributes and mechanisms by target and name).
- `src/serialization.jl`: JSON envelope around ACSets' JSON, `schema_json`.
- `src/examples.jl`: `reference_habitat_bn` (SPEC §45, structure; states match the Formats
  `habitat_reference` fixtures) and `reference_habitat_model` (the fixture's CPTs bound);
  `vegetation_herbivore_dbn` / `vegetation_herbivore_model` (SPEC §43 dynamic example,
  optional `management`).
- `src/model.jl`: `BayesModel{S,Sp,K}` wrapper (syntax, spaces, kernels, evidence, history,
  extras), `ModelEvent`, `MechanismRecord`, `mechanism_record(bn, m)` (the snapshot stored
  in events), `validate(::BayesModel; atol)`. Provenance, evidence and metadata live here,
  never in the ACSet. A `ModelEvent`'s wall-clock `time` is kept, shown and serialised but
  excluded from `==` / `hash` (`_EVENT_VALUE_FIELDS`), so the same sequence of operations
  always gives equal models (SPEC §49, §52). `BayesModel(bn)` builds `FiniteSpace`s from the syntax and starts
  with `Dict{KernelRef,FiniteKernel}()`; `BayesModel(m; syntax, spaces, kernels, evidence,
  history, extras)` is the public copy-with-replacements constructor (`_with` is its
  alias) that every operation and downstream wrapper uses. Containers are copied but syntax,
  kernel arrays and nested values may be shared; this is not deep immutability. Every accessor of
  `inspection.jl` and `graph.jl` also takes a `BayesModel` and reads `syntax(m)`
  (generated by a loop at the end of the accessors).
- Open networks and their composition (`src/open.jl`, `src/composition.jl`, `src/wiring.jl`)
  moved to `CategoricalBayesianNetworks.jl`. What stayed behind for them: `VariableSpace`,
  the interface exceptions in `src/errors.jl`, `_state_table` in `src/inspection.jl`, and the
  brute-force factor machinery of `src/evaluation.jl`.
- `src/interventions.jl`: `observe` / `unobserve` (wrapper only), `do_intervention` and
  `soft_intervention` (local mechanism rewrites, on any `AbstractBayesNet`, returning the
  same type via `deepcopy`, so InfluenceDiagrams' ACSet works, and on `BayesModel`),
  provenance. `substitute` stays on the concrete `BayesNet` (its pushout builds a
  `BayesNet` foot).
- `src/semantics.jl`: `axis` / `syntax_space(s)` / `space` / `parent_space`, `bind_kernel`,
  `bind_cpt`, `kernel` (resolution of `NamedRef` / `PolicyRef` through `kernels(m)`,
  `PointMassRef` materialised as `delete(parents) ⋅ point_mass`), `missing_kernels`,
  `has_semantics`, `semantic_errors` (SPEC §11 items 8-10), `isapprox` on models, the
  kernel-taking `soft_intervention`, `rename_variable` for a network and for a model, and the
  helpers that keep spaces and kernel axes in step with `rename_variable` and `substitute`.
  `_resolve_kernel` materialises a `PointMassRef` with FiniteKernels' own
  `compose_kernel(discard_kernel(parents), point_mass(...))`, never Catlab's `compose`/`delete`.
- `src/certificates.jl`: `proof_certificate(::BayesModel)` exports
  `finite-bn-certificate-1` for the separate literal-Lean consumer. Preserve one-based
  raw part-ID row order, explicit positions, references and every repeated-slot CPT
  column. Capture exact bound integer/rational/binary-floating values, never a
  Float64 backend conversion or decimal rational approximation. Explicit evidence
  replaces stored evidence; impossible observations are still data. The consumer's
  exact normalization result is separate from runtime `atol`. This is not the
  open-network or DVE certificate format.
- `src/evaluation.jl`: brute-force `joint_distribution` (a `FiniteKernel` state) and
  `JointTable`, `marginal` / `conditional` with evidence, `sample` / `empirical_marginal`.
  All enumerate joint states and are capped by `max_states`. The shared internals
  (`_closed_semantics`, `_factors`, `_product`, `_joint_atol`, `DEFAULT_MAX_STATES`) are used
  by `CategoricalBayesianNetworks.jl`'s `interpret`; changing their signatures changes that
  package too.
- `src/dynamic.jl`: `DynamicBayesNet(initial, transition; lags)` templates (lags by the
  naming convention `lagged(:X, k)` = `X[t-k]`, parsed by `lag_of`; unrolled names
  `variable_at(:X, t)` = `X_t`, parsed by `time_index`), `validate` / `validation_errors`
  (`DynamicTemplateError`), `unroll` by direct construction (`_add_slice!`; mechanism
  `X_mechanism` becomes `X_t_mechanism`, other names and `NamedRef`s get `_t`,
  `PointMassRef`s kept), `initial_slice` / `transition_slice` (the pieces `glue` would
  join; tests check the two constructions agree), `DynamicBayesModel` (two `BayesModel`s,
  `bind_kernel` / `bind_cpt` / `kernel` with `slice = :initial | :transition`, `unroll`
  copies kernels per slice with `_map_axes`), `filter_marginal`, `rollout`. `X_<digits>` is
  a reserved name shape: `horizon(bn)` and `slice_variables(bn, t)` read it off the names,
  but `rollout` and `horizon(::BayesModel)` use what `unroll` recorded in
  `extras(m)[UNROLLED_EXTRA]` (`:horizon`, `:lags`, `:variables`) and throw
  `NotUnrolledError` on a model `unroll` did not produce, so a plain model with a variable
  called `A_1` is never mistaken for an unrolled one. Boundary
  convention: with maximal lag `L` the initial network covers slices `0..L-1` using the
  lag notation relative to slice `L-1`, the transition covers `t >= L`; `unroll` needs
  `horizon >= L - 1` (`HorizonError`).
- `src/formats_bridge.jl`: `BayesModel(::NetworkIR)`, `NetworkIR(::BayesModel)`,
  `read_bayesnet`, `write_bayesnet`; chance nodes only (`UnsupportedNodeKindError`); titles,
  positions, comments and extras kept in `extras(m)` in the layout built by the public
  `ir_extras(ir)`. Files are read with `atol = 1e-6`; validate such models with the same
  `atol`.
- `src/modelcard.jl`: `ModelCard` (the ecology reporting standard's fields: decision
  context, endpoint, extents, graph rationale and alternatives, state definitions,
  per-mechanism `ParameterProvenance` (SPEC §49), elicitation protocol, validation summary
  and a `validation_scores` slot for BayesianNetworkInference, intended use, limitations,
  licence, versions, history), `ModelCard(m::BayesModel; kw...)` prefilled from a model,
  `provenance` / `provenance!` / `undocumented_mechanisms`, and `report` (Markdown).
  Metadata only: a card never touches a kernel, an evaluation or model equality.
- `src/serialization.jl` also holds `json_model` / `parse_json_model` / `write_json_model` /
  `read_json_model`: the same envelope plus `"semantics"`, `"evidence"`, `"history"`,
  `"extras"`, and an optional `"card"` section (`json_model(m; card)`, `json_card`,
  `parse_json_card`, `read_json_card`). Documents without a `"card"` are read as before:
  `parse_json_card` returns `nothing` for them, and the model itself parses identically.
- `src/graphics.jl`: `to_graphviz` for networks and models (a `Graphviz.Graph` built by hand)
  and `_graphviz_environment!` (called from `__init__`; kept because
  `CategoricalBayesianNetworks.jl` still uses Catlab's renderer for wiring diagrams, which
  runs the JLL binaries by bare path). `to_graphviz` is declared here as an empty generic
  function; `CategoricalBayesianNetworks.jl` and `InfluenceDiagrams.jl` add methods to it.
- `src/catcolab.jl`: `catcolab_model`, `catcolab_schema_document`, `parse_catcolab_schema`,
  `catcolab_instance_document`, `presentation_json` / `parse_presentation_json`,
  `catcolab_uuid` (UUID v5 in `CATCOLAB_NAMESPACE`); documents are `OrderedDict`s.
- `test/helpers.jl`: `abiotic_bn` and `biotic_bn`, the two halves of the reference network
  (the same pair `CategoricalBayesianNetworks.jl` composes), included first by `runtests.jl`.
- `test/test_*.jl`: one file per source file; `test_causal.jl` (numeric observe-versus-do,
  soft interventions), `test_properties.jl` (random DAGs with `random_kernel`),
  `test_formats_bridge.jl` (fixtures via `fixture_path`, asia oracle), `test_model_json.jl`,
  `test_modelcard.jl` (card construction, provenance, Markdown headings, JSON round trip and
  card-less backwards compatibility);
  `test_serialization.jl` compares `schema_json` with `proofs/schemas/*.schema.json` when
  present; `test_graphics.jl`, `test_catcolab.jl`;
  `test_dynamic.jl` (template validation, forward marginals against a
  hand recursion, two lags, and `BayesianNetworkInference.infer` on horizon 8 against brute
  force on horizon 4; BayesianNetworkInference is a test-only dependency declared in
  `[extras]` with a `[sources]` path). The categorical halves of `test_causal.jl`,
  `test_properties.jl`, `test_semantics.jl`, `test_formats_bridge.jl`, `test_evaluation.jl`
  and `test_dynamic.jl`, and all of `test_open.jl`, `test_composition.jl` and
  `test_wiring.jl`, are in `CategoricalBayesianNetworks.jl`.
- `vignettes/0N_*/0N_*.qmd`: the five vignettes (mechanisms, Graphviz and brute-force
  evaluation; observation versus intervention; serialisation and CatColab; dynamic networks;
  model cards and provenance); `vignettes/Project.toml` adds ACSets, JSON3, Random. The
  wiring-diagram and open-network vignettes are `CategoricalBayesianNetworks.jl`'s 01 and 02.

## What the Lean project does and does not prove

`proofs/` proves Propositions 1, 2, 3 and 4 and the open-network closure theorem `sorry`-free
(axioms `propext`, `Classical.choice`, `Quot.sound`). The following qualifications must survive every
rewording of the README, the docs and the vignettes:

- The original `FinBayesNet` / `OpenFinBayesNet` layer has finite variable/mechanism
  types, unordered parent sets and functional kernels. `Finite/RawRecords.lean` now
  compiles checked attributed rows into that reduct: bounded unique owner positions
  derive positional bijections, causal ranks derive an order, and repeated slots
  read the same assignment coordinate. `Finite/ReferenceTables.lean` checks finite
  named/policy bindings, point-mass labels, complete raw columns, axis labels,
  nonnegative rational entries and exact normalization separately. The literal
  certificate consumer uses `decide +kernel`, not native-decision axioms.
  `proof_certificate` is the Julia producer; the full language/compiler/JSON/array
  correspondence is still not a theorem.
- The Lean project has not moved, although `Finite/Open.lean` is about the layer that now
  lives in `CategoricalBayesianNetworks.jl`: it also emits the `SchBayesNet` schema JSON that
  this package's `test_serialization.jl` compares against, and a Lake project with a shared
  `packagesDir` is not worth splitting for that alone.
- Proposition 3 has both the split form `marg_joint_compose_split` and the own-variable
  `osem_compose` in `Finite/OpenSemantics.lean`. The stronger `osem_compose_glue` needs no
  locality, normalisation or match surjectivity, but retains disjoint input/output sets.
  Its match consumes every B input and may leave unused A outputs; it does not cover
  arbitrary two-sided partial gluing or pass-through interfaces.
- `Finite/VariableElimination.lean` proves a scoped finite-function bucket algorithm,
  compilation from local mechanisms and elimination-order independence.
  `Assignments.lean` / `Posterior.lean` prove clamping versus indicator conditioning,
  genuine posterior distributions on retained assignments, and global zero-mass
  rejection. Do not equate a normalized empty-query posterior with Julia's
  unnormalized empty `infer` result.
- `Finite/JunctionTree.lean` proves cached collect/distribute computation, not an
  assumed-correct message trace. Its hypotheses are running intersection, complete
  factor assignment and variable coverage; grafting handles arbitrary branching.
  Its virtual-root forest beliefs are global. Julia's raw beliefs are component-local
  and need outside-component scalar factors before comparison.
- `Finite/DSeparation.lean` derives the conditional-independence identity from
  moralized ancestral graph separation and normalized local kernels. It does not
  verify a concrete Julia graph-query routine. `NumericalContracts.lean` proves
  explicit input/rounded-product error bounds and a posterior bound with positive
  evidence-mass floor; IEEE local arithmetic contracts remain assumptions to discharge.
- All former Roadmap holes are discharged, and the compatibility Roadmap target also
  builds warning-free. Every headline theorem belongs in `Audit.lean`.

The new general boundary-map category is proved separately in
`CategoricalBayesianNetworks.jl/proofs/` (ADR 0010), with structural-isomorphism
equality and coherent copy/discard. Its general exact FinStoch interpretation is
now a proved strong braided monoidal functor; the full Julia/ACSet runtime
refinement remains separate. The `InfluenceDiagramsProofs/Finite/DVE/`
modules in the influence-diagram proof project prove the exact finite-function algorithm, including generated strong
schedules, policy reconstruction, realized optimality and all-row probability-guard
completeness without strict positivity. Literal floating-point/array refinement is
still not proved. Keep this section, `README.md`, `docs/src/index.md`
and the SPEC revision note in step with proof coverage. Architectural changes get a new
ADR rather than a rewrite of the historical ADR 0005.

## Semantics conventions

- Normalisation tolerance: every kernel check (`bind_kernel`, `bind_cpt`,
  `soft_intervention` with a kernel, `semantic_errors`, `validate(::BayesModel)`) takes
  `atol`, defaulting to FiniteKernels' `DEFAULT_ATOL` (`1e-8`, re-exported). Never
  hard-code a tolerance literal.
- The brute-force evaluators take it too and forward it to the validation, the
  per-mechanism check and the kernel they return: `joint_distribution`, `joint_table`,
  `marginal`, `conditional`, `sample`, `categorical_joint` and `interpret`, through
  `_closed_semantics(m, max_states, atol)` and `_factors(...; atol)`. A model read from a
  file at `atol = 1e-6` must be *evaluated* at `1e-6` as well, which is what lets
  InfluenceDiagrams.jl's `expected_utility` and the model zoo work without renormalising
  the tables. The returned joint is checked at `_joint_atol(atol, nmechanisms)`, using
  the multiplicative nonnegative row-mass budget `(1 + atol)^n - 1`, not a first-order
  linear approximation. This algebraic budget is not a floating-point forward-error certificate.

- `kernel(m, :X)` has `dom == parent_space(m, :X)` (parents in `input_position` order) and
  `codom == space(m, :X)`; axis names are variable names and labels are state names.
- `bind_kernel` on a `NoRef` mechanism assigns `NamedRef(string(mechanism_name))` and returns
  a model with an updated syntax; refs survive colimits, which is why `interpret` looks kernels
  up by `KernelRef` (a `Dict{Symbol,FiniteKernel}` keyed by target name also works).
- `validate(m)` checks bound kernels and stored spaces; `validate(m; semantics = true)` also
  demands that every mechanism resolves. Evaluators call
  `validate(m; closed = true, unique_names = true, semantics = true, atol = atol)`.
- Re-exported from FiniteKernels: the kernel and space API (`FiniteAxis`, `FiniteSpace`,
  `FiniteKernel`, `cpt`, `state`, `point_mass`, `uniform`, `random_kernel`, `deterministic`,
  `probability`, `marginal`, `is_normalized`, `is_stochastic`, `kernel_matrix`, `factors`,
  `labels`, `axis_names`, `joint_states`), the SPEC §3.2 wiring operations under their own
  names (`tensor_space`, `compose_kernel`, `tensor_kernel`, `identity_kernel`, `copy_kernel`,
  `discard_kernel`, `swap_kernel`, `apply`) and `DEFAULT_ATOL`. Use those, not Catlab's
  `compose` / `otimes` / `mcopy` / `delete`, which exist only once `MarkovCategories.jl` is
  loaded. From ACSets: `nparts`, `parts`, `subpart`, `incident`, `has_subpart`, `add_part!`,
  `set_subpart!`, `cascading_rem_part!` and `acset_schema` (the README Quick Start uses it).
  Keep this list and the `export` block in `src/BayesianNetworks.jl` in step.
- Name clashes with the siblings: of the names this package also defines,
  BayesianNetworkFormats exports `validate`, `topological_order`, `joint_distribution`,
  `marginal` and `NotNormalizedError`. `using FiniteKernels` is blanket, while
  BayesianNetworkFormats is imported name by name (`NetworkIR`, the node types,
  `read_network`, `write_network`, `fixture_path`) and otherwise qualified. FiniteKernels'
  normalisation error is `KernelNormalizationError` (SPEC §54); only BayesianNetworkFormats
  has a `NotNormalizedError`, and neither is re-exported here. `validate`, `is_isomorphic`
  and `to_graphviz` are this package's own functions now, not Catlab's;
  `CategoricalBayesianNetworks.jl` and `InfluenceDiagrams.jl` import them from here.

## Graphviz and CatColab: what to know

- `src/graphviz.jl` is a stand-alone submodule with no dependency on the rest of the package;
  it mirrors `Catlab.Graphics.Graphviz` closely enough that code written against that module
  works unchanged. Attribute lists are `OrderedDict{Symbol,String}`; a plain `Dict` passed in
  has its keys sorted, so the printed DOT is deterministic.
- `run_graphviz` copies `env` and `dir` off the `Cmd` that `Graphviz_jll.dot()` returns,
  because interpolating a `Cmd` into a backtick expression keeps only its arguments. The
  `_graphviz_environment!` hack in `src/graphics.jl` stays for Catlab's renderer, which
  `CategoricalBayesianNetworks.jl` uses for wiring diagrams.
- The Graphviz_jll dependency is genuine, not inherited: this package renders its own
  drawings.
- CatColab documents follow `notebook-types` v1 (`notebook = {cellContents, cellOrder}`);
  ids are UUID v5 of `name/kind/generator`, so documents are reproducible. Export-only.
  `catcolab_model` and friends accept an ACSet type, an ACSets `Schema` (which is what
  `SchBayesNet` now is) or a GATlab `Presentation`, so a Catlab user can still pass one.

## Files not to edit by hand

- `docs/src/tutorials/` is generated by `scripts/sync_vignettes.jl`.
- `vignettes/*/*.md`, `*.html`, `*.pdf` and `*_files/` are quarto output; edit the `.qmd`.
- `proofs/schemas/*.json` (where present) is emitted by the Lean project; edit the Lean source.

## Style

JuliaFormatter `yas`; docstrings on every exported name, which `test/test_docstrings.jl` enforces; the docs
build is strict (no `warnonly`), so a docstring left out of the manual or a broken `@ref` fails it; typed
exceptions with variable names in the message; no emojis in code or docs.
