# API Reference

## Schemas and types

```@docs
SchVariableSpace
SchBayesNet
AbstractVariableSpace
AbstractBayesNet
VariableSpaceUntyped
BayesNetUntyped
VariableSpace
BayesNet
```

## Kernel references

```@docs
KernelRef
NamedRef
PointMassRef
PolicyRef
NoRef
```

## Construction

```@docs
bayesnet
add_variable!
add_state!
add_mechanism!
add_input!
variable_id
mechanism_id
reference_habitat_bn
reference_habitat_model
```

## Inspection

```@docs
variables
variable_names
variable_name
has_variable
state_ids
states
nstates
space_ref
mechanisms
mechanism_names
mechanism_name
kernel_ref
target
input_ids
inputs
mechanism_of
has_mechanism
parents
children
exogenous
roots
```

## Derived graphs

```@docs
variable_graph
is_acyclic
topological_order
moral_graph
```

## Validation

```@docs
validate
validation_errors
Base.isvalid(::AbstractBayesNet)
```

## Canonical forms

```@docs
canonicalize
is_isomorphic
```

## Serialisation

```@docs
json_bayesnet
parse_json_bayesnet
write_json_bayesnet
read_json_bayesnet
schema_json
json_model
parse_json_model
write_json_model
read_json_model
json_card
parse_json_card
read_json_card
```

## Reporting: model cards and provenance

The reporting record that travels with a model (SPEC section 49; the ecology
literature's minimum reporting standard). A [`ModelCard`](@ref) is metadata only: it
never changes a kernel, an evaluation or the equality of two models.

```@docs
ModelCard
ParameterProvenance
SOURCE_TYPES
CARD_SCHEMA_VERSION
provenance
provenance!
undocumented_mechanisms
report
```

## Open networks and composition

Open networks (`Open`, `apex`, `inputs`, `outputs`, the legs) and the operations on them
(`compose`, `glue`, `otimes`, `oapply`, `validate_composition`, `substitute`) are in
`CategoricalBayesianNetworks.jl`. What stays here is the interface machinery they build
on.

```@docs
rename_variable
```

## Models, observation and interventions

```@docs
BayesModel
BayesModel(::BayesModel)
MechanismRecord
mechanism_record
ModelEvent
syntax
spaces
kernels
evidence
history
extras
validate(::BayesModel)
observe
unobserve
do_intervention
soft_intervention
hard_intervention_name
intervened_variables
is_intervened
```

## Semantics: spaces and kernels

The kernel API comes from FiniteKernels.jl and is re-exported: `FiniteAxis`,
`FiniteSpace`, `FiniteKernel`, `cpt`, `state`, `point_mass`, `uniform`, `random_kernel`,
`probability`, `marginal`, `is_normalized`, `kernel_matrix`, `factors`, `labels`,
`joint_states`, `evaluate`, `FreeMarkovCategory`, `mcopy`, `delete`, `braid`.

```@docs
axis
syntax_space
syntax_spaces
space
parent_space
bind_kernel
bind_cpt
kernel
missing_kernels
has_semantics
semantic_errors
Base.isapprox(::BayesModel, ::BayesModel)
```

## Reference evaluation

```@docs
joint_distribution
JointTable
joint_table
marginal(::BayesModel, ::AbstractVector{Symbol})
conditional
sample
empirical_marginal
```

The categorical route to the same joint (`to_free_expression`, `free_generators`,
`categorical_joint`) and the semantics of an open network (`interpret`) are in
`CategoricalBayesianNetworks.jl`.

## Dynamic networks

Time-indexed templates (SPEC section 43) that [`unroll`](@ref) into ordinary closed
networks over a finite horizon. Lagged inputs follow the naming convention
[`lagged`](@ref) (`X[t-1]`); unrolled variables are named [`variable_at`](@ref) (`X_t`).
The boundary convention is documented in the module docstring of `src/dynamic.jl`: with
maximal lag `L` the initial network covers slices `0` to `L - 1` and the transition
template every later slice, so unrolling is exact.

```@docs
lagged
lag_of
is_lagged
variable_at
time_index
slice_variables
horizon
is_unrolled
UNROLLED_EXTRA
DynamicBayesNet
initial_network
transition_network
lags
current_variables
lagged_variables
validation_errors(::DynamicBayesNet)
validate(::DynamicBayesNet)
Base.isvalid(::DynamicBayesNet)
unroll
initial_slice
transition_slice
DynamicBayesModel
template
bind_kernel(::DynamicBayesModel, ::Pair{Symbol,<:FiniteKernel})
kernel(::DynamicBayesModel, ::Symbol)
missing_kernels(::DynamicBayesModel)
has_semantics(::DynamicBayesModel)
validate(::DynamicBayesModel)
filter_marginal
rollout
vegetation_herbivore_dbn
vegetation_herbivore_model
```

## File formats

```@docs
BayesModel(::NetworkIR)
NetworkIR(::BayesModel)
ir_extras
read_bayesnet
write_bayesnet
```

## Graphics

Drawings are `Graphviz.Graph`s built by the package's own `Graphviz` submodule (a
minimal DOT abstract syntax tree, exported as `Graphviz`) and render to SVG with
`show(io, MIME"image/svg+xml"(), g)` through Graphviz_jll.
`CategoricalBayesianNetworks.jl` adds `to_graphviz` methods for open networks and for
wiring diagrams.

```@docs
to_graphviz
to_graphviz(::AbstractBayesNet)
BayesianNetworks.Graphviz
BayesianNetworks.Graphviz.Graph
BayesianNetworks.Graphviz.Digraph
BayesianNetworks.Graphviz.Node
BayesianNetworks.Graphviz.Edge
BayesianNetworks.Graphviz.NodeID
BayesianNetworks.Graphviz.Subgraph
BayesianNetworks.Graphviz.Attributes
BayesianNetworks.Graphviz.Expression
BayesianNetworks.Graphviz.Statement
BayesianNetworks.Graphviz.pprint
BayesianNetworks.Graphviz.run_graphviz
BayesianNetworks.Graphviz.UnavailableGraphvizError
BayesianNetworks.Graphviz.UnknownLayoutProgramError
```

The wiring-diagram view (`VariablePort`, `MechanismBox`, `BayesWiringDiagram`,
`to_wiring_diagram`, `from_wiring_diagram`, `to_hom_expr`, `wiring_expression`) is in
`CategoricalBayesianNetworks.jl`.

## CatColab export

Export-only: CatColab does not yet have a Bayesian-network theory. The schema is written
as a model of the `simple-schema` theory and a network as a diagram in it; the
presentation of the free Markov category is written as `markov-presentation/0.1`.

```@docs
CATCOLAB_NAMESPACE
catcolab_uuid
catcolab_model
catcolab_schema_document
parse_catcolab_schema
catcolab_instance_document
presentation_json
parse_presentation_json
```

## Exceptions

```@docs
BayesNetError
UnknownVariableError
UnknownMechanismError
CyclicBayesNetError
MissingMechanismError
DuplicateGeneratorError
DanglingReferenceError
PositionError
DuplicateStateError
SelfInputError
DuplicateNameError
NameClashError
FormatError
InterfaceError
InterfaceMismatchError
UnknownStateError
NoEvidenceError
MissingKernelError
KernelBindingError
UnnormalizedKernelError
ImpossibleEvidenceError
ModelTooLargeError
UnsupportedNodeKindError
WiringDiagramError
DynamicTemplateError
HorizonError
NotUnrolledError
```
