using Dates: DateTime

@testset "Model cards" begin
    m = reference_habitat_model()

    @testset "construction from a model" begin
        card = ModelCard(m; decision_context="grazing policy for the reserve",
                         endpoint="Occupancy of the focal species",
                         spatial_extent="the 400 km2 reserve",
                         temporal_extent="one growing season",
                         graph_rationale="expert workshop, SPEC section 45",
                         alternative_structures=["Vegetation -> Occupancy directly"],
                         elicitation_protocol="three-point elicitation, two rounds",
                         validation_summary="no independent data yet",
                         intended_use="scenario comparison",
                         limitations="conditional predictions, not causal claims",
                         license="CC BY 4.0", model_version="1.2")
        @test card isa ModelCard
        @test card.name == :model
        @test card.schema_version == CARD_SCHEMA_VERSION
        @test card.model_version == "1.2"
        @test card.variables == variable_names(syntax(m))
        @test card.states[:SoilMoisture] == [:low, :medium, :high]
        @test sort(collect(keys(card.state_definitions))) == sort(card.variables)
        @test all(isempty, values(card.state_definitions))
        @test card.mechanisms == mechanism_names(syntax(m))
        @test card.kernel_refs[:Occupancy_mechanism] ==
              kernel_ref(syntax(m), :Occupancy_mechanism)
        @test isempty(card.history) && isempty(card.provenance)
        @test undocumented_mechanisms(card) == card.mechanisms
        @test occursin("7 variables", sprint(show, card))
        # The history of a rewritten model is carried over.
        md = do_intervention(m, :GrazingPressure => :low; note="cull")
        @test length(ModelCard(md).history) == 1
        # `extras[:name]` names the card, and keywords override every default.
        named = BayesModel(syntax(m); extras=Dict{Symbol,Any}(:name => :habitat))
        @test ModelCard(named).name == :habitat
        @test ModelCard(m; name=:other, variables=[:Only]).variables == [:Only]
    end

    @testset "parameter provenance" begin
        card = ModelCard(m)
        p = ParameterProvenance(; source_type=:elicited, expert="regional panel",
                                citation="Marcot et al. (2006)",
                                timestamp=DateTime(2026, 1, 2, 3, 4, 5),
                                notes="three-point elicitation")
        @test p.source_type == :elicited && p.dataset == ""
        @test p == ParameterProvenance(; source_type=:elicited, expert="regional panel",
                                       citation="Marcot et al. (2006)",
                                       timestamp=DateTime(2026, 1, 2, 3, 4, 5),
                                       notes="three-point elicitation")
        @test hash(p) == hash(ParameterProvenance(; source_type=:elicited,
                                                  expert="regional panel",
                                                  citation="Marcot et al. (2006)",
                                                  timestamp=DateTime(2026, 1, 2, 3, 4, 5),
                                                  notes="three-point elicitation"))
        @test_throws ArgumentError ParameterProvenance(; source_type=:guessed)
        @test provenance!(card, :Occupancy_mechanism => p) === card
        @test provenance(card, :Occupancy_mechanism) == p
        @test provenance(card)[:Occupancy_mechanism] == p
        @test !(:Occupancy_mechanism in undocumented_mechanisms(card))
        # A mechanism with nothing recorded reports an `:unknown` source.
        @test provenance(card, :Climate_mechanism) == ParameterProvenance()
        @test provenance(card, :Climate_mechanism).source_type == :unknown
        # A mechanism that is not the card's is refused, which keeps card and model in
        # step.
        @test_throws UnknownMechanismError provenance!(card,
                                                       :Nope_mechanism => ParameterProvenance())
        @test_throws UnknownMechanismError provenance(card, :Nope_mechanism)
        # The vector form attaches several at once.
        provenance!(card,
                    [:Climate_mechanism => ParameterProvenance(; source_type=:literature,
                                                               citation="Chen and Pollino (2012)"),
                     :Vegetation_mechanism => ParameterProvenance(; source_type=:empirical,
                                                                  dataset="transects 2019-2024",
                                                                  estimator="Dirichlet-multinomial")])
        @test length(provenance(card)) == 3
        @test provenance(card, :Vegetation_mechanism).estimator ==
              "Dirichlet-multinomial"
    end

    @testset "markdown report" begin
        card = ModelCard(do_intervention(m, :GrazingPressure => :low; note="cull");
                         decision_context="grazing policy", endpoint="Occupancy",
                         spatial_extent="reserve", temporal_extent="season",
                         graph_rationale="expert workshop",
                         alternative_structures=["without HabitatQuality"],
                         elicitation_protocol="two rounds",
                         validation_summary="expert review only",
                         validation_scores=Dict(:brier => 0.21, :log_score => -0.65),
                         intended_use="scenario comparison", limitations="no holdout",
                         license="CC BY 4.0")
        provenance!(card,
                    :Occupancy_mechanism => ParameterProvenance(; source_type=:elicited,
                                                                expert="panel",
                                                                notes="round 2"))
        md = report(card)
        for heading in ("# Model card: model", "## Decision context",
                        "## Endpoint and extent", "## Graph rationale and alternatives",
                        "## Variables and states",
                        "## Mechanisms and parameter provenance",
                        "## Elicitation protocol", "## Validation",
                        "## Intended use and limitations", "## Model history",
                        "## Release")
            @test occursin(heading, md)
        end
        @test occursin("grazing policy", md)
        @test occursin("without HabitatQuality", md)
        @test occursin("| `Occupancy` | absent, present |", md)
        @test occursin("elicited", md) && occursin("panel", md)
        @test occursin("Mechanisms without provenance:", md)
        @test occursin("brier | 0.21", md)
        @test occursin("CC BY 4.0", md)
        @test occursin("hard", md)          # the intervention in the history
        # Empty fields are shown as gaps rather than hidden.
        bare = report(ModelCard(m))
        @test occursin("*Not documented.*", bare)
        @test occursin("*No alternative structures recorded.*", bare)
        @test occursin("*No scores recorded.*", bare)
        @test occursin("*No recorded rewrites.*", bare)
        # The two forms agree.
        io = IOBuffer()
        @test report(io, card) === nothing
        @test String(take!(io)) == md
    end

    @testset "JSON round trip and backwards compatibility" begin
        card = ModelCard(m; decision_context="grazing policy", endpoint="Occupancy",
                         alternative_structures=["A", "B"],
                         state_definitions=Dict(:Occupancy => "detected in >= 1 survey"),
                         validation_scores=Dict(:brier => 0.21), license="CC BY 4.0")
        provenance!(card,
                    :Occupancy_mechanism => ParameterProvenance(; source_type=:elicited,
                                                                expert="panel",
                                                                timestamp=DateTime(2026,
                                                                                   1, 2)))
        # Inside a model document.
        str = json_model(m; card=card)
        @test parse_json_card(str) == card
        @test parse_json_model(str) == m
        # On its own.
        @test parse_json_card(json_card(card)) == card
        # A document without a card, written by an older version of the package, is
        # still read; the model is identical either way.
        @test parse_json_card(json_model(m)) === nothing
        @test parse_json_model(json_model(m)) == parse_json_model(str)
        @test_throws FormatError parse_json_card("{}")
        @test_throws FormatError parse_json_card("[]")
        # Through files.
        path = tempname()
        write_json_model(path, m; card=card)
        @test read_json_card(path) == card
        @test read_json_model(path) == m
        plain = tempname()
        write_json_model(plain, m)
        @test read_json_card(plain) === nothing
        @test read_json_model(plain) == m
        rm(path)
        return rm(plain)
    end
end
