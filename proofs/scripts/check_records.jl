#!/usr/bin/env julia
#
# Cross-check of the proved JSON decoders against Julia.
#
#     cd BayesianNetworks.jl/proofs && lake build check_records
#     cd ../../InfluenceDiagrams.jl/proofs && lake build check_records
#     julia --project=../../EcologicalBayesianNetworks.jl scripts/check_records.jl [OUTDIR]
#
# (run from BayesianNetworks.jl/proofs; the EcologicalBayesianNetworks environment provides
# BayesianNetworks, InfluenceDiagrams and the model zoo.)
#
# For every fixture network and influence diagram it can load, the script writes the ACSet JSON
# with `write_json_bayesnet` / `write_json_influence_diagram`, runs the Lean executable
# `check_records` on the file (BN or ID proofs project), and compares its summary, line by line,
# with the same summary built from Julia's own accessors: `states`, `inputs` (parents in
# `input_position` order), `mechanism_name`, `decision_information`, `utility_scope` and, for
# models with numbers, the axes of the policy tables `optimize` returns (information axes and
# their labels, then the action labels). The Lean `topological:` line is checked to be a
# permutation in which every Julia parent and information variable precedes its child, and
# `valid:` is compared with `isempty(validation_errors(x; closed = true))`.
#
# A second part writes mutated documents (a missing column or table, a hom ID out of range, a
# value of the wrong JSON type, position 0, a wrong `_id`, an extra key, an unknown `KernelRef`
# type, and three well-shaped documents of invalid models) and records whether the Lean decoder
# and Julia reject each: Julia's reader with a `FormatError`, or `validation_errors(x; closed =
# true)` after a successful read, as the Lean check rejects a decoded but invalid model. A
# mutated document Julia accepts (reads and validates) fails the run.
#
# A third part checks decision precedence and names: mutated diagrams (a precedence cycle, a
# precedence row against the information order, a self-loop, a row out of range, a duplicate and
# a consistent row, and duplicate variable, mechanism, decision and utility names) whose Lean
# verdicts (`valid:`, from `FullValid`, and `valid with unique names:`, from `FullValid` and
# `NamesUnique`) must equal Julia's (`validate(...; closed = true)` and `validate(...; closed =
# true, unique_names = true)`, a reader rejection counting as invalid). Every ID summary also
# compares the `valid with unique names:` line.
#
# A fourth part writes the DVE certificate of every influence diagram with numbers
# (`export_dve_certificate`, binary64 mode, and rational mode with companions recovered from the
# binary64 certificate) and runs `lake exe check_certificate` (ID proofs project) on the diagram
# and the certificate: a certificate Julia exports must match (`certificateMatches`), and the
# exact applicability verdicts are recorded. Mutated certificates (swapped labels, a wrong axis, a
# repeated variable in the topological order, a missing field and others) must be rejected; Julia
# has no certificate reader, so there is no Julia verdict for them.
#
# Trusted, not proved: Lean.Json.parse, Julia's JSON3/ACSets writer, and this script.

using BayesianNetworks
using InfluenceDiagrams
using EcologicalBayesianNetworks
# JSON3 and Random come from BayesianNetworks' own dependencies: the EcologicalBayesianNetworks
# environment does not list them.
const JSON3 = BayesianNetworks.JSON3
const Random = Base.require(Base.PkgId(Base.UUID("9a3f8284-a2c9-5f02-9a11-845980a1fd5c"),
                                        "Random"))
const MersenneTwister = Random.MersenneTwister

const BN_PROOFS = normpath(joinpath(@__DIR__, ".."))
const ID_PROOFS = normpath(joinpath(@__DIR__, "..", "..", "..", "InfluenceDiagrams.jl", "proofs"))
const BN_EXE = joinpath(BN_PROOFS, ".lake", "build", "bin", "check_records")
const ID_EXE = joinpath(ID_PROOFS, ".lake", "build", "bin", "check_records")
const CERT_EXE = joinpath(ID_PROOFS, ".lake", "build", "bin", "check_certificate")

const OUT = isempty(ARGS) ? mktempdir() : mkpath(ARGS[1])

function run_lean(exe, path)
    out = IOBuffer()
    p = run(pipeline(ignorestatus(`$exe $path`); stdout=out, stderr=out))
    return p.exitcode, split(chomp(String(take!(out))), '\n')
end

joinlabels(xs) = join(string.(xs), ", ")

julia_valid(x) = isempty(validation_errors(x; closed=true))
julia_valid_names(x) = isempty(validation_errors(x; closed=true, unique_names=true))

# Julia's summary of a network, in the Lean executable's format (no topological line).
function bn_summary(bn)
    lines = String["format: bayesnet-acset", "valid: " * (julia_valid(bn) ? "yes" : "no"),
                   "variables: $(nparts(bn, :Variable))"]
    julia_valid(bn) || return lines
    for v in parts(bn, :Variable)
        push!(lines, "states $(variable_name(bn, v)): $(joinlabels(states(bn, v)))")
    end
    for m in parts(bn, :Mechanism)
        t = subpart(bn, m, :target)
        ps = [variable_name(bn, p) for p in inputs(bn, m)]
        push!(lines, "parents $(variable_name(bn, t)): $(joinlabels(ps))")
    end
    for m in parts(bn, :Mechanism)
        push!(lines,
              "mechanism $(mechanism_name(bn, m)): $(variable_name(bn, subpart(bn, m, :target)))")
    end
    push!(lines, "acyclic: yes")
    return lines
end

# Julia's summary of an influence diagram; `axes[d]` are the policy-table axes from `optimize`
# when the model has numbers, otherwise `information_space` / `action_space` of the model.
function id_summary(id, axes)
    lines = String["format: influence-diagram-acset",
                   "valid: " * (julia_valid(id) ? "yes" : "no"),
                   "valid with unique names: " * (julia_valid_names(id) ? "yes" : "no"),
                   "variables: $(nparts(id, :Variable))"]
    julia_valid(id) || return lines
    for v in parts(id, :Variable)
        push!(lines, "states $(variable_name(id, v)): $(joinlabels(states(id, v)))")
    end
    for m in parts(id, :Mechanism)
        t = subpart(id, m, :target)
        ps = [variable_name(id, p) for p in inputs(id, m)]
        push!(lines, "parents $(variable_name(id, t)): $(joinlabels(ps))")
    end
    for d in parts(id, :Decision)
        dn = decision_name(id, d)
        a = variable_name(id, decision_variable(id, d))
        info = [variable_name(id, v) for v in decision_information(id, d)]
        push!(lines, "decision $dn: $a", "information $dn: $(joinlabels(info))")
        infoaxes, action = axes[dn]
        ax = ["$(n) [$(joinlabels(ls))]" for (n, ls) in infoaxes]
        push!(lines, "policy $dn: $(join(ax, " x ")) -> $(action[1]) [$(joinlabels(action[2]))]")
    end
    for u in parts(id, :Utility)
        sc = [variable_name(id, v) for v in utility_scope(id, u)]
        push!(lines, "utility $(utility_name(id, u)): $(joinlabels(sc))")
    end
    push!(lines, "acyclic: yes")
    return lines
end

axis_pair(a::FiniteAxis) = (String(a.name), String.(a.labels))

# Policy-table axes of every decision: from the solution of `optimize` when possible.
function policy_axes(m::InfluenceDiagramModel)
    id = syntax(m)
    axes = Dict{Symbol,Any}()
    source = "optimize"
    sol = try
        optimize(m)
    catch e
        source = "information_space (optimize: $(nameof(typeof(e))))"
        nothing
    end
    for d in parts(id, :Decision)
        dn = decision_name(id, d)
        if sol !== nothing
            p = sol.strategy[dn]
            k = policy_kernel(p)
            axes[dn] = ([axis_pair(a) for a in factors(k.dom)],
                        axis_pair(only(factors(k.codom))))
        else
            axes[dn] = ([axis_pair(a) for a in factors(information_space(m, d))],
                        axis_pair(only(factors(action_space(m, d)))))
        end
    end
    return axes, source
end

# The Lean topological line: a permutation in which every parent (and information variable)
# precedes its child.
function check_topological(x, line; information=false)
    startswith(line, "topological: ") || return false
    order = split(line[(length("topological: ") + 1):end], ", ")
    names = [String(variable_name(x, v)) for v in parts(x, :Variable)]
    sort(String.(order)) == sort(names) || return false
    pos = Dict(String(n) => i for (i, n) in enumerate(order))
    for m in parts(x, :Mechanism)
        t = String(variable_name(x, subpart(x, m, :target)))
        all(pos[String(variable_name(x, p))] < pos[t] for p in inputs(x, m)) || return false
    end
    if information
        for d in parts(x, :Decision)
            a = String(variable_name(x, decision_variable(x, d)))
            all(pos[String(variable_name(x, v))] < pos[a]
                for v in decision_information(x, d)) || return false
        end
    end
    return true
end

const RESULTS = Any[]

function compare(kind, name, path, exe, julia_lines, x; note="")
    status, lean = run_lean(exe, path)
    topo = filter(l -> startswith(l, "topological: "), lean)
    leanrest = filter(l -> !startswith(l, "topological: "), lean)
    diffs = String[]
    if leanrest != julia_lines
        for i in 1:max(length(leanrest), length(julia_lines))
            l = i <= length(leanrest) ? leanrest[i] : "<none>"
            j = i <= length(julia_lines) ? julia_lines[i] : "<none>"
            l == j || push!(diffs, "lean: $l | julia: $j")
        end
    end
    if julia_valid(x) && (isempty(topo) || !check_topological(x, only(topo);
                                                             information=kind == "ID"))
        push!(diffs, "topological order rejected: $(isempty(topo) ? "none" : only(topo))")
    end
    ok = isempty(diffs)
    push!(RESULTS, (kind=kind, name=name, ok=ok, diffs=diffs, note=note, status=status))
    println(rpad(ok ? "PASS" : "FAIL", 6), rpad(kind, 4), name, isempty(note) ? "" : "  ($note)")
    for d in first(diffs, 8)
        println("        ", d)
    end
    return ok
end

slug(s) = replace(String(s), r"[^A-Za-z0-9_.-]" => "_")

function check_bn(name, bn)
    path = joinpath(OUT, "bn_" * slug(name) * ".json")
    write_json_bayesnet(path, bn)
    return compare("BN", name, path, BN_EXE, bn_summary(bn), bn)
end

const CERT_MODELS = Any[]

function check_id(name, m::InfluenceDiagramModel)
    id = syntax(m)
    path = joinpath(OUT, "id_" * slug(name) * ".json")
    write_json_influence_diagram(path, id)
    axes, source = policy_axes(m)
    push!(CERT_MODELS, (name=name, model=m, diagram=path))
    return compare("ID", name, path, ID_EXE, id_summary(id, axes), id; note="axes: $source")
end

# Random numbers for a structure-only diagram, as in InfluenceDiagrams' test helpers.
function with_random_numbers(id; seed=1)
    rng = MersenneTwister(seed)
    m = InfluenceDiagramModel(id)
    for x in chance_names(id)
        m = bind_kernel(m, x => random_kernel(rng, parent_space(m, x), space(m, x)))
    end
    for u in utility_names(id)
        dims = Tuple(nstates(id, v) for v in utility_scope(id, u))
        m = bind_utility(m, u => 20 .* rand(rng, dims...) .- 10)
    end
    return m
end

# Howard's car-buyer problem (structure as in the decision-analysis literature): no such
# fixture exists in the ecosystem, so it is built here, with random numbers.
function car_buyer_diagram()
    return influence_diagram(:Condition => [:peach, :lemon],
                             :FirstTest => [:none, :steering, :fuel_electrical, :transmission],
                             :FirstResult => [:no_result, :zero, :one, :two],
                             :SecondTest => [:none, :differential],
                             :SecondResult => [:no_result, :zero, :one],
                             :Purchase => [:buy, :guarantee, :dont];
                             mechanisms=[:FirstResult => (:Condition, :FirstTest),
                                         :SecondResult => (:Condition, :FirstTest,
                                                           :SecondTest)],
                             decisions=[:FirstTest => Symbol[],
                                        :SecondTest => (:FirstTest, :FirstResult),
                                        :Purchase => (:FirstTest, :FirstResult, :SecondTest,
                                                      :SecondResult)],
                             utilities=[:TestCost => (:FirstTest, :SecondTest),
                                        :Value => (:Condition, :Purchase)],
                             precedence=[:FirstTest => :SecondTest,
                                         :SecondTest => :Purchase])
end

# The two-stage diagram built in another part order and with an explicit precedence row, as in
# InfluenceDiagrams' test_serialization.jl.
function two_stage_with_precedence()
    return influence_diagram(:Drill => [:drill, :dont], :Result => [:pos, :neg, :none],
                             :Test => [:test, :skip], :Oil => [:dry, :wet];
                             mechanisms=[:Result => (:Oil, :Test)],
                             decisions=[:Drill => (:Test, :Result), :Test => Symbol[]],
                             utilities=[:TestCost => :Test, :Payoff => (:Oil, :Drill)],
                             precedence=[:Test => :Drill])
end

println("output directory: ", OUT)
println("\n== Networks ==")
check_bn("reference_habitat_bn", reference_habitat_bn())
for f in ("bif/asia.bif", "bif/habitat_reference.bif", "bif/sprinkler_table.bif",
          "dne/habitat_reference.dne", "dne/habitat_reference_flat.dne", "dsc/asia.dsc",
          "net/asia.net", "net/habitat_reference.net", "uai/asia.uai", "uai/ChestClinic.uai",
          "uai/habitat_reference.uai", "xdsl/habitat_reference.xdsl",
          "xdsl/Habitat_Suitability.xdsl", "dne/determin_functable.dne",
          "dne/levels_named_states.dne", "dne/state_index_literals.dne")
    try
        check_bn(f, syntax(read_bayesnet(fixture_path(f))))
    catch e
        println("SKIP  BN  $f  ($(nameof(typeof(e))))")
    end
end

println("\n== Influence diagrams ==")
check_id("reference_grazing", InfluenceDiagrams.reference_grazing_model())
check_id("umbrella", InfluenceDiagrams.umbrella_model())
check_id("two_stage (oil wildcatter)", InfluenceDiagrams.two_stage_model())
check_id("two_stage reordered, with precedence (random numbers)",
         with_random_numbers(two_stage_with_precedence()))
check_id("car_buyer (built here, random numbers)", with_random_numbers(car_buyer_diagram()))
for f in ("dne/umbrella.dne", "net/umbrella.net", "xdsl/umbrella.xdsl",
          "dne/grazing_reference_id.dne", "net/grazing_reference_id.net",
          "xdsl/grazing_reference_id.xdsl")
    try
        check_id(f, InfluenceDiagramModel(read_network(fixture_path(f))))
    catch e
        println("SKIP  ID  $f  ($(nameof(typeof(e))))")
    end
end

println("\n== Model zoo ==")
for spec in MODEL_SPECS
    name = spec.name
    (is_builtin(spec) || EcologicalBayesianNetworks.is_available(name)) || begin
        println("SKIP  zoo $name  ($(spec.redistribution), not available locally)")
        continue
    end
    m = try
        load_model(name)
    catch e
        println("SKIP  zoo $name  (load: $(nameof(typeof(e))))")
        continue
    end
    try
        if m isa InfluenceDiagramModel
            check_id("zoo/" * name, m)
        elseif m isa BayesModel
            check_bn("zoo/" * name, syntax(m))
        elseif m isa BayesNet
            check_bn("zoo/" * name, m)
        else
            println("SKIP  zoo $name  ($(typeof(m)))")
        end
    catch e
        println("SKIP  zoo $name  ($(nameof(typeof(e))): $(first(sprint(showerror, e), 120)))")
    end
end

# Mutated documents: Lean must reject every one; record what Julia's reader does.
println("\n== Mutated documents ==")
const MUTATIONS = Any[]

function julia_reads(kind, path)
    x = try
        kind == "BN" ? read_json_bayesnet(path) : read_json_influence_diagram(path)
    catch e
        return "rejected by the reader ($(nameof(typeof(e))))"
    end
    errs = try
        validation_errors(x; closed=true)
    catch e
        return "read; validation_errors threw $(nameof(typeof(e)))"
    end
    isempty(errs) && return "accepted, validates"
    return "rejected by validate ($(nameof(typeof(first(errs)))))"
end

function mutate(kind, base, label, f!)
    doc = JSON3.read(read(base, String), Dict{String,Any})
    f!(doc["acset"])
    path = joinpath(OUT, "mut_" * lowercase(kind) * "_" * slug(label) * ".json")
    write(path, JSON3.write(doc))
    status, lean = run_lean(kind == "BN" ? BN_EXE : ID_EXE, path)
    leanres = status == 0 ? "ACCEPTED" : "rejected: " * first(lean)
    jres = julia_reads(kind, path)
    push!(MUTATIONS, (kind=kind, label=label, lean_ok=status != 0, lean=leanres, julia=jres))
    println(rpad(status != 0 ? "PASS" : "FAIL", 6), rpad(kind, 4), rpad(label, 34), "| julia: ",
            jres)
    println("        lean: ", leanres)
end

let base = joinpath(OUT, "bn_reference_habitat_bn.json")
    mutate("BN", base, "missing column state_position",
           a -> delete!(a["State"][1], "state_position"))
    mutate("BN", base, "missing table Input", a -> delete!(a, "Input"))
    mutate("BN", base, "missing table Label", a -> delete!(a, "Label"))
    mutate("BN", base, "hom out of range (state_variable 99)",
           a -> (a["State"][1]["state_variable"] = 99))
    mutate("BN", base, "hom zero (target 0)", a -> (a["Mechanism"][1]["target"] = 0))
    mutate("BN", base, "wrong type (state_name number)",
           a -> (a["State"][1]["state_name"] = 5))
    mutate("BN", base, "wrong type (state_variable string)",
           a -> (a["State"][1]["state_variable"] = "1"))
    mutate("BN", base, "wrong type (input_position 1.5)",
           a -> (a["Input"][1]["input_position"] = 1.5))
    mutate("BN", base, "position 0", a -> (a["State"][1]["state_position"] = 0))
    mutate("BN", base, "wrong _id", a -> (a["State"][2]["_id"] = 7))
    mutate("BN", base, "extra key in a row", a -> (a["Mechanism"][1]["note"] = "x"))
    mutate("BN", base, "unknown KernelRef type",
           a -> (a["Mechanism"][1]["kernel_ref"] = Dict("type" => "Bogus")))
    mutate("BN", base, "duplicate input_position",
           a -> (a["Input"][2]["input_position"] = a["Input"][1]["input_position"]))
    mutate("BN", base, "directed cycle (Climate reads Occupancy)",
           a -> push!(a["Input"],
                      Dict("_id" => length(a["Input"]) + 1,
                           "input_mechanism" => findfirst(r -> r["target"] == 1,
                                                          a["Mechanism"]),
                           "input_variable" => 7, "input_position" => 1)))
end
let base = joinpath(OUT, "id_umbrella.json")
    mutate("ID", base, "missing table DecisionPrecedence", a -> delete!(a, "DecisionPrecedence"))
    mutate("ID", base, "hom out of range (information_variable 9)",
           a -> (a["InformationInput"][1]["information_variable"] = 9))
    mutate("ID", base, "missing column utility_ref", a -> delete!(a["Utility"][1], "utility_ref"))
    mutate("ID", base, "wrong type (decision_name number)",
           a -> (a["Decision"][1]["decision_name"] = 3))
    mutate("ID", base, "information_position 0",
           a -> (a["InformationInput"][1]["information_position"] = 0))
    mutate("ID", base, "action also a mechanism target",
           a -> (a["Mechanism"][1]["target"] = a["Decision"][1]["decision_variable"]))
end

# Decision precedence and names: Lean's two verdicts against Julia's.
println("\n== Precedence and names ==")
const VERDICTS = Any[]

function julia_verdicts(path)
    x = try
        read_json_influence_diagram(path)
    catch e
        return ("no", "no", "reader: $(nameof(typeof(e)))")
    end
    errs = validation_errors(x; closed=true)
    errs_names = validation_errors(x; closed=true, unique_names=true)
    detail = isempty(errs_names) ? "valid" :
             join(unique(string.(nameof.(typeof.(errs_names)))), ", ")
    return (isempty(errs) ? "yes" : "no", isempty(errs_names) ? "yes" : "no", detail)
end

# A document the decoder rejects (no `valid:` line) is invalid for both verdicts.
function lean_verdicts(path)
    _, lean = run_lean(ID_EXE, path)
    get_line(prefix) = begin
        l = filter(x -> startswith(x, prefix), lean)
        isempty(l) ? "no" : String(strip(l[1][(length(prefix) + 1):end]))
    end
    return (get_line("valid: "), get_line("valid with unique names: "), first(lean))
end

function verdict_case(base, label, f!)
    doc = JSON3.read(read(base, String), Dict{String,Any})
    f!(doc["acset"])
    path = joinpath(OUT, "prec_" * slug(label) * ".json")
    write(path, JSON3.write(doc))
    lv, ln, first_line = lean_verdicts(path)
    jv, jn, detail = julia_verdicts(path)
    ok = lv == jv && ln == jn
    push!(VERDICTS, (label=label, ok=ok, lean=(lv, ln), julia=(jv, jn), detail=detail))
    lnote = startswith(first_line, "error") ? " ($first_line)" : ""
    println(rpad(ok ? "PASS" : "FAIL", 6), rpad(label, 52), "| lean: valid $lv, names $ln$lnote",
            " | julia: valid $jv, names $jn ($detail)")
    return ok
end

decision_id(a, name) = findfirst(r -> r["decision_name"] == name, a["Decision"])
function add_precedence!(a, earlier, later)
    push!(a["DecisionPrecedence"],
          Dict("_id" => length(a["DecisionPrecedence"]) + 1,
               "earlier" => decision_id(a, earlier), "later" => decision_id(a, later)))
end

let base = joinpath(OUT, "id_" * slug("two_stage (oil wildcatter)") * ".json")
    verdict_case(base, "unchanged (oil wildcatter)", a -> nothing)
    verdict_case(base, "consistent precedence (Test before Drill)",
                 a -> add_precedence!(a, "Test", "Drill"))
    verdict_case(base, "duplicate precedence row (Test before Drill, twice)",
                 a -> (add_precedence!(a, "Test", "Drill"); add_precedence!(a, "Test", "Drill")))
    verdict_case(base, "precedence cycle (Test-Drill-Test)",
                 a -> (add_precedence!(a, "Test", "Drill"); add_precedence!(a, "Drill", "Test")))
    verdict_case(base, "precedence against information (Drill before Test)",
                 a -> add_precedence!(a, "Drill", "Test"))
    verdict_case(base, "precedence self-loop (Test before Test)",
                 a -> add_precedence!(a, "Test", "Test"))
    verdict_case(base, "precedence row out of range (earlier = 3)",
                 a -> push!(a["DecisionPrecedence"],
                            Dict("_id" => length(a["DecisionPrecedence"]) + 1,
                                 "earlier" => 3, "later" => 1)))
    verdict_case(base, "duplicate variable name",
                 a -> (a["Variable"][2]["variable_name"] = a["Variable"][1]["variable_name"]))
    verdict_case(base, "duplicate mechanism name",
                 a -> (a["Mechanism"][2]["mechanism_name"] = a["Mechanism"][1]["mechanism_name"]))
    verdict_case(base, "duplicate decision name",
                 a -> (a["Decision"][2]["decision_name"] = a["Decision"][1]["decision_name"]))
    verdict_case(base, "duplicate utility name",
                 a -> (a["Utility"][2]["utility_name"] = a["Utility"][1]["utility_name"]))
end
let base = joinpath(OUT, "id_" * slug("car_buyer (built here, random numbers)") * ".json")
    verdict_case(base, "car buyer: three-decision precedence cycle",
                 a -> add_precedence!(a, "Purchase", "FirstTest"))
    verdict_case(base, "car buyer: precedence skipping a decision (FirstTest before Purchase)",
                 a -> add_precedence!(a, "FirstTest", "Purchase"))
end

# DVE certificates: every diagram with numbers, binary64 and rational modes, then mutations.
println("\n== DVE certificates ==")
const CERTS = Any[]

function run_cert(diagram, cert)
    out = IOBuffer()
    p = run(pipeline(ignorestatus(`$CERT_EXE $diagram $cert`); stdout=out, stderr=out))
    lines = split(chomp(String(take!(out))), '\n')
    field(prefix) = begin
        l = filter(x -> startswith(x, prefix), lines)
        isempty(l) ? "-" : strip(l[1][(length(prefix) + 1):end])
    end
    fails = [l for l in lines if endswith(l, ": FAIL") || startswith(l, "certificate: error") ||
                                 startswith(l, "error")]
    return (status=p.exitcode, matches=field("matches: "), exact=field("exactly normalised: "),
            nonneg=field("nonnegative: "), fails=fails, lines=lines)
end

# Exact companions recovered from a binary64 certificate: the simplest rational that rounds to
# each cell (`rationalize`), or the cell's own dyadic value when that one does not.
function companions(cert)
    tables = Dict{Tuple{Symbol,Int,Tuple},Any}()
    word(v) = reinterpret(Float64, parse(UInt64, v["f64"]; base=16))
    exact(x) = (q = rationalize(BigInt, x); Float64(q) == x ? q : Rational{BigInt}(x))
    for m in cert["mechanisms"], e in m["cpt"]["entries"]
        tables[(:cpt, parse(Int, m["id"]), Tuple(Int.(e["at"])))] = exact(word(e["value"]))
    end
    for u in cert["utilities"], e in u["table"]["entries"]
        tables[(:utility, parse(Int, u["id"]), Tuple(Int.(e["at"])))] = exact(word(e["value"]))
    end
    return tables
end

function cert_case(name, diagram, mode, export_cert)
    path = joinpath(OUT, "cert_" * slug(name) * "_" * mode * ".json")
    cert = try
        export_cert()
    catch e
        println("SKIP  cert $name [$mode]  (export_dve_certificate: $(nameof(typeof(e))))")
        return nothing
    end
    write(path, JSON3.write(cert))
    r = run_cert(diagram, path)
    ok = r.status == 0 && r.matches == "yes"
    push!(CERTS, (name=name, mode=mode, ok=ok, exact=r.exact, nonneg=r.nonneg, fails=r.fails))
    println(rpad(ok ? "PASS" : "FAIL", 6), rpad("$name [$mode]", 60), "| matches $(r.matches),",
            " nonnegative $(r.nonneg), exactly normalised $(r.exact)")
    for f in r.fails
        println("        ", f)
    end
    return ok ? path : nothing
end

const CERT_BASES = Dict{String,String}()
for c in CERT_MODELS
    p = cert_case(c.name, c.diagram, "binary64", () -> export_dve_certificate(c.model))
    p === nothing && continue
    CERT_BASES[c.name] = p
    b64 = JSON3.read(read(p, String), Dict{String,Any})
    cert_case(c.name, c.diagram, "rational",
              () -> export_dve_certificate(c.model; numeric_mode=:rational_exact,
                                           exact_tables=companions(b64)))
    if c.name == "umbrella"
        cert_case(c.name, c.diagram, "rational, no bits",
                  () -> export_dve_certificate(c.model; numeric_mode=:rational_exact,
                                               exact_tables=companions(b64),
                                               capture_runtime_bits=false))
    end
end

const CERT_MUTATIONS = Any[]
function cert_mutation(name, label, f!)
    base = CERT_BASES[name]
    diagram = only(c.diagram for c in CERT_MODELS if c.name == name)
    doc = JSON3.read(read(base, String), Dict{String,Any})
    f!(doc)
    path = joinpath(OUT, "certmut_" * slug(name) * "_" * slug(label) * ".json")
    write(path, JSON3.write(doc))
    r = run_cert(diagram, path)
    rejected = r.status != 0
    why = isempty(r.fails) ? "matches $(r.matches)" : join(r.fails, "; ")
    push!(CERT_MUTATIONS, (name=name, label=label, rejected=rejected, why=why))
    println(rpad(rejected ? "PASS" : "FAIL", 6), rpad("$name: $label", 64), "| lean: ",
            rejected ? "rejected ($why)" : "ACCEPTED")
end

if haskey(CERT_BASES, "umbrella")
    cert_mutation("umbrella", "swapped label order (Weather)",
                  d -> (s = d["variables"][1]["states"];
                        (s[1]["label"], s[2]["label"]) = (s[2]["label"], s[1]["label"])))
    cert_mutation("umbrella", "wrong axis (Forecast CPT axes reversed)",
                  d -> reverse!(d["mechanisms"][1]["cpt"]["axes"]))
    cert_mutation("umbrella", "wrong axis (utility axis Forecast for Weather)",
                  d -> (d["utilities"][1]["table"]["axes"][1] = "2"))
    cert_mutation("umbrella", "repeated variable in topological order",
                  d -> (d["topological_order"] = ["1", "1", "3"]))
    cert_mutation("umbrella", "topological order against an arc",
                  d -> (d["topological_order"] = ["2", "1", "3"]))
    cert_mutation("umbrella", "missing field (decision_order)",
                  d -> delete!(d, "decision_order"))
    cert_mutation("umbrella", "missing field (a state label)",
                  d -> delete!(d["variables"][2]["states"][1], "label"))
    cert_mutation("umbrella", "reference out of range (target 9)",
                  d -> (d["mechanisms"][1]["target"] = "9"))
    cert_mutation("umbrella", "factor cell not the CPT diagonal",
                  d -> (d["mechanisms"][1]["factor"]["entries"][1]["value"]["f64"] = "3fe0000000000000"))
    cert_mutation("umbrella", "entry coordinates out of order",
                  d -> reverse!(d["mechanisms"][1]["cpt"]["entries"]))
    cert_mutation("umbrella", "word not 16 hex digits",
                  d -> (d["utilities"][1]["table"]["entries"][1]["value"]["f64"] = "4034"))
    cert_mutation("umbrella", "duplicate pool entry",
                  d -> push!(d["reference_pool"],
                             Dict("code" => length(d["reference_pool"]),
                                  "reference" => Dict("type" => "NoRef"))))
    cert_mutation("umbrella", "kind decision on a chance variable",
                  d -> (d["variables"][1]["kind"] = "decision"))
end
if haskey(CERT_BASES, "two_stage (oil wildcatter)")
    cert_mutation("two_stage (oil wildcatter)", "decision order reversed",
                  d -> reverse!(d["decision_order"]))
    cert_mutation("two_stage (oil wildcatter)", "information slots swapped (Drill)",
                  d -> (s = d["decisions"][2]["information"];
                        (s[1]["variable"], s[2]["variable"]) = (s[2]["variable"], s[1]["variable"])))
end

npass = count(r -> r.ok, RESULTS)
nmut = count(r -> r.lean_ok, MUTATIONS)
nreader = count(r -> startswith(r.julia, "rejected by the reader"), MUTATIONS)
nvalidate = count(r -> startswith(r.julia, "rejected by validate"), MUTATIONS)
naccept = length(MUTATIONS) - nreader - nvalidate
println("\nComparisons: $(npass) pass, $(length(RESULTS) - npass) fail, of $(length(RESULTS)).")
println("Mutations rejected by Lean: $(nmut) of $(length(MUTATIONS)).")
println("Mutations rejected by Julia: $(nreader) by the reader, $(nvalidate) by validate; " *
        "accepted $(naccept) of $(length(MUTATIONS)).")
for r in MUTATIONS
    if !startswith(r.julia, "rejected")
        println("  Julia accepts mutated document ($(r.kind)): $(r.label): $(r.julia)")
    end
end
nverdict = count(r -> r.ok, VERDICTS)
println("Precedence and names: $(nverdict) of $(length(VERDICTS)) Lean verdicts equal Julia's.")
ncert = count(r -> r.ok, CERTS)
nexact = count(r -> r.ok && r.exact == "yes", CERTS)
println("Certificates matching: $(ncert) of $(length(CERTS)) " *
        "($(count(r -> r.mode == "binary64", CERTS)) binary64, " *
        "$(count(r -> r.mode != "binary64", CERTS)) rational); exactly normalised: $(nexact).")
ncmut = count(r -> r.rejected, CERT_MUTATIONS)
println("Certificate mutations rejected by Lean: $(ncmut) of $(length(CERT_MUTATIONS)).")
exit(npass == length(RESULTS) && nmut == length(MUTATIONS) && naccept == 0 &&
     nverdict == length(VERDICTS) && ncert == length(CERTS) &&
     ncmut == length(CERT_MUTATIONS) ? 0 : 1)
