# BayesianNetworks.jl

Compositional Bayesian belief networks as attributed C-sets: mechanisms, interventions, dynamic networks and reference finite-stochastic semantics.

The package has two layers. The **structural layer** says how a network is represented, built, inspected, validated and serialised; how networks are rewritten (interventions); and what the `BayesModel` wrapper carries (evidence, provenance). The **semantic layer** binds a finite stochastic kernel from FiniteKernels.jl to every mechanism and evaluates models: brute-force joints, marginals and conditionals, ancestral sampling, dynamic templates unrolled over a horizon, and a bridge to the file formats of BayesianNetworkFormats.jl.

It depends on ACSets and GATlab but **not** on Catlab (ADR 0009). Open networks as structured cospans, their composition (`compose`, `glue`, `otimes`, `oapply`, `substitute`), the wiring-diagram view and the categorical evaluators (`to_free_expression`, `categorical_joint`, `interpret`) are in `CategoricalBayesianNetworks.jl`, which adds them as methods and types on top of everything here.

## Representation

A network is an ACSet on the schema `SchBayesNet`, which extends the interface schema `SchVariableSpace`:

| Object | Homs | Attributes |
|---|---|---|
| `Variable` | | `variable_name::Label`, `space_ref::Ref` |
| `State` | `state_variable → Variable` | `state_name::Label`, `state_position::Position` |
| `Mechanism` | `target → Variable` | `mechanism_name::Label`, `kernel_ref::Ref` |
| `Input` | `input_mechanism → Mechanism`, `input_variable → Variable` | `input_position::Position` |

There is no primitive edge: an arrow `X → Y` is an `Input` saying that `X` is an argument of the mechanism generating `Y`. The DAG is a derived view ([`variable_graph`](@ref), a Graphs.jl `SimpleDiGraph` whose vertex ids are the variable part ids). Parent order is explicit (`input_position`) and state order is explicit (`state_position`); part ids never define an order.

The standard type is [`BayesNet`](@ref)` = BayesNetUntyped{Symbol, Int, KernelRef}`. Attribute slots of type `Ref` hold a [`KernelRef`](@ref): [`NamedRef`](@ref), [`PointMassRef`](@ref), [`PolicyRef`](@ref) or [`NoRef`](@ref). The structural layer never stores numerical tables.

## Building a network

```julia
using BayesianNetworks

bn = bayesnet(:Climate => [:dry, :normal, :wet],
              :Irrigation => [:low, :high],
              :SoilMoisture => [:low, :medium, :high];
              mechanisms = [:SoilMoisture => (:Climate, :Irrigation)])

validate(bn; closed = true)                 # nothing: every variable has one mechanism
states(bn, :SoilMoisture)                    # [:low, :medium, :high]
variable_name.(Ref(bn), parents(bn, :SoilMoisture))   # [:Climate, :Irrigation]
variable_name.(Ref(bn), topological_order(bn))
```

`bayesnet` gives every unlisted variable a prior mechanism (`closed = true`); pass `closed = false` to leave them exogenous. The mutating builders `add_variable!`, `add_state!`, `add_mechanism!` and `add_input!` give full control. [`reference_habitat_bn`](@ref) builds the reference ecological network used throughout the tests.

## Validation

[`validate`](@ref) throws the first violation as a typed exception; [`validation_errors`](@ref) collects them all and `isvalid` reports a `Bool`. Open networks (variables without a mechanism) are accepted unless `closed = true`. Duplicate variable and mechanism names are reported only with `unique_names = true`, because tensoring networks legitimately repeats names.

## Canonical forms and serialisation

ACSet equality is sensitive to part numbering, so [`canonicalize`](@ref) renumbers parts deterministically (variables by name, states by position, mechanisms by target, inputs by position); [`is_isomorphic`](@ref) compares canonical forms. [`json_bayesnet`](@ref) / [`parse_json_bayesnet`](@ref) and the file variants wrap ACSets' JSON representation in a `{"format", "schema_version", "acset"}` envelope, and [`schema_json`](@ref) returns the schema description that CI compares against the schema emitted by the Lean project in `proofs/`. The Lean `SchemaDesc` terms and the Julia `BasicSchema` declarations are two hand-written definitions checked to agree (`lake exe emit_schema --check` and a Julia test); neither is generated from, or the source of truth for, the other.

## Open networks and composition

An open network -- a `BayesNet` apex with an input and an output interface, each a [`VariableSpace`](@ref) embedded into the apex by a leg of a structured cospan -- is the subject of `CategoricalBayesianNetworks.jl`, together with `compose`, `glue`, `otimes`, `oapply` and `substitute`. The pieces that live here are the ones that need no category theory: [`VariableSpace`](@ref) itself, [`validate`](@ref), the interface errors ([`InterfaceError`](@ref), [`InterfaceMismatchError`](@ref), [`NameClashError`](@ref)) that the composition operations throw, and [`rename_variable`](@ref), which lines up interfaces that differ only by name.

## Models, observation and interventions

A [`BayesModel`](@ref) wraps a network with the semantic objects to be bound later (`spaces`, `kernels`), the `evidence` recorded by [`observe`](@ref) and a `history` of mechanism rewrites. Observation never touches the syntax; an intervention is a local rewrite that removes one mechanism (with its inputs) and adds one:

```julia
m = BayesModel(reference_habitat_bn())
m1 = observe(m, :Climate => :dry)                              # evidence only
m2 = do_intervention(m1, :Vegetation => :dense)                # do[Vegetation=dense], PointMassRef(:dense)
m3 = soft_intervention(m2, :Occupancy => NamedRef("k"); parents = [:Vegetation])
intervened_variables(m3)                                       # [:Vegetation, :Occupancy]
history(m3)[1].removed                                         # the original Vegetation mechanism
```

## Semantics: binding kernels

A model's spaces are read from the syntax (`FiniteAxis(name, states)` per variable). A kernel is bound to a mechanism with [`bind_kernel`](@ref) (a `FiniteKernel` whose domain is the tensor of the parents' spaces, in `input_position` order, and whose codomain is the variable's space) or [`bind_cpt`](@ref) (a parents-first / child-last table, ADR 0002). The kernel is stored under the mechanism's `kernel_ref`; a `NoRef` mechanism receives `NamedRef("<mechanism name>")`. [`validate`](@ref validate(::BayesModel)) checks shapes and normalisation (SPEC §11 items 8-10) and, with `semantics = true`, that every mechanism resolves.

```julia
m = BayesModel(reference_habitat_bn())
m = bind_cpt(m, :Climate => [0.3, 0.5, 0.2])
m = bind_cpt(m, :Occupancy => [0.8 0.2; 0.25 0.75])      # rows = HabitatQuality
missing_kernels(m)                                        # the five still unbound
m = reference_habitat_model()                             # all seven bound
kernel(m, :Occupancy)                                     # FiniteKernel HabitatQuality -> Occupancy
```

## Evaluation

[`joint_distribution`](@ref) enumerates every assignment and returns the joint as a state `I -> X_1 ⊗ ... ⊗ X_n` (a `FiniteKernel`, so it composes); [`joint_table`](@ref) gives a named-axis array. [`marginal`](@ref marginal(::BayesModel, ::AbstractVector{Symbol})) conditions on the model's evidence and sums out the rest; [`conditional`](@ref) returns a kernel. [`sample`](@ref) draws ancestrally in topological order and [`empirical_marginal`](@ref) turns the draws back into a state. `CategoricalBayesianNetworks.jl`'s `categorical_joint` computes the same joint by building the string diagram as a `FreeMarkovCategory` expression and evaluating it with MarkovCategories' functor; its tests check the two against each other (Proposition 1).

Every one of them takes `atol`, the normalisation tolerance used for the validation, the per-mechanism kernel check and the kernel returned. A model read from a file carries rounded probabilities ([`read_bayesnet`](@ref) uses `1e-6`) and must be evaluated with the tolerance it was read with, exactly as [`validate`](@ref validate(::BayesModel)) requires: `marginal(m, :Occupancy; atol = 1e-6)`.

Observation and intervention are different operations and give different numbers:

```julia
m = reference_habitat_model()
marginal(m, :Occupancy).table                               # prior
marginal(observe(m, :Vegetation => :dense), :SoilMoisture)   # conditioning moves SoilMoisture
marginal(do_intervention(m, :Vegetation => :dense), :SoilMoisture) ≈ marginal(m, :SoilMoisture)   # do does not
```

`CategoricalBayesianNetworks.jl`'s `interpret` gives the kernel `⊗ inputs -> ⊗ outputs` of an open network, with `interpret(compose(A, B)) ≈ compose(interpret(A), interpret(B))` and likewise for `otimes` (Propositions 2 and 3). Both are checked by that package's test suite and proved in the Lean project here for the abstract finite model (`Finite/Tensor.lean`, `Finite/Open.lean`), which also proves the closure theorem: composition along a matched interface preserves the typed-interface rule, acyclicity included. Proposition 3 is proved in the split form `marg (S ∪ T) ⟦B ∘ A⟧ = marg S (⟦A⟧ · marg T ⟦B⟧)`; its restatement in terms of each side's own open semantics is the project's one remaining `sorry`.

## Dynamic networks

Feedback through time is expressed by a [`DynamicBayesNet`](@ref): an initial network
and a transition template in which lagged inputs are named [`lagged`](@ref)`(:X, k)`
(`X[t-1]`). [`unroll`](@ref)`(dbn, h)` compiles the template into a closed network over
slices `0, ..., h` with variables `X_t` ([`variable_at`](@ref)); with maximal lag `L`
the initial network covers slices `0` to `L - 1`, so every lagged parent exists and the
construction is exact. A [`DynamicBayesModel`](@ref) binds kernels to both templates
and unrolls to an ordinary `BayesModel`, so evaluation, evidence, interventions and
BayesianNetworkInference.jl apply unchanged; [`rollout`](@ref) and
[`filter_marginal`](@ref) give per-slice marginals by brute force.

```julia
dm = vegetation_herbivore_model()          # Vegetation_t -> Herbivores_t, Herbivores_{t-1} -> Vegetation_t
um = unroll(dm, 3)                         # a closed BayesModel over slices 0..3
[k.table[2] for k in rollout(um, :Vegetation)]     # P(Vegetation_t = dense), t = 0..3
marginal(do_intervention(um, :Herbivores_2 => :high), :Vegetation_3)
```

Unrolling agrees with gluing consecutive slices as open networks:
`glue(Open(initial_slice(dbn); outputs = ...), Open(transition_slice(dbn, 1); inputs = ..., outputs = ...); along = ...)`
has the same canonical apex as `unroll(dbn, 1)`.

## Drawings

[`to_graphviz`](@ref) on a network or a model draws the derived DAG: one node per variable labelled with its states, evidence shaded, a hard intervention labelled `do(X = x)` with a double border. The result is a `Graphviz.Graph`, the DOT syntax tree of the package's own [`Graphviz`](@ref BayesianNetworks.Graphviz) submodule, which renders to SVG through Graphviz_jll in notebooks and quarto.

```julia
m = reference_habitat_model()
to_graphviz(m)                                          # the DAG; evidence shaded, do(X = x) doubled
to_graphviz(m; states = false, rankdir = "LR")
```

The wiring-diagram view -- `to_wiring_diagram`, `from_wiring_diagram`, `to_hom_expr` and `wiring_expression`, and the Graphviz renderer for diagrams -- is in `CategoricalBayesianNetworks.jl`.

## CatColab export

[`catcolab_schema_document`](@ref) writes the ACSet schema as a CatColab model of the `simple-schema` theory (objects `Entity` / `AttrType`, morphisms `Hom(Entity)` / `Attr`, deterministic UUID v5 identifiers), [`catcolab_instance_document`](@ref) writes a network as a diagram in that model, [`catcolab_model`](@ref) gives the `catlog`-side `Model` shape and [`presentation_json`](@ref) the generators of the free Markov-category presentation. [`parse_catcolab_schema`](@ref) reads a schema document back. These are export-only: CatColab does not yet have a Bayesian-network theory.

## Files

[`read_bayesnet`](@ref) and [`write_bayesnet`](@ref) go through BayesianNetworkFormats.jl (`.dne`, `.xdsl`, `.net`, `.bif`, `.dsc`, `.uai`); `BayesModel(ir::NetworkIR)` and `NetworkIR(m)` are the underlying conversions, with titles, positions and comments kept in [`extras`](@ref). [`json_model`](@ref) writes the ACSet envelope with a `"semantics"` section (spaces and kernels), evidence and history.

```julia
m = read_bayesnet(fixture_path("dne/habitat_reference.dne"))
m ≈ reference_habitat_model()                                # true
marginal(read_bayesnet(fixture_path("bif/asia.bif")), :dysp).table   # [0.436, 0.564]
```

## Reporting: model cards and provenance

A model that will be reviewed, reused or handed to a decision maker needs more than its
tables. [`ModelCard`](@ref) is the reporting record the ecology literature's minimum
standard asks for: the decision the model serves, the endpoint and the spatial and
temporal extent it applies to, why the graph is what it is and which alternatives were
considered, what the states mean, where every table came from, how experts were
elicited, how the model was validated, what it may not be used for, and the licence and
version it is released under. [`ModelCard(m)`](@ref) prefills the structural half from a
model; [`provenance!`](@ref) records a [`ParameterProvenance`](@ref) per mechanism
(source type, citation, dataset, estimator, expert, timestamp, notes; SPEC section 49);
[`report`](@ref) writes the card as Markdown, showing rather than hiding what is still
undocumented.

```julia
card = ModelCard(m; decision_context = "grazing policy", endpoint = "Occupancy",
                 license = "CC BY 4.0")
provenance!(card, :Occupancy_mechanism =>
                  ParameterProvenance(; source_type = :elicited, expert = "panel"))
undocumented_mechanisms(card)                 # the tables still without a source
write_json_model("habitat.json", m; card = card)
read_json_card("habitat.json") == card        # true; files without a card read as nothing
print(report(card))
```

The card is metadata: it never changes a kernel, an evaluation or the equality of two
models. `validation_scores` is the slot BayesianNetworkInference.jl's scoring layer
fills.

See the Tutorials section for rendered vignettes and the API Reference for docstrings.

## References

The package is an implementation, with a checked closure condition, of established
constructions:

- [Fong2012](@citet), whose causal theories are Bayesian networks with free inputs --
  the semantics an open network carries here.
- [BaezCourser2020](@citet), the structured cospans that make `Open`, `compose` and
  `otimes` pushouts rather than name surgery.
- [JacobsKissingerZanasi2019](@citet) and [Pearl2009](@citet) for the `do` operator as
  diagram surgery and as truncated factorisation; [LorenzTull2023](@citet) for causal
  models in string diagrams generally.
- [Fritz2020](@citet) and [ChoJacobs2019](@citet) for Markov categories, string diagrams
  and disintegration, the semantics `interpret` and `conditional` compute.
- [LorenzinZanasi2025](@citet) for moralisation and categorical variable elimination.
- [PattersonLynchFairbanks2022](@citet) and [Libkind2022](@citet) for the ACSet and
  open-systems machinery this package is built on.
- [KollerFriedman2009](@citet) for the standard Bayesian-network material: the chain
  rule, ancestral sampling and moralisation.
- [Marcot2006](@citet), [ChenPollino2012](@citet) and [Kaikkonen2021](@citet) for the
  reporting practice that [`ModelCard`](@ref) implements.

Full entries are on the [References](references.md) page.

## Module

```@docs
BayesianNetworks
```
