# The exception hierarchy of ADR 0013. Every exception type this package defines subtypes
# `BayesNetError`; `AnyBayesNetError` covers those, the two lower roots and the stand-alone
# Graphviz errors. Because the kernel API is re-exported, every exception type FiniteKernels
# exports is re-exported too, as the same binding; of BayesianNetworkFormats only the root
# is, because the conformance adapters load this package with `using` and the inspect
# adapter records Formats' concrete types under their qualified names. The frozen name
# `ImpossibleEvidenceError` keeps its module and its unqualified printing. `==` compares
# fields with `isequal`, so that it agrees with `hash`.
using FiniteKernels: FiniteKernels
using BayesianNetworkFormats: BayesianNetworkFormats

# Concrete and abstract exception types whose binding `M` owns. `AnyBayesNetError` is a
# `Union`, on which `parentmodule` throws, so only data types are considered.
function owned_exception_types(M)
    types = Type[]
    for n in names(M; all=true)
        isdefined(M, n) || continue
        T = getglobal(M, n)
        T isa DataType && T <: Exception && parentmodule(T) === M && push!(types, T)
    end
    return types
end

function exported_exception_names(M)
    return filter(names(M)) do n
        T = getglobal(M, n)
        return T isa Type && T <: Exception
    end
end

function caught(f)
    try
        f()
    catch e
        return e
    end
    return nothing
end

@testset "errors" begin
    @testset "hierarchy" begin
        owned = owned_exception_types(BayesianNetworks)
        # The search is not vacuous: it finds the root and the 29 concrete types.
        @test BayesNetError in owned
        @test issubset([UnknownVariableError, FormatError, ImpossibleEvidenceError,
                        UnnormalizedKernelError, NotUnrolledError], owned)
        @test length(owned) >= 30
        for T in owned
            @test T <: BayesNetError
            @test parentmodule(T) === BayesianNetworks
            @test string(T) == string(nameof(T))
        end
        @test isabstracttype(BayesNetError)
        @test BayesNetError <: Exception
        # A frozen name: the domain certifier compares it as a bare string.
        @test parentmodule(ImpossibleEvidenceError) === BayesianNetworks
        @test string(ImpossibleEvidenceError) == "ImpossibleEvidenceError"
    end

    @testset "AnyBayesNetError" begin
        @test AnyBayesNetError isa Union
        @test Base.which(BayesianNetworks, :AnyBayesNetError) === BayesianNetworks
        for T in (BayesNetError, FiniteKernelsError, BayesianNetworkFormatsError)
            @test T <: AnyBayesNetError
        end
        # Every exception type of the stand-alone Graphviz submodule is covered, so a new
        # one there cannot be missed.
        graphviz = owned_exception_types(BayesianNetworks.Graphviz)
        @test issubset([Graphviz.UnavailableGraphvizError,
                        Graphviz.UnknownLayoutProgramError],
                       graphviz)
        for T in graphviz
            @test T <: AnyBayesNetError
        end
        # Base exceptions stay outside.
        @test !(ArgumentError <: AnyBayesNetError)
        @test !(KeyError <: AnyBayesNetError)
        @test !(SystemError <: AnyBayesNetError)
    end

    @testset "errors of every layer are caught by AnyBayesNetError" begin
        # This package's own: a cyclic network.
        cyclic = reference_habitat_bn()
        add_input!(cyclic, mechanism_of(cyclic, :Climate), :Occupancy)
        @test_throws AnyBayesNetError validate(cyclic)
        @test caught(() -> validate(cyclic)) isa CyclicBayesNetError
        # FiniteKernels', passing through `JointTable` unchanged.
        k = FiniteKernel(FiniteSpace(:X, [:a, :b]), FiniteSpace(:Y, [:u, :v]),
                         fill(0.5, 2, 2))
        @test_throws AnyBayesNetError JointTable(k)
        @test caught(() -> JointTable(k)) isa SpaceMismatchError
        # BayesianNetworkFormats', passing through `read_bayesnet` unchanged.
        bad = joinpath(mktempdir(), "bad.bif")
        write(bad, "network {")
        @test_throws AnyBayesNetError read_bayesnet(bad)
        @test caught(() -> read_bayesnet(bad)) isa BayesianNetworkFormats.ParseError
        # The Graphviz submodule's.
        g = Graphviz.Digraph("G", Graphviz.Statement[])
        @test_throws AnyBayesNetError Graphviz.run_graphviz(g; prog="nope")
        # Outside: a missing file.
        missing_file = joinpath(mktempdir(), "missing.bif")
        e = caught(() -> read_bayesnet(missing_file))
        @test e isa SystemError
        @test !(e isa AnyBayesNetError)
    end

    @testset "re-exports" begin
        exported = names(BayesianNetworks)
        @test :AnyBayesNetError in exported
        # Drift: every exception type FiniteKernels exports, the root included.
        fk = exported_exception_names(FiniteKernels)
        @test issubset([:FiniteKernelsError, :InvalidAxisError, :KernelShapeError,
                        :KernelEntryError, :KernelNormalizationError, :SpaceMismatchError],
                       fk)
        for n in fk
            @test n in exported
            @test getglobal(BayesianNetworks, n) === getglobal(FiniteKernels, n)
        end
        # Of BayesianNetworkFormats, the root only.
        @test :BayesianNetworkFormatsError in exported
        @test BayesianNetworkFormatsError ===
              BayesianNetworkFormats.BayesianNetworkFormatsError
        fmt = exported_exception_names(BayesianNetworkFormats)
        @test issubset([:ParseError, :ValidationError, :NotNormalizedError], fmt)
        for n in fmt
            n === :BayesianNetworkFormatsError && continue
            @test n ∉ exported
        end
        # What the inspect adapter sees: it loads this package with `using` and Formats
        # with `import`, so Formats' types print qualified and the frozen name bare.
        adapter = Module(:InspectAdapterLike)
        Core.eval(adapter,
                  :(using BayesianNetworks;
                    using BayesianNetworkFormats: BayesianNetworkFormats))
        shown(T) = sprint(show, T; context=:module => adapter)
        @test shown(BayesianNetworkFormats.ParseError) ==
              "BayesianNetworkFormats.ParseError"
        @test shown(ImpossibleEvidenceError) == "ImpossibleEvidenceError"
        @test shown(KernelEntryError) == "KernelEntryError"
    end

    @testset "equality agrees with hash" begin
        # NaN fields: an error equals itself and an identical one.
        e = UnnormalizedKernelError(:X, NaN)
        @test e == e
        @test e == UnnormalizedKernelError(:X, NaN)
        @test isequal(e, UnnormalizedKernelError(:X, NaN))
        @test hash(e) == hash(UnnormalizedKernelError(:X, NaN))
        @test length(Set([e, UnnormalizedKernelError(:X, NaN)])) == 1
        # Signed zeros: `isequal` tells them apart, and so does `hash`.
        @test UnnormalizedKernelError(:X, 0.0) != UnnormalizedKernelError(:X, -0.0)
        @test UnnormalizedKernelError(:X, 0.0) == UnnormalizedKernelError(:X, 0.0)
        # Different types never compare equal, even with equal fields.
        @test UnknownVariableError(:A) != UnknownMechanismError(:A)
        # A sample with vector, `Any`, `Dict`, `nothing`, NaN and signed-zero fields: for
        # every pair, `==` and `isequal` agree, and equal errors hash alike.
        sample = BayesNetError[UnnormalizedKernelError(:X, NaN),
                               UnnormalizedKernelError(:X, NaN),
                               UnnormalizedKernelError(:X, 0.0),
                               UnnormalizedKernelError(:X, -0.0),
                               UnnormalizedKernelError(:Y, 0.0),
                               CyclicBayesNetError([:A, :B], [1, 2]),
                               CyclicBayesNetError([:A, :B], [1, 2]),
                               CyclicBayesNetError([:B, :A], [2, 1]),
                               InterfaceMismatchError(:states, 1, [:a, :b], [:a], "glue"),
                               InterfaceMismatchError(:states, 1, [:a, :b], [:a], "glue"),
                               InterfaceMismatchError(:length, 0, NaN, NaN, "glue"),
                               InterfaceMismatchError(:length, 0, NaN, NaN, "glue"),
                               InterfaceMismatchError(:length, 0, 0.0, -0.0, "glue"),
                               InterfaceMismatchError(:length, 0, 0.0, 0.0, "glue"),
                               ImpossibleEvidenceError(Dict(:A => :a)),
                               ImpossibleEvidenceError(Dict(:A => :a)),
                               ImpossibleEvidenceError(Dict{Symbol,Symbol}()),
                               NotUnrolledError(:rollout),
                               NotUnrolledError(:rollout, nothing),
                               NotUnrolledError(:rollout, :A),
                               ProofCertificateError(:x, :Variable, 0, nothing, "m"),
                               ProofCertificateError(:x, :Variable, 0, nothing, "m")]
        for a in sample, b in sample
            @test (a == b) == isequal(a, b)
            a == b && @test hash(a) == hash(b)
        end
        # Each error equals itself, NaN fields included.
        @test all(a -> a == a, sample)
        # The pairs built alike are equal; the others are not.
        @test sample[1] == sample[2]
        @test sample[3] != sample[4]
        @test sample[6] == sample[7] != sample[8]
        @test sample[11] == sample[12]
        @test sample[13] != sample[14]
        @test sample[18] == sample[19] != sample[20]
    end
end
