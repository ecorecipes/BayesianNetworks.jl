"""
Structural validation (SPEC §11, structural items). Semantic checks (kernel shapes and
normalisation) live with the semantics layer.
"""

_in_range(bn, ob::Symbol, id::Int) = 1 <= id <= nparts(bn, ob)

# Each check appends its errors to `errs` and returns whether later checks that depend on
# it are safe to run.

function _check_references!(errs, bn::AbstractBayesNet)
    ok = true
    for s in parts(bn, :State)
        v = subpart(bn, s, :state_variable)
        if !_in_range(bn, :Variable, v)
            push!(errs, DanglingReferenceError(:State, s, :state_variable, v))
            ok = false
        end
    end
    for m in parts(bn, :Mechanism)
        t = subpart(bn, m, :target)
        if !_in_range(bn, :Variable, t)
            push!(errs, DanglingReferenceError(:Mechanism, m, :target, t))
            ok = false
        end
    end
    for i in parts(bn, :Input)
        m = subpart(bn, i, :input_mechanism)
        if !_in_range(bn, :Mechanism, m)
            push!(errs, DanglingReferenceError(:Input, i, :input_mechanism, m))
            ok = false
        end
        v = subpart(bn, i, :input_variable)
        if !_in_range(bn, :Variable, v)
            push!(errs, DanglingReferenceError(:Input, i, :input_variable, v))
            ok = false
        end
    end
    return ok
end

function _check_generators!(errs, bn::AbstractBayesNet, closed::Bool)
    for v in parts(bn, :Variable)
        ms = incident(bn, v, :target)
        if length(ms) > 1
            push!(errs, DuplicateGeneratorError(variable_name(bn, v), v, collect(ms)))
        elseif closed && isempty(ms)
            push!(errs, MissingMechanismError(variable_name(bn, v), v))
        end
    end
end

function _check_positions!(errs, bn, ob::Symbol, owner_ob::Symbol, owner_hom::Symbol,
                           pos_attr::Symbol, name_attr::Symbol)
    for o in parts(bn, owner_ob)
        members = incident(bn, o, owner_hom)
        isempty(members) && continue
        positions = sort(Int[subpart(bn, x, pos_attr) for x in members])
        positions == 1:length(positions) ||
            push!(errs, PositionError(ob, subpart(bn, o, name_attr), o, positions))
    end
end

function _check_state_names!(errs, bn::AbstractBayesNet)
    for v in parts(bn, :Variable)
        seen = Set{Symbol}()
        for s in incident(bn, v, :state_variable)
            name = subpart(bn, s, :state_name)
            if name in seen
                push!(errs, DuplicateStateError(variable_name(bn, v), v, name))
            else
                push!(seen, name)
            end
        end
    end
end

function _check_self_inputs!(errs, bn::AbstractBayesNet)
    for m in parts(bn, :Mechanism)
        t = subpart(bn, m, :target)
        t in inputs(bn, m) &&
            push!(errs, SelfInputError(mechanism_name(bn, m), m, variable_name(bn, t)))
    end
end

function _check_acyclic!(errs, bn::AbstractBayesNet)
    _, remaining = _kahn(bn)
    return isempty(remaining) ||
           push!(errs, CyclicBayesNetError(variable_name.(Ref(bn), remaining), remaining))
end

function _check_unique_names!(errs, bn, ob::Symbol, name_attr::Symbol)
    groups = Dict{Symbol,Vector{Int}}()
    for p in parts(bn, ob)
        push!(get!(groups, subpart(bn, p, name_attr), Int[]), p)
    end
    for name in sort!(collect(keys(groups)))
        ids = groups[name]
        length(ids) > 1 && push!(errs, DuplicateNameError(ob, name, ids))
    end
end

"""
    validation_errors(bn; closed = false, unique_names = false) -> Vector{Exception}

All structural problems of `bn`, in a deterministic order, without stopping at the
first. The checks, with the exception each produces:

1. every `state_variable`, `target`, `input_mechanism` and `input_variable` points at
   an existing part ([`DanglingReferenceError`](@ref));
2. at most one mechanism per variable ([`DuplicateGeneratorError`](@ref)), and exactly
   one when `closed = true` ([`MissingMechanismError`](@ref));
3. state positions of each variable are a permutation of `1:n`
   ([`PositionError`](@ref));
4. state names are unique within each variable ([`DuplicateStateError`](@ref));
5. input positions of each mechanism are a permutation of `1:k`
   ([`PositionError`](@ref));
6. no mechanism lists its own target as an input ([`SelfInputError`](@ref));
7. the derived variable graph is acyclic ([`CyclicBayesNetError`](@ref));
8. with `unique_names = true`, variable names and mechanism names are unique
   ([`DuplicateNameError`](@ref)). This is off by default because tensoring two
   networks legitimately produces repeated names.

Part ids are unique by construction, which covers SPEC §11 item 12 for the ACSet
itself. Checks 6 and 7 are skipped when check 1 fails.
"""
function validation_errors(bn::AbstractBayesNet; closed::Bool=false,
                           unique_names::Bool=false)
    errs = Exception[]
    refs_ok = _check_references!(errs, bn)
    _check_generators!(errs, bn, closed)
    _check_positions!(errs, bn, :State, :Variable, :state_variable, :state_position,
                      :variable_name)
    _check_state_names!(errs, bn)
    _check_positions!(errs, bn, :Input, :Mechanism, :input_mechanism, :input_position,
                      :mechanism_name)
    if refs_ok
        _check_self_inputs!(errs, bn)
        _check_acyclic!(errs, bn)
    end
    if unique_names
        _check_unique_names!(errs, bn, :Variable, :variable_name)
        _check_unique_names!(errs, bn, :Mechanism, :mechanism_name)
    end
    return errs
end

"""
    validate(bn::AbstractBayesNet; closed = false, unique_names = false) -> Nothing

Check the structural invariants of `bn` and throw the first violation as a typed
exception; return `nothing` when the network is valid. See
[`validation_errors`](@ref) for the list of checks and their keyword arguments.

`closed = false` accepts open networks (variables may lack a mechanism); `closed = true`
demands exactly one mechanism per variable.
"""
function validate(bn::AbstractBayesNet; kw...)
    errs = validation_errors(bn; kw...)
    isempty(errs) || throw(first(errs))
    return nothing
end

"""
    isvalid(bn::AbstractBayesNet; closed = false, unique_names = false) -> Bool

Whether [`validation_errors`](@ref) is empty.
"""
Base.isvalid(bn::AbstractBayesNet; kw...) = isempty(validation_errors(bn; kw...))
