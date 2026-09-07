# Model cards and parameter provenance
Simon Frost

- [Overview](#overview)
- [Setup](#setup)
- [A card for a model](#a-card-for-a-model)
- [Where the numbers came from](#where-the-numbers-came-from)
- [Validation, honestly](#validation-honestly)
- [The report](#the-report)
- [Carrying the card with the model](#carrying-the-card-with-the-model)
- [Summary](#summary)
- [References](#references)

## Overview

Reviews of ecological belief-network practice keep reaching the same
verdict: the networks are intelligible, but the reporting around them is
not. Marcot et al. ([2006](#ref-Marcot2006)) set out what a defensible
model should say about itself; Chen and Pollino
([2012](#ref-ChenPollino2012)) turned that into a practical checklist
for environmental models; Kaikkonen et al. ([2021](#ref-Kaikkonen2021)),
after screening several hundred studies, found elicitation methods and
validation still reported too thinly to review or reuse. The gap is not
an algorithm. It is that a model usually travels as a file of tables,
with the decision it was built for, the meaning of its states, the
source of each table and the limits of its use left in a paper, an inbox
or somebody’s memory.

A `ModelCard` is that missing record, held beside the model and
serialised with it. This vignette builds one for the reference habitat
network, records where each conditional probability table came from,
writes the card as Markdown, and reads it back out of the JSON envelope.
Nothing here changes a kernel: a card is metadata, and two models with
different cards are still the same model.

## Setup

``` julia
using BayesianNetworks

m = reference_habitat_model()
variable_names(syntax(m))
```

    7-element Vector{Symbol}:
     :Climate
     :Irrigation
     :SoilMoisture
     :GrazingPressure
     :Vegetation
     :HabitatQuality
     :Occupancy

## A card for a model

`ModelCard(m)` fills in everything that can be read off the model – the
variables and their states, the mechanisms and the references they
resolve to, and the history of any rewrites – and leaves the narrative
fields for the modeller. Those fields are the ones a reviewer needs:
which decision the model serves, which endpoint it predicts, over which
spatial and temporal extent, why the graph looks the way it does, and
which other structures were considered and rejected.

``` julia
card = ModelCard(m;
                 name = :habitat_occupancy,
                 model_version = "1.0",
                 decision_context = """
                     Whether to reduce stocking rates on a 400 km2 reserve, and where.
                     """,
                 endpoint = "Occupancy of the focal species at the end of the season",
                 spatial_extent = "the reserve, in 1 km grid cells",
                 temporal_extent = "one growing season, 2026",
                 graph_rationale = """
                     Elicited at a two-day workshop: climate and irrigation drive soil
                     moisture, soil moisture and grazing drive vegetation, and occupancy
                     responds to habitat quality rather than to vegetation directly.
                     """,
                 alternative_structures = ["Vegetation -> Occupancy without HabitatQuality",
                                           "GrazingPressure -> HabitatQuality directly"],
                 elicitation_protocol = """
                     Four ecologists, three-point elicitation of each row, two rounds
                     with feedback, linear pooling of the second round.
                     """,
                 validation_summary = """
                     Temporal holdout: fitted on the 2019-2022 transects and scored on
                     2023-2024, against a baseline of the marginal occupancy rate.
                     """,
                 intended_use = "comparing stocking scenarios at reserve scale",
                 limitations = """
                     Conditional scenario predictions, not evidence that a stocking
                     change causes the predicted occupancy; not transferable off the
                     reserve; no independent validation data yet.
                     """,
                 license = "CC BY 4.0")
```

    ModelCard(:habitat_occupancy v1.0, 7 variables, 0/7 mechanisms with provenance)

The structural half is already populated, and per-variable state
definitions start empty, which is deliberate: an empty field is a gap
the report will show.

``` julia
(card.variables, card.states[:HabitatQuality], length(card.mechanisms))
```

    ([:Climate, :Irrigation, :SoilMoisture, :GrazingPressure, :Vegetation, :HabitatQuality, :Occupancy], [:poor, :good], 7)

State definitions say what a state *means* in the field, which is what
makes a model reusable by someone who was not at the workshop. They are
ordinary text, keyed by variable.

``` julia
card.state_definitions[:Occupancy] = "detected in at least one of four surveys"
card.state_definitions[:Vegetation] = "mean sward height: <5 cm, 5-15 cm, >15 cm"
card.state_definitions[:HabitatQuality] = "composite index below or above 0.6"
sort(collect(keys(filter(p -> !isempty(last(p)), card.state_definitions))))
```

    3-element Vector{Symbol}:
     :HabitatQuality
     :Occupancy
     :Vegetation

## Where the numbers came from

Ecological networks mix estimates from data, numbers taken from the
literature, values derived from process models and numbers elicited from
experts, and the four are not equally strong evidence ([Chen and Pollino
2012](#ref-ChenPollino2012)). `ParameterProvenance` records, per
mechanism, which kind a table is and everything needed to trace it: a
citation, the dataset, the estimator, the expert or panel, a timestamp
and free notes (the field list of section 49 of the package
specification).

``` julia
provenance!(card,
            [:SoilMoisture_mechanism =>
             ParameterProvenance(; source_type = :mechanistic,
                                 citation = "reserve water-balance model v3",
                                 estimator = "discretised model output",
                                 notes = "run on 2015-2025 rainfall"),
             :Vegetation_mechanism =>
             ParameterProvenance(; source_type = :empirical,
                                 dataset = "grazing transects 2019-2024, n = 812",
                                 estimator = "Dirichlet-multinomial, weak prior"),
             :HabitatQuality_mechanism =>
             ParameterProvenance(; source_type = :literature,
                                 citation = "Marcot et al. (2006), Table 2"),
             :Occupancy_mechanism =>
             ParameterProvenance(; source_type = :elicited,
                                 expert = "panel of four reserve ecologists",
                                 notes = "three-point elicitation, second round")])
provenance(card, :Vegetation_mechanism)
```

    ParameterProvenance(:empirical, "", "grazing transects 2019-2024, n = 812", "Dirichlet-multinomial, weak prior", "", nothing, "")

The point of recording sources per mechanism is that the gaps become
visible. `undocumented_mechanisms` lists the tables nobody has yet
accounted for; here they are the three root variables, whose priors were
taken from the file the model was read from.

``` julia
undocumented_mechanisms(card)
```

    3-element Vector{Symbol}:
     :Climate_mechanism
     :Irrigation_mechanism
     :GrazingPressure_mechanism

Asking for a mechanism with nothing recorded returns an `:unknown`
provenance rather than an error, and a mechanism that is not the model’s
is refused, so a card cannot drift away from the network it describes.

``` julia
err = try
    provenance!(card, :Rainfall_mechanism => ParameterProvenance())
catch e
    e
end
(provenance(card, :Climate_mechanism).source_type, sprint(showerror, err))
```

    (:unknown, "UnknownMechanismError: no mechanism named :Rainfall_mechanism")

## Validation, honestly

The card separates what was done to test the model from the scores that
testing produced. The free-text summary, filled in above, is where the
design of the test belongs – which data were held out, how, and against
which baseline. The `validation_scores` slot holds the numbers, and is
what `BayesianNetworkInference.jl`’s scoring layer fills; leaving it
empty is itself a statement, which the report prints as one.

``` julia
card.validation_scores[:brier] = 0.21
card.validation_scores[:log_score] = -0.65
card
```

    ModelCard(:habitat_occupancy v1.0, 7 variables, 4/7 mechanisms with provenance, 2 scores)

## The report

`report` writes the card as Markdown, in the order a reader needs it:
context first, then the structure, then the numbers and their sources,
then how the model was tested and what it must not be used for. Fields
that were left empty are printed as *Not documented.*, so the report
shows its own gaps rather than hiding them.

``` julia
md = report(card)
println(join(first(split(md, "\n"), 24), "\n"))
```

    # Model card: habitat_occupancy

    ## Decision context

    Whether to reduce stocking rates on a 400 km2 reserve, and where.


    ## Endpoint and extent

    - Endpoint: Occupancy of the focal species at the end of the season
    - Spatial extent: the reserve, in 1 km grid cells
    - Temporal extent: one growing season, 2026

    ## Graph rationale and alternatives

    Elicited at a two-day workshop: climate and irrigation drive soil
    moisture, soil moisture and grazing drive vegetation, and occupancy
    responds to habitat quality rather than to vegetation directly.


    - Vegetation -> Occupancy without HabitatQuality
    - GrazingPressure -> HabitatQuality directly

    ## Variables and states

The provenance table is the part that a reviewer will read first.

``` julia
sections = split(md, "## ")
println("## ", first(filter(s -> startswith(s, "Mechanisms"), sections)))
```

    ## Mechanisms and parameter provenance

    | Mechanism | Reference | Source | Citation | Dataset | Estimator | Expert | Timestamp | Notes |
    |---|---|---|---|---|---|---|---|---|
    | `SoilMoisture_mechanism` | `SoilMoisture_mechanism` | mechanistic | reserve water-balance model v3 |  | discretised model output |  |  | run on 2015-2025 rainfall |
    | `Vegetation_mechanism` | `Vegetation_mechanism` | empirical |  | grazing transects 2019-2024, n = 812 | Dirichlet-multinomial, weak prior |  |  |  |
    | `HabitatQuality_mechanism` | `HabitatQuality_mechanism` | literature | Marcot et al. (2006), Table 2 |  |  |  |  |  |
    | `Occupancy_mechanism` | `Occupancy_mechanism` | elicited |  |  |  | panel of four reserve ecologists |  | three-point elicitation, second round |
    | `Climate_mechanism` | `Climate_mechanism` | *not documented* |  |  |  |  |  |  |
    | `Irrigation_mechanism` | `Irrigation_mechanism` | *not documented* |  |  |  |  |  |  |
    | `GrazingPressure_mechanism` | `GrazingPressure_mechanism` | *not documented* |  |  |  |  |  |  |

    Mechanisms without provenance: `Climate_mechanism`, `Irrigation_mechanism`, `GrazingPressure_mechanism`.

## Carrying the card with the model

A card that lives in a separate document is a card that gets lost.
`json_model` takes one and writes it into the same envelope as the
syntax, semantics, evidence and history; `read_json_card` reads it back,
and returns `nothing` for a file written without one, so older model
files still read exactly as before.

``` julia
path = tempname()
write_json_model(path, m; card = card)
(read_json_card(path) == card, read_json_model(path) == m)
```

    (true, true)

``` julia
plain = tempname()
write_json_model(plain, m)
(read_json_card(plain), read_json_model(plain) == m)
```

    (nothing, true)

Because a card is metadata, it never enters the semantics: the same
model with and without a card is the same value, evaluates identically,
and compares equal.

``` julia
(read_json_model(path) == read_json_model(plain),
 marginal(read_json_model(path), :Occupancy) ≈ marginal(m, :Occupancy))
```

    (true, true)

``` julia
rm(path)
rm(plain)
```

## Summary

- A `ModelCard` records what the ecology reporting standard asks of a
  model: decision context, endpoint and extent, graph rationale and the
  alternatives considered, state definitions, parameter provenance,
  elicitation protocol, validation, intended use, limitations, licence
  and version.
- `ModelCard(m)` prefills the structural half from a model; the
  narrative fields are the modeller’s to write, and empty ones are
  reported as gaps rather than omitted.
- `ParameterProvenance` records per mechanism whether a table is
  empirical, elicited, from the literature or mechanistic, with the
  citation, dataset, estimator, expert and timestamp needed to trace it;
  `undocumented_mechanisms` lists what is still missing.
- `report` writes the card as Markdown, and `json_model(m; card)`
  carries it in the model’s own JSON envelope, with files that predate
  cards reading unchanged.
- A card is metadata: it never changes a kernel, an evaluation or model
  equality.

This is the last vignette in the series; the scoring layer that fills
`validation_scores` lives in `BayesianNetworkInference.jl`.

## References

<div id="refs" class="references csl-bib-body hanging-indent">

<div id="ref-ChenPollino2012" class="csl-entry">

Chen, Serena H., and Carmel A. Pollino. 2012. “Good Practice in Bayesian
Network Modelling.” *Environmental Modelling & Software* 37: 134–45.
<https://doi.org/10.1016/j.envsoft.2012.03.016>.

</div>

<div id="ref-Kaikkonen2021" class="csl-entry">

Kaikkonen, Laura, Tuuli Parviainen, Mika Rahikainen, Laura Uusitalo, and
Annukka Lehikoinen. 2021. “Bayesian Networks in Environmental Risk
Assessment: A Review.” *Integrated Environmental Assessment and
Management* 17 (1): 62–78. <https://doi.org/10.1002/ieam.4332>.

</div>

<div id="ref-Marcot2006" class="csl-entry">

Marcot, Bruce G., J. Douglas Steventon, Glenn D. Sutherland, and Robert
K. McCann. 2006. “Guidelines for Developing and Updating Bayesian Belief
Networks Applied to Ecological Modeling and Conservation.” *Canadian
Journal of Forest Research* 36 (12): 3063–74.
<https://doi.org/10.1139/x06-135>.

</div>

</div>
