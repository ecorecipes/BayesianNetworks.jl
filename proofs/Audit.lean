/-
Axiom audit: `lake env lean Audit.lean` (or `make audit`). Every theorem below must report at
most `propext`, `Classical.choice` and `Quot.sound`. `BayesianNetworksProofs.Roadmap` (which
contains `sorry`) is intentionally not imported here.
-/
import BayesianNetworksProofs

open BayesianNetworksProofs BayesianNetworksProofs.FinBayesNet

-- Schema layer
#print axioms schVariableSpace_wf
#print axioms schBayesNet_wf
#print axioms schInfluenceDiagram_wf
#print axioms sub_variableSpace_bayesNet
#print axioms noOutgoing_variableSpace_bayesNet
#print axioms sub_bayesNet_influenceDiagram
#print axioms noOutgoing_variableSpace_influenceDiagram
#print axioms SchemaDesc.sub_extend

-- Proposition 1
#print axioms marg_partialJoint_eq_one
#print axioms sum_joint_eq_one
#print axioms evalSeq_eq_joint
#print axioms evalSeq_topo_eq_joint
#print axioms sum_joint_eq_one_nnreal

-- Proposition 4
#print axioms joint_intervene
#print axioms normalised_intervene
#print axioms local_cut
#print axioms sum_joint_intervene_eq_one
#print axioms joint_intervene_nnreal

-- Proposition 2
#print axioms joint_tensor
#print axioms closed_tensor
#print axioms normalised_tensor
#print axioms local_tensor
#print axioms TopoOrder.tensor

-- Open networks: the closure theorem (SPEC §13 revision note)
#print axioms OpenFinBayesNet.Composable.composeNet_target_injective
#print axioms OpenFinBayesNet.Composable.compose_input_exogenous
#print axioms OpenFinBayesNet.Composable.compose_exogenous_input
#print axioms OpenFinBayesNet.Composable.composeTopo
#print axioms OpenFinBayesNet.Composable.compose
#print axioms OpenFinBayesNet.Composable.closed_compose

-- Proposition 3
#print axioms marg_joint_downstream
#print axioms marg_joint_upstream
#print axioms marg_union_disjoint
#print axioms OpenFinBayesNet.Composable.joint_compose
#print axioms OpenFinBayesNet.Composable.local_compose
#print axioms OpenFinBayesNet.Composable.normalised_compose
#print axioms OpenFinBayesNet.Composable.marg_joint_compose
#print axioms OpenFinBayesNet.Composable.marg_joint_compose_split
#print axioms OpenFinBayesNet.Composable.sum_joint_compose_eq_one

-- Markov-category lemmas
#print axioms Markov.discard_natural
#print axioms Markov.state_discard
#print axioms Markov.deterministic_comp
#print axioms Markov.deterministic_copy
