"""
    BayesianNetworks

Compositional Bayesian belief networks as attributed C-sets: mechanisms, interventions,
and reference finite-stochastic semantics.

This module provides the structural layer: the [`SchBayesNet`](@ref) schema and
[`BayesNet`](@ref) type, builders ([`bayesnet`](@ref), `add_*!`), inspection, derived
graphs, [`validate`](@ref), [`canonicalize`](@ref) and JSON serialisation; the
[`BayesModel`](@ref) wrapper with observation and interventions ([`observe`](@ref),
[`do_intervention`](@ref), [`soft_intervention`](@ref)); the finite-stochastic
semantics on top of FiniteKernels.jl: kernels bound to mechanisms
([`bind_kernel`](@ref), [`bind_cpt`](@ref)), reference evaluation
([`joint_distribution`](@ref), [`marginal`](@ref), [`conditional`](@ref),
[`sample`](@ref)), dynamic templates unrolled over finite horizons
([`DynamicBayesNet`](@ref), [`unroll`](@ref)) and the bridge to the file formats of
BayesianNetworkFormats.jl ([`read_bayesnet`](@ref), [`write_bayesnet`](@ref)); Graphviz
drawings ([`to_graphviz`](@ref)) and export to CatColab's document format
([`catcolab_schema_document`](@ref), [`catcolab_instance_document`](@ref),
[`presentation_json`](@ref)); and the reporting layer, [`ModelCard`](@ref) with
per-mechanism [`ParameterProvenance`](@ref) and [`report`](@ref).

The package depends on ACSets and GATlab but **not** on Catlab (ADR 0009). Open
networks as structured cospans, their composition, the wiring-diagram view and the free
Markov-category semantics live in `CategoricalBayesianNetworks.jl`, which adds them as
methods and types on top of everything here.

Part of the ecorecipes compositional Bayesian-network ecosystem.
"""
module BayesianNetworks

using ACSets
using Dates: DateTime, now
using GATlab: Presentation
using Graphs: SimpleDiGraph, SimpleGraph, add_edge!
using Graphviz_jll: Graphviz_jll
using JSON3: JSON3
using OrderedCollections: OrderedDict
using StructTypes: StructTypes
using Random: AbstractRNG, default_rng
using UUIDs: UUID, uuid5
using FiniteKernels
using BayesianNetworkFormats: NetworkIR, IRVariable, ChanceNode, DecisionNode, UtilityNode,
                              read_network, write_network, fixture_path,
                              BayesianNetworkFormatsError

import FiniteKernels: marginal
import BayesianNetworkFormats: NetworkIR

# Re-exported ACSets primitives that users need to work with a `BayesNet` directly
# (part surgery, and the schema of a network; higher-level operations return new
# networks).
export nparts, parts, subpart, incident, add_part!, set_subpart!, cascading_rem_part!,
       acset_schema, has_subpart
# Re-exported FiniteKernels names: the kernel API needed to bind and read semantics,
# and the wiring operations of FinStoch under their SPEC section 3.2 names
# (`MarkovCategories.jl` binds the same operations to the Catlab generic functions).
export FiniteAxis, FiniteSpace, FiniteKernel, cpt, state, point_mass, uniform,
       random_kernel, deterministic, probability, marginal, is_normalized, is_stochastic,
       kernel_matrix, factors, labels, axis_names, joint_states, tensor_space,
       compose_kernel, tensor_kernel, identity_kernel, copy_kernel, discard_kernel,
       swap_kernel, apply, DEFAULT_ATOL
# Re-exported BayesianNetworkFormats names used by the bridge.
export NetworkIR, fixture_path
# Re-exported exception roots and types (ADR 0013). The kernel API above raises
# FiniteKernels' errors, so every exception type FiniteKernels exports is re-exported
# (test/test_errors.jl checks for drift). Of BayesianNetworkFormats only the root: the
# conformance adapters load this package with `using`, and the inspect adapter records
# Formats' concrete types under their qualified names, which a re-export would change.
export FiniteKernelsError, InvalidAxisError, KernelShapeError, KernelEntryError,
       KernelNormalizationError, SpaceMismatchError
export BayesianNetworkFormatsError

# graphviz.jl
export Graphviz
# refs.jl
export KernelRef, NamedRef, PointMassRef, PolicyRef, NoRef
# schemas.jl
export SchVariableSpace, SchBayesNet, AbstractVariableSpace, AbstractBayesNet,
       VariableSpaceUntyped, BayesNetUntyped, VariableSpace, BayesNet
# errors.jl
export BayesNetError, AnyBayesNetError
export UnknownVariableError, UnknownMechanismError, CyclicBayesNetError,
       MissingMechanismError, DuplicateGeneratorError, DanglingReferenceError,
       PositionError, DuplicateStateError, EmptyStateSpaceError, SelfInputError,
       DuplicateNameError,
       FormatError, InterfaceError, InterfaceMismatchError, UnknownStateError,
       NameClashError, NoEvidenceError, MissingKernelError, KernelBindingError,
       UnnormalizedKernelError, InvalidKernelEntryError, ProofCertificateError,
       OpenCertificateError,
       ImpossibleEvidenceError, IndeterminatePosteriorError, ModelTooLargeError,
       UnsupportedNodeKindError,
       WiringDiagramError, DynamicTemplateError, HorizonError, NotUnrolledError
# construction.jl
export variable_id, mechanism_id, add_variable!, add_state!, add_mechanism!, add_input!,
       bayesnet
# inspection.jl
export variables, variable_names, variable_name, has_variable, state_ids, states,
       nstates, space_ref, mechanisms, mechanism_names, mechanism_name, kernel_ref,
       target, input_ids, inputs, mechanism_of, has_mechanism, parents, children,
       exogenous, roots
# graph.jl
export variable_graph, is_acyclic, topological_order, moral_graph
# validation.jl
export validate, validation_errors
# canonicalize.jl
export canonicalize, is_isomorphic
# serialization.jl
export json_bayesnet, parse_json_bayesnet, write_json_bayesnet, read_json_bayesnet,
       schema_json, json_model, parse_json_model, write_json_model, read_json_model,
       json_card, parse_json_card, read_json_card
# modelcard.jl
export ModelCard, ParameterProvenance, SOURCE_TYPES, CARD_SCHEMA_VERSION, provenance,
       provenance!, undocumented_mechanisms, report
# examples.jl
export reference_habitat_bn, reference_habitat_model, vegetation_herbivore_dbn,
       vegetation_herbivore_model
# model.jl
export BayesModel, ModelEvent, MechanismRecord, mechanism_record, syntax, spaces, kernels,
       evidence, history, extras
# interventions.jl
export observe, unobserve, do_intervention, soft_intervention, intervened_variables,
       is_intervened, hard_intervention_name
# semantics.jl
export axis, syntax_space, syntax_spaces, space, parent_space, bind_kernel, bind_cpt,
       kernel, missing_kernels, has_semantics, semantic_errors, rename_variable
# certificates.jl
export proof_certificate
# evaluation.jl
export joint_distribution, JointTable, joint_table, conditional, sample,
       empirical_marginal
# dynamic.jl
export lagged, lag_of, is_lagged, variable_at, time_index, slice_variables, horizon,
       is_unrolled, UNROLLED_EXTRA,
       DynamicBayesNet, initial_network, transition_network, lags, current_variables,
       lagged_variables, unroll, initial_slice, transition_slice, DynamicBayesModel,
       template, filter_marginal, rollout
# formats_bridge.jl
export read_bayesnet, write_bayesnet, ir_extras
# graphics.jl
export to_graphviz
# catcolab.jl
export CATCOLAB_NAMESPACE, catcolab_uuid, catcolab_model, catcolab_schema_document,
       parse_catcolab_schema, catcolab_instance_document, presentation_json,
       parse_presentation_json

include("graphviz.jl")
using .Graphviz: Graphviz

include("refs.jl")
include("schemas.jl")
include("errors.jl")  # after graphviz.jl: `AnyBayesNetError` names the two Graphviz errors
include("construction.jl")
include("inspection.jl")
include("graph.jl")
include("validation.jl")
include("canonicalize.jl")
include("examples.jl")
include("model.jl")
include("interventions.jl")
include("semantics.jl")
include("certificates.jl")
include("modelcard.jl")
include("serialization.jl")
include("evaluation.jl")
include("dynamic.jl")
include("formats_bridge.jl")
include("graphics.jl")
include("catcolab.jl")

__init__() = _graphviz_environment!()

end # module
