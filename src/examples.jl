"""
    reference_habitat_bn() -> BayesNet

The reference ecological network of SPEC §45, structure only (no kernels attached):

    Climate -> SoilMoisture -> Vegetation -> HabitatQuality -> Occupancy
    Irrigation -> SoilMoisture
    GrazingPressure -> Vegetation

Variables and states: `Climate` (dry, normal, wet), `Irrigation` (low, high),
`SoilMoisture` (low, medium, high), `GrazingPressure` (low, high),
`Vegetation` (sparse, moderate, dense), `HabitatQuality` (poor, good),
`Occupancy` (absent, present). Parent order of `SoilMoisture` is
`(Climate, Irrigation)` and of `Vegetation` is `(SoilMoisture, GrazingPressure)`. The
states are those of the `habitat_reference` fixtures of BayesianNetworkFormats.jl, so
that [`reference_habitat_model`](@ref) and the files agree.
"""
function reference_habitat_bn()
    return bayesnet(:Climate => [:dry, :normal, :wet],
                    :Irrigation => [:low, :high],
                    :SoilMoisture => [:low, :medium, :high],
                    :GrazingPressure => [:low, :high],
                    :Vegetation => [:sparse, :moderate, :dense],
                    :HabitatQuality => [:poor, :good],
                    :Occupancy => [:absent, :present];
                    mechanisms=[:SoilMoisture => (:Climate, :Irrigation),
                                :Vegetation => (:SoilMoisture, :GrazingPressure),
                                :HabitatQuality => (:Vegetation,),
                                :Occupancy => (:HabitatQuality,)])
end

"""
    reference_habitat_model() -> BayesModel

[`reference_habitat_bn`](@ref) with the conditional probability tables of the
`habitat_reference` fixtures of BayesianNetworkFormats.jl bound
([`bind_cpt`](@ref), parents-first layout), so that
`read_bayesnet(fixture_path("dne/habitat_reference.dne")) ≈ reference_habitat_model()`.
Every mechanism's reference is `NamedRef("<Variable>_mechanism")`.
"""
function reference_habitat_model()
    m = BayesModel(reference_habitat_bn())
    sm = zeros(3, 2, 3)                # (Climate, Irrigation, SoilMoisture)
    sm[1, 1, :] = [0.7, 0.25, 0.05]    # dry, low
    sm[1, 2, :] = [0.3, 0.5, 0.2]      # dry, high
    sm[2, 1, :] = [0.3, 0.5, 0.2]      # normal, low
    sm[2, 2, :] = [0.1, 0.4, 0.5]      # normal, high
    sm[3, 1, :] = [0.1, 0.4, 0.5]      # wet, low
    sm[3, 2, :] = [0.05, 0.25, 0.7]    # wet, high
    veg = zeros(3, 2, 3)               # (SoilMoisture, GrazingPressure, Vegetation)
    veg[1, 1, :] = [0.6, 0.3, 0.1]     # low moisture, low grazing
    veg[1, 2, :] = [0.8, 0.15, 0.05]   # low moisture, high grazing
    veg[2, 1, :] = [0.2, 0.5, 0.3]
    veg[2, 2, :] = [0.4, 0.45, 0.15]
    veg[3, 1, :] = [0.05, 0.3, 0.65]
    veg[3, 2, :] = [0.2, 0.5, 0.3]
    return bind_cpt(m,
                    [:Climate => [0.3, 0.5, 0.2],
                     :Irrigation => [0.6, 0.4],
                     :SoilMoisture => sm,
                     :GrazingPressure => [0.5, 0.5],
                     :Vegetation => veg,
                     :HabitatQuality => [0.85 0.15; 0.4 0.6; 0.15 0.85],
                     :Occupancy => [0.8 0.2; 0.25 0.75]])
end

"""
    vegetation_herbivore_dbn(; management = false) -> DynamicBayesNet

The dynamic ecological template of SPEC §43, structure only: `Vegetation`
(sparse, dense) and `Herbivores` (low, high) in every slice, with the within-slice
edge `Vegetation_t -> Herbivores_t` and the feedback across slices
`Vegetation_{t-1} -> Vegetation_t` and `Herbivores_{t-1} -> Vegetation_t` (lag 1;
parent order of `Vegetation` is `(Vegetation[t-1], Herbivores[t-1])`). The initial
network has the prior `Vegetation -> Herbivores`.

With `management = true` every slice also carries the exogenous variable `Management`
(none, cull) with a prior mechanism and the edge `Management_t -> Herbivores_t`
(parent order of `Herbivores` is `(Vegetation, Management)`).
"""
function vegetation_herbivore_dbn(; management::Bool=false)
    herb_parents = management ? (:Vegetation, :Management) : (:Vegetation,)
    vars = Any[:Vegetation => [:sparse, :dense], :Herbivores => [:low, :high]]
    management && push!(vars, :Management => [:none, :cull])
    initial = bayesnet(vars...; mechanisms=[:Herbivores => herb_parents])
    transition = bayesnet(vars..., lagged(:Vegetation, 1) => [:sparse, :dense],
                          lagged(:Herbivores, 1) => [:low, :high];
                          mechanisms=[:Vegetation => (lagged(:Vegetation, 1),
                                                      lagged(:Herbivores, 1)),
                                      :Herbivores => herb_parents],
                          closed=false)
    if management
        add_mechanism!(transition, :Management)
    end
    return DynamicBayesNet(initial, transition; lags=1)
end

"""
    vegetation_herbivore_model(; management = false) -> DynamicBayesModel

[`vegetation_herbivore_dbn`](@ref) with fixed, plausible tables bound
([`bind_cpt`](@ref), parents-first layout). Initial slice: `Vegetation ~ (0.4, 0.6)`
and `P(Herbivores = high | Vegetation) = 0.3, 0.7` for sparse, dense. Transition:
`P(Vegetation_t = dense | Vegetation_{t-1}, Herbivores_{t-1})` is `0.5` (sparse, low),
`0.2` (sparse, high), `0.9` (dense, low) and `0.6` (dense, high), and the herbivore
response is the same as in the initial slice. With `management = true`, `Management ~
(0.8, 0.2)` in every slice and culling lowers `P(Herbivores = high | Vegetation)` to
`0.1, 0.4`.
"""
function vegetation_herbivore_model(; management::Bool=false)
    dm = DynamicBayesModel(vegetation_herbivore_dbn(; management=management))
    veg = zeros(2, 2, 2)                 # (Vegetation[t-1], Herbivores[t-1], Vegetation)
    veg[1, 1, :] = [0.5, 0.5]            # sparse, low
    veg[1, 2, :] = [0.8, 0.2]            # sparse, high
    veg[2, 1, :] = [0.1, 0.9]            # dense, low
    veg[2, 2, :] = [0.4, 0.6]            # dense, high
    herb = if management
        h = zeros(2, 2, 2)               # (Vegetation, Management, Herbivores)
        h[1, 1, :] = [0.7, 0.3]          # sparse, none
        h[1, 2, :] = [0.9, 0.1]          # sparse, cull
        h[2, 1, :] = [0.3, 0.7]          # dense, none
        h[2, 2, :] = [0.6, 0.4]          # dense, cull
        h
    else
        [0.7 0.3; 0.3 0.7]               # rows = Vegetation
    end
    dm = bind_cpt(dm, [:Vegetation => [0.4, 0.6], :Herbivores => herb]; slice=:initial)
    dm = bind_cpt(dm, [:Vegetation => veg, :Herbivores => herb]; slice=:transition)
    if management
        dm = bind_cpt(dm, :Management => [0.8, 0.2]; slice=:initial)
        dm = bind_cpt(dm, :Management => [0.8, 0.2]; slice=:transition)
    end
    return dm
end
