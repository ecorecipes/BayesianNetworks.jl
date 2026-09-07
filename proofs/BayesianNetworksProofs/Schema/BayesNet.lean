import BayesianNetworksProofs.Schema.Desc

/-!
# BayesianNetworksProofs.Schema.BayesNet

The three ACSet schemas of the ecosystem, as `SchemaDesc` terms:

* `schVariableSpace` — the interface sub-schema (variables and their states);
* `schBayesNet` — adds mechanisms and their ordered inputs (SPEC §8);
* `schInfluenceDiagram` — adds decisions, information arcs, utilities and decision precedence
  (SPEC §24).

The theorems (all by `decide`) are what the Julia layer assumes: each schema is well formed,
each extension contains its base, and `schVariableSpace` has *no outgoing arrows* in
`schBayesNet` / `schInfluenceDiagram`, which is the precondition of Catlab's multi-object
`OpenACSetTypes(BayesNet, VariableSpace)`.
-/

namespace BayesianNetworksProofs

open SchemaDesc

/-- `SchVariableSpace`: objects `Variable`, `State`; hom `state_variable`; attribute types
`Label`, `Position`, `Ref`; attributes naming variables and states, positioning states and
referencing the semantic state space. -/
def schVariableSpace : SchemaDesc where
  obs := ["Variable", "State"]
  homs := [⟨"state_variable", "State", "Variable"⟩]
  attrtypes := ["Label", "Position", "Ref"]
  attrs :=
    [ ⟨"variable_name", "Variable", "Label"⟩
    , ⟨"space_ref", "Variable", "Ref"⟩
    , ⟨"state_name", "State", "Label"⟩
    , ⟨"state_position", "State", "Position"⟩ ]

/-- `SchBayesNet <: SchVariableSpace`: mechanisms with a `target` variable and ordered inputs. -/
def schBayesNet : SchemaDesc :=
  schVariableSpace.extend
    (obs := ["Mechanism", "Input"])
    (homs :=
      [ ⟨"target", "Mechanism", "Variable"⟩
      , ⟨"input_mechanism", "Input", "Mechanism"⟩
      , ⟨"input_variable", "Input", "Variable"⟩ ])
    (attrs :=
      [ ⟨"mechanism_name", "Mechanism", "Label"⟩
      , ⟨"kernel_ref", "Mechanism", "Ref"⟩
      , ⟨"input_position", "Input", "Position"⟩ ])

/-- `SchInfluenceDiagram <: SchBayesNet`: decisions, information inputs, utilities with their
inputs, and decision precedence. -/
def schInfluenceDiagram : SchemaDesc :=
  schBayesNet.extend
    (obs := ["Decision", "InformationInput", "Utility", "UtilityInput", "DecisionPrecedence"])
    (homs :=
      [ ⟨"decision_variable", "Decision", "Variable"⟩
      , ⟨"information_decision", "InformationInput", "Decision"⟩
      , ⟨"information_variable", "InformationInput", "Variable"⟩
      , ⟨"utility_node", "UtilityInput", "Utility"⟩
      , ⟨"utility_variable", "UtilityInput", "Variable"⟩
      , ⟨"earlier", "DecisionPrecedence", "Decision"⟩
      , ⟨"later", "DecisionPrecedence", "Decision"⟩ ])
    (attrs :=
      [ ⟨"decision_name", "Decision", "Label"⟩
      , ⟨"utility_name", "Utility", "Label"⟩
      , ⟨"utility_ref", "Utility", "Ref"⟩
      , ⟨"information_position", "InformationInput", "Position"⟩
      , ⟨"utility_position", "UtilityInput", "Position"⟩ ])

/-! ## Theorems -/

theorem schVariableSpace_wf : schVariableSpace.WF := by decide

theorem schBayesNet_wf : schBayesNet.WF := by decide

theorem schInfluenceDiagram_wf : schInfluenceDiagram.WF := by decide

theorem sub_variableSpace_bayesNet : Sub schVariableSpace schBayesNet := by decide

/-- No hom or attribute of `SchBayesNet` leaves `{Variable, State}`: `VariableSpace` is a valid
interface type for `OpenACSetTypes(BayesNet, VariableSpace)`. -/
theorem noOutgoing_variableSpace_bayesNet : NoOutgoing schVariableSpace schBayesNet := by decide

theorem sub_bayesNet_influenceDiagram : Sub schBayesNet schInfluenceDiagram := by decide

theorem noOutgoing_variableSpace_influenceDiagram :
    NoOutgoing schVariableSpace schInfluenceDiagram := by decide

end BayesianNetworksProofs
