# The SPEC section 45 reference network split into an abiotic component (closed, exporting
# SoilMoisture) and a biotic component (importing SoilMoisture). The same two networks are
# the pieces `CategoricalBayesianNetworks.jl` composes in its own suite.
function abiotic_bn()
    return bayesnet(:Climate => [:dry, :normal, :wet], :Irrigation => [:low, :high],
                    :SoilMoisture => [:low, :medium, :high];
                    mechanisms=[:SoilMoisture => (:Climate, :Irrigation)])
end

function biotic_bn(; grazing_input::Bool=false)
    mechs = Any[:Vegetation => (:SoilMoisture, :GrazingPressure),
                :HabitatQuality => :Vegetation, :Occupancy => :HabitatQuality]
    grazing_input || push!(mechs, :GrazingPressure => ())
    return bayesnet(:SoilMoisture => [:low, :medium, :high],
                    :GrazingPressure => [:low, :high],
                    :Vegetation => [:sparse, :moderate, :dense],
                    :HabitatQuality => [:poor, :good],
                    :Occupancy => [:absent, :present]; mechanisms=mechs, closed=false)
end
