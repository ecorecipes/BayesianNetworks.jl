"""
Mutating builders (`add_*!`) and the `bayesnet` DSL.

The `!` functions mutate the network passed to them and return the id of the part they
create. Everything else in the package treats networks as immutable values.
"""

# Resolving user-facing identifiers
###################################

_variable_id(::AbstractVariableSpace, v::Integer) = Int(v)
_variable_id(bn::AbstractVariableSpace, name::Symbol) = variable_id(bn, name)

_mechanism_id(::AbstractBayesNet, m::Integer) = Int(m)
_mechanism_id(bn::AbstractBayesNet, name::Symbol) = mechanism_id(bn, name)

"""
    variable_id(bn, name::Symbol) -> Int

Part id of the variable called `name`. Throws [`UnknownVariableError`](@ref) if there
is none and [`DuplicateNameError`](@ref) if there are several.
"""
function variable_id(bn::AbstractVariableSpace, name::Symbol)
    ids = incident(bn, name, :variable_name)
    isempty(ids) && throw(UnknownVariableError(name))
    length(ids) > 1 && throw(DuplicateNameError(:Variable, name, collect(ids)))
    return first(ids)
end

"""
    mechanism_id(bn, name::Symbol) -> Int

Part id of the mechanism called `name`. Throws [`UnknownMechanismError`](@ref) if there
is none and [`DuplicateNameError`](@ref) if there are several.
"""
function mechanism_id(bn::AbstractBayesNet, name::Symbol)
    ids = findall(==(name), subpart(bn, :mechanism_name))
    isempty(ids) && throw(UnknownMechanismError(name))
    length(ids) > 1 && throw(DuplicateNameError(:Mechanism, name, ids))
    return first(ids)
end

# Builders
##########

"""
    add_variable!(bn, name::Symbol; states::Vector{Symbol}, space_ref = NoRef()) -> Int

Add a variable with the given ordered `states` (positions `1:length(states)`) and
return its part id. Names are not checked for uniqueness here; see
[`validate`](@ref).
"""
function add_variable!(bn::AbstractVariableSpace, name::Symbol;
                       states::AbstractVector{Symbol}, space_ref=NoRef())
    v = add_part!(bn, :Variable; variable_name=name, space_ref=space_ref)
    for (i, s) in enumerate(states)
        add_part!(bn, :State; state_variable=v, state_name=s, state_position=i)
    end
    return v
end

"""
    add_state!(bn, variable, name::Symbol; position = nstates(bn, variable) + 1) -> Int

Append a state to `variable` (a part id or a variable name) and return its part id. By
default the new state takes the next free position.
"""
function add_state!(bn::AbstractVariableSpace, variable, name::Symbol;
                    position::Integer=nstates(bn, variable) + 1)
    v = _variable_id(bn, variable)
    return add_part!(bn, :State; state_variable=v, state_name=name,
                     state_position=Int(position))
end

"""
    add_mechanism!(bn, target; inputs = Symbol[], name = Symbol(target, "_mechanism"),
                   kernel_ref = NoRef()) -> Int

Add a mechanism generating `target` (a variable name or part id) from the parent
variables `inputs`, in the given order (input positions `1:length(inputs)`), and return
its part id. Existing mechanisms of `target` are left in place; a second one is a
validation error, not a construction error.
"""
function add_mechanism!(bn::AbstractBayesNet, target;
                        inputs::AbstractVector=Symbol[],
                        name::Symbol=Symbol(_display_name(bn, target), "_mechanism"),
                        kernel_ref=NoRef())
    t = _variable_id(bn, target)
    m = add_part!(bn, :Mechanism; target=t, mechanism_name=name,
                  kernel_ref=kernel_ref)
    for (i, p) in enumerate(inputs)
        add_part!(bn, :Input; input_mechanism=m, input_variable=_variable_id(bn, p),
                  input_position=i)
    end
    return m
end

_display_name(::AbstractVariableSpace, name::Symbol) = name
_display_name(bn::AbstractVariableSpace, v::Integer) = subpart(bn, Int(v), :variable_name)

"""
    add_input!(bn, mechanism, variable; position = ninputs + 1) -> Int

Append `variable` as an input (parent) of `mechanism` and return the new `Input` part
id. Both arguments may be names or part ids.
"""
function add_input!(bn::AbstractBayesNet, mechanism, variable;
                    position::Integer=length(incident(bn, _mechanism_id(bn, mechanism),
                                                      :input_mechanism)) + 1)
    m = _mechanism_id(bn, mechanism)
    v = _variable_id(bn, variable)
    return add_part!(bn, :Input; input_mechanism=m, input_variable=v,
                     input_position=Int(position))
end

# DSL
#####

_input_list(x::Symbol) = [x]
_input_list(x::Tuple) = collect(Symbol, x)
_input_list(x::AbstractVector) = collect(Symbol, x)

"""
    bayesnet(variables...; mechanisms = [], closed = true, space_refs = Dict(),
             kernel_refs = Dict()) -> BayesNet

Build a [`BayesNet`](@ref) from `name => states` pairs and a list of
`target => parents` mechanisms, where `parents` is a `Symbol`, a tuple or a vector of
variable names, in the parent order that `input_position` will record.

With `closed = true` (the default) every variable not named as a target receives a
mechanism without inputs, so the result is a closed network with priors on its roots.
With `closed = false` those variables stay exogenous (no mechanism).

`space_refs` and `kernel_refs` map variable names to `space_ref` values and target
names to `kernel_ref` values; anything not listed gets [`NoRef`](@ref).

# Example

```jldoctest
julia> bn = bayesnet(:Climate => [:dry, :wet], :Irrigation => [:none, :high],
                     :SoilMoisture => [:low, :high];
                     mechanisms = [:SoilMoisture => (:Climate, :Irrigation)]);

julia> variable_name.(Ref(bn), topological_order(bn))
3-element Vector{Symbol}:
 :Climate
 :Irrigation
 :SoilMoisture
```
"""
function bayesnet(variables::Pair{Symbol,<:AbstractVector{Symbol}}...;
                  mechanisms::AbstractVector=Pair{Symbol,Any}[], closed::Bool=true,
                  space_refs=Dict{Symbol,KernelRef}(),
                  kernel_refs=Dict{Symbol,KernelRef}())
    bn = BayesNet()
    for (name, states) in variables
        add_variable!(bn, name; states=states,
                      space_ref=get(space_refs, name, NoRef()))
    end
    targets = Set{Symbol}()
    for (target, parents) in mechanisms
        add_mechanism!(bn, target; inputs=_input_list(parents),
                       kernel_ref=get(kernel_refs, target, NoRef()))
        push!(targets, target)
    end
    if closed
        for (name, _) in variables
            name in targets && continue
            add_mechanism!(bn, name; kernel_ref=get(kernel_refs, name, NoRef()))
        end
    end
    return bn
end
