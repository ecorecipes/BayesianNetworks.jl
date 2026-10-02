function _proof_text(value, part::Symbol, id::Int, name::Union{Nothing,Symbol})
    value isa Union{Symbol,AbstractString} ||
        throw(ProofCertificateError(:text, part, id, name,
                                    "expected a symbol or string, got $(typeof(value))"))
    text = String(value)
    isvalid(text) && !any(c -> Int(c) < 32 || Int(c) == 127, text) ||
        throw(ProofCertificateError(:text, part, id, name,
                                    "certificate text must be valid UTF-8 without control characters"))
    return text
end

function _proof_ref(ref, part::Symbol, id::Int, name::Symbol)
    if ref isa NamedRef
        return (kind="named", key=_proof_text(ref.id, part, id, name))
    elseif ref isa PolicyRef
        return (kind="policy", key=_proof_text(ref.decision, part, id, name))
    elseif ref isa PointMassRef
        return (kind="point_mass", state=_proof_text(ref.state, part, id, name))
    elseif ref isa NoRef
        return (kind="none",)
    end
    return throw(ProofCertificateError(:reference, part, id, name,
                                       "unsupported reference type $(typeof(ref))"))
end

function _proof_structure(bn::AbstractBayesNet)
    for part in (:Variable, :State, :Mechanism, :Input)
        collect(parts(bn, part)) == collect(1:nparts(bn, part)) ||
            throw(ProofCertificateError(:part_ids, part, 0, nothing,
                                        "finite-bn-certificate-1 requires dense one-based part IDs"))
    end
    for (part, attr) in ((:Variable, :variable_name), (:State, :state_name),
                         (:Mechanism, :mechanism_name))
        for id in parts(bn, part)
            name = subpart(bn, id, attr)
            name isa Symbol ||
                throw(ProofCertificateError(:label_type, part, id, nothing,
                                            "finite model labels must be Symbols"))
            _proof_text(name, part, id, name)
        end
    end
    for (part, attr) in ((:State, :state_position), (:Input, :input_position))
        for id in parts(bn, part)
            position = subpart(bn, id, attr)
            position isa Integer && !(position isa Bool) ||
                throw(ProofCertificateError(:position_type, part, id, nothing,
                                            "positions must be integers, not booleans"))
        end
    end
    validate(bn; closed=true, unique_names=true)
    for v in variables(bn)
        nstates(bn, v) > 0 ||
            throw(ProofCertificateError(:empty_states, :Variable, v, variable_name(bn, v),
                                        "a finite probability variable must have at least one state"))
    end
    return nothing
end

function _proof_evidence(observations)
    observations isa AbstractDict ||
        throw(ProofCertificateError(:evidence_type, :Model, 0, nothing,
                                    "evidence must be a dictionary of variable and state Symbols"))
    result = Dict{Symbol,Symbol}()
    for (variable, state) in observations
        variable isa Symbol && state isa Symbol ||
            throw(ProofCertificateError(:evidence_type, :Model, 0,
                                        variable isa Symbol ? variable : nothing,
                                        "evidence keys and values must be Symbols"))
        result[variable] = state
    end
    return result
end

function _proof_entries(k::FiniteKernel, mech::Int, name::Symbol)
    for i in CartesianIndices(k.table)
        x = k.table[i]
        x isa Union{Integer,Rational,Float16,Float32,Float64,BigFloat} ||
            throw(ProofCertificateError(:scalar_type, :Mechanism, mech, name,
                                        "unsupported scalar $(typeof(x)) at output-first coordinate $(Tuple(i))"))
        isfinite(x) && x >= 0 ||
            throw(ProofCertificateError(:weight, :Mechanism, mech, name,
                                        "expected a finite nonnegative weight at output-first coordinate $(Tuple(i)), got $(repr(x))"))
    end
    return nothing
end

function _proof_weight(x)
    q = Rational{BigInt}(x)
    return (num=string(numerator(q)), den=string(denominator(q)))
end

function _proof_binding(bn::AbstractBayesNet, mech::Int, k::FiniteKernel)
    ref = _proof_ref(_set_kernel_ref(bn, mech), :Mechanism, mech, mechanism_name(bn, mech))
    table = cpt(k)
    columns = NamedTuple[]
    # Reverse the iteration dimensions, not the table: the last parent varies fastest.
    for reversed in CartesianIndices(reverse(size(k.dom)))
        coordinates = reverse(Tuple(reversed))
        push!(columns,
              (parents=collect(Int, coordinates),
               weights=[_proof_weight(table[coordinates..., b])
                        for b in 1:nstates(bn, target(bn, mech))]))
    end
    return (kind=ref.kind, key=ref.key,
            input_states=[String.(states(bn, v)) for v in inputs(bn, mech)],
            output_states=String.(states(bn, target(bn, mech))), columns=columns)
end

"""
    proof_certificate(m::BayesModel; evidence=m.evidence, atol=DEFAULT_ATOL) -> NamedTuple

Capture a closed, fully bound finite model as JSON-compatible
`finite-bn-certificate-1` data for `proofs/scripts/check_certificate.py`.
The explicit `evidence` dictionary **replaces**, rather than merges with, the
stored observations. Impossible but well-formed observations are exportable;
the tables are not conditioned on the evidence.

Variable, state, mechanism and input rows retain their original part-ID order.
IDs and positions are one-based; non-dense part IDs are rejected rather than
renumbered. Preserve every ordered parent slot, including repeated slots and
all their off-diagonal CPT columns, through `cpt(k)`. Preserve space
references and used generating references; emit one binding per used named
or policy reference. Point masses need no numeric binding. A generating
[`NoRef`](@ref) is unresolved, and incompatible shared bindings are rejected.

Integers and rationals are exported exactly. `Float16`, `Float32`, `Float64`
and `BigFloat` entries become their exact binary rational values, **before**
any inference-backend conversion. Numerators and denominators are decimal
strings; signed zero becomes rational zero. Other scalar types, nonfinite
or negative entries (even within `atol`), and control characters in names
raise [`ProofCertificateError`](@ref). Ordinary validation receives `atol`;
no value is rounded, clipped, rationally approximated or renormalized.

For example, the actual Float64 entries `[0.1, 0.9]` are not an exactly
normalized rational row. The Lean consumer can check the data while reporting
false exact normalization, or reject it with `--require-normalized`.

The result owns its arrays. Callers must not mutate the source model during
capture. Only the Bayesian-network records are represented, not history,
extras or additional fields of an extended schema. Successful checking proves
facts about the emitted literal Lean data, not the Julia exporter, JSON
transcription, floating-point inference, or policy optimality.
"""
function proof_certificate(m::BayesModel; evidence=m.evidence, atol::Real=DEFAULT_ATOL)
    isfinite(atol) && atol >= 0 ||
        throw(ProofCertificateError(:atol, :Model, 0, nothing,
                                    "atol must be finite and nonnegative"))
    bn = deepcopy(m.syntax)
    _proof_structure(bn)
    observations = _proof_evidence(evidence)
    variable_data = [(name=String(variable_name(bn, v)),
                      space_ref=_proof_ref(_ref_value(bn, :Variable, v, :space_ref),
                                           :Variable, v,
                                           variable_name(bn, v))) for v in variables(bn)]
    mechanism_data = [(name=String(mechanism_name(bn, mech)), target=target(bn, mech),
                       kernel_ref=_proof_ref(_set_kernel_ref(bn, mech), :Mechanism, mech,
                                             mechanism_name(bn, mech)))
                      for mech in mechanisms(bn)]

    captured_spaces = Dict{Symbol,FiniteSpace}()
    for (name, sp) in m.spaces
        v = variable_id(bn, name)
        sp isa FiniteSpace ||
            throw(ProofCertificateError(:space_type, :Variable, v, name,
                                        "expected a FiniteSpace, got $(typeof(sp))"))
        captured_spaces[name] = deepcopy(sp)
    end
    captured_kernels = Dict{KernelRef,FiniteKernel}()
    binding_mechanisms = Int[]
    for mech in mechanisms(bn)
        ref = _set_kernel_ref(bn, mech)
        name = variable_name(bn, target(bn, mech))
        if ref isa PointMassRef
            ref.state in states(bn, target(bn, mech)) ||
                throw(UnknownStateError(name, ref.state))
            continue
        end
        ref isa NoRef && throw(MissingKernelError(name, ref))
        haskey(captured_kernels, ref) && continue
        k = get(m.kernels, ref, nothing)
        k === nothing && throw(MissingKernelError(name, ref))
        k isa FiniteKernel ||
            throw(ProofCertificateError(:kernel_type, :Mechanism, mech,
                                        mechanism_name(bn, mech),
                                        "expected a FiniteKernel, got $(typeof(k))"))
        captured = deepcopy(k)
        _proof_entries(captured, mech, mechanism_name(bn, mech))
        captured_kernels[ref] = captured
        push!(binding_mechanisms, mech)
    end
    snapshot = BayesModel(bn; spaces=captured_spaces, kernels=captured_kernels,
                          evidence=observations)
    validate(snapshot; closed=true, unique_names=true, semantics=true, atol=atol)

    return (version="finite-bn-certificate-1", variables=variable_data,
            states=[(variable=subpart(bn, s, :state_variable),
                     position=subpart(bn, s, :state_position),
                     name=String(subpart(bn, s, :state_name))) for s in parts(bn, :State)],
            mechanisms=mechanism_data,
            inputs=[(mechanism=subpart(bn, i, :input_mechanism),
                     variable=subpart(bn, i, :input_variable),
                     position=subpart(bn, i, :input_position)) for i in parts(bn, :Input)],
            bindings=[_proof_binding(bn, mech, captured_kernels[kernel_ref(bn, mech)])
                      for mech in binding_mechanisms],
            topological_order=topological_order(bn),
            evidence=[(variable=v,
                       state_position=findfirst(==(observations[variable_name(bn, v)]),
                                                states(bn, v)))
                      for v in variables(bn) if haskey(observations, variable_name(bn, v))])
end
