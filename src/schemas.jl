"""
ACSet schemas for Bayesian networks, in the sense of
[PattersonLynchFairbanks2022](@cite): a network is a functor from a finitely presented
schema category into sets and attribute types, so colimits, functorial data migration
and validity checking come for free from the schema.

`SchVariableSpace` is the interface sub-schema (variables with ordered states, no
outgoing homs) that later serves as the foot type of open networks. `SchBayesNet`
extends it with mechanisms and their ordered inputs. These declarations are normative:
the Lean project in `proofs/` emits the same schema and CI compares the two.

The schemas are ACSets.jl `BasicSchema` values rather than Catlab `@present`
presentations, so that this package needs no Catlab (ADR 0009). The generator order is
the order of a `@present Sch <: Sch0` declaration -- the parent's generators first --
so `generate_json_acset_schema` produces exactly the JSON it produced before, which is
what the Lean project's `proofs/schemas/*.schema.json` is compared against.
"""

# Schema presentations
######################

"""
    SchVariableSpace

Schema of the variable / state interface: objects `Variable` and `State`,
hom `state_variable`, attribute types `Label`, `Position`, `Ref`, and attributes
`variable_name`, `space_ref`, `state_name`, `state_position`. It has no outgoing homs
from `Variable`, which is what lets it serve as the foot of an open network.
"""
const SchVariableSpace = BasicSchema([:Variable, :State],
                                     [(:state_variable, :State, :Variable)],
                                     [:Label, :Position, :Ref],
                                     [(:variable_name, :Variable, :Label),
                                      (:space_ref, :Variable, :Ref),
                                      (:state_name, :State, :Label),
                                      (:state_position, :State, :Position)])

"""
    SchBayesNet

Schema of a structural Bayesian network, extending
[`SchVariableSpace`](@ref) with objects `Mechanism` and `Input`, homs
`target: Mechanism -> Variable`, `input_mechanism: Input -> Mechanism` and
`input_variable: Input -> Variable`, and attributes `mechanism_name`, `kernel_ref`
(both on `Mechanism`) and `input_position` (on `Input`). There are no path equations.
"""
const SchBayesNet = BasicSchema([:Variable, :State, :Mechanism, :Input],
                                [(:state_variable, :State, :Variable),
                                 (:target, :Mechanism, :Variable),
                                 (:input_mechanism, :Input, :Mechanism),
                                 (:input_variable, :Input, :Variable)],
                                [:Label, :Position, :Ref],
                                [(:variable_name, :Variable, :Label),
                                 (:space_ref, :Variable, :Ref),
                                 (:state_name, :State, :Label),
                                 (:state_position, :State, :Position),
                                 (:mechanism_name, :Mechanism, :Label),
                                 (:kernel_ref, :Mechanism, :Ref),
                                 (:input_position, :Input, :Position)])

# ACSet types
#############

"""
    AbstractVariableSpace{S, Ts, P}

Abstract supertype of ACSets whose schema contains the variable / state interface
(`SchVariableSpace`). Every [`AbstractBayesNet`](@ref) is one.
"""
@abstract_acset_type AbstractVariableSpace

"""
    AbstractBayesNet{S, Ts, P} <: AbstractVariableSpace{S, Ts, P}

Abstract supertype of ACSets whose schema contains `SchBayesNet`. All inspection,
validation and graph functions accept any `AbstractBayesNet`.
"""
@abstract_acset_type AbstractBayesNet <: AbstractVariableSpace

# Plain (non-unique) indexes: uniqueness of names and targets is a validation concern,
# reported by `validate` as typed errors, never enforced inside ACSet operations.
"""
    VariableSpaceUntyped{Label, Position, Ref}

ACSet type for `SchVariableSpace` with attribute types left open. Use
[`VariableSpace`](@ref) for the standard instantiation.
"""
@acset_type VariableSpaceUntyped(SchVariableSpace;
                                 index=[:state_variable, :variable_name]) <:
            AbstractVariableSpace

"""
    BayesNetUntyped{Label, Position, Ref}

ACSet type for `SchBayesNet` with attribute types left open. Use [`BayesNet`](@ref)
for the standard instantiation.
"""
@acset_type BayesNetUntyped(SchBayesNet;
                            index=[:state_variable, :variable_name, :target,
                                   :input_mechanism, :input_variable]) <:
            AbstractBayesNet

"""
    VariableSpace

A variable space with `Symbol` labels, `Int` positions and [`KernelRef`](@ref)
references: `VariableSpaceUntyped{Symbol, Int, KernelRef}`.
"""
const VariableSpace = VariableSpaceUntyped{Symbol,Int,KernelRef}

"""
    BayesNet

A structural Bayesian network with `Symbol` labels, `Int` positions and
[`KernelRef`](@ref) references: `BayesNetUntyped{Symbol, Int, KernelRef}`.

The network stores variables with ordered states, mechanisms with a target variable, and
ordered inputs (parents) of each mechanism. It carries no numerical tables.

# Example

```jldoctest
julia> bn = bayesnet(:Rain => [:no, :yes], :Sprinkler => [:off, :on],
                     :Wet => [:dry, :wet];
                     mechanisms = [:Wet => (:Rain, :Sprinkler)]);

julia> nparts(bn, :Variable), nparts(bn, :Mechanism), nparts(bn, :Input)
(3, 3, 2)

julia> parents(bn, :Wet) .|> v -> variable_name(bn, v)
2-element Vector{Symbol}:
 :Rain
 :Sprinkler
```
"""
const BayesNet = BayesNetUntyped{Symbol,Int,KernelRef}
