/-
Axiom audit: `lake env lean Audit.lean` (or `make audit`). Every theorem below must report at
most `propext`, `Classical.choice` and `Quot.sound`. The completed Roadmap theorems now
live in the default library; the compatibility module itself is not needed here.
-/
import BayesianNetworksProofs
import Mathlib.Util.AssertNoSorry

assert_no_sorry BayesianNetworksProofs.Raw.Network.checked_reference_normalization
assert_no_sorry BayesianNetworksProofs.FinBayesNet.ve_normalized_posterior
assert_no_sorry BayesianNetworksProofs.Junction.calibrate_correct
assert_no_sorry BayesianNetworksProofs.Junction.queryPosterior_none_iff
assert_no_sorry BayesianNetworksProofs.FinBayesNet.d_separation_sound
assert_no_sorry BayesianNetworksProofs.Numerical.kernel_query_posterior_error
assert_no_sorry BayesianNetworksProofs.Binary64.nearestBinary64_roundsTo
assert_no_sorry BayesianNetworksProofs.ErrorBounds.ve_posterior_forward_error
assert_no_sorry BayesianNetworksProofs.Raw.decodeTables_eq_ok
assert_no_sorry BayesianNetworksProofs.Raw.decodeTables_encodeTables
assert_no_sorry BayesianNetworksProofs.Raw.decodeChecked_isSome_iff
assert_no_sorry BayesianNetworksProofs.Raw.decodeChecked_encode

-- Concrete data, references, repeated slots and exact conditioning.
#print axioms BayesianNetworksProofs.Raw.decodeId_none_iff
#print axioms BayesianNetworksProofs.Raw.decodeId_value
#print axioms BayesianNetworksProofs.Raw.positionEquiv
#print axioms BayesianNetworksProofs.Raw.Network.check_iff
#print axioms BayesianNetworksProofs.Raw.Network.topological
#print axioms BayesianNetworksProofs.Raw.Network.slot_position
#print axioms BayesianNetworksProofs.Raw.Network.state_position
#print axioms BayesianNetworksProofs.Raw.Network.slot_image
#print axioms BayesianNetworksProofs.Raw.Network.repeated_slots_diagonal
#print axioms BayesianNetworksProofs.Raw.Network.factor_compilation
#print axioms BayesianNetworksProofs.Raw.resolve_has_key
#print axioms BayesianNetworksProofs.Raw.Network.AxisMatch.input
#print axioms BayesianNetworksProofs.Raw.Network.AxisMatch.output
#print axioms BayesianNetworksProofs.Raw.Network.rawReady_sound
#print axioms BayesianNetworksProofs.Raw.Network.checked_reference_normalization
#print axioms BayesianNetworksProofs.Raw.Network.realKernel_local
#print axioms BayesianNetworksProofs.Raw.Network.realKernel_nonnegative
#print axioms BayesianNetworksProofs.Raw.Network.realKernel_normalized

-- The ACSets JSON decoder (Finite/JsonRecords.lean).
#print axioms BayesianNetworksProofs.Raw.decodeId_eq_some
#print axioms BayesianNetworksProofs.Raw.decodeRef_eq_ok
#print axioms BayesianNetworksProofs.Raw.decodeFn_eq_ok
#print axioms BayesianNetworksProofs.Raw.decodeTable_eq_ok
#print axioms BayesianNetworksProofs.Raw.decodeBody_eq_ok
#print axioms BayesianNetworksProofs.Raw.decodeTables_eq_ok
#print axioms BayesianNetworksProofs.Raw.decodeTables_encodeTables
#print axioms BayesianNetworksProofs.Raw.BodyMatches.shape
#print axioms BayesianNetworksProofs.Raw.decodeTables_error_of_envelope
#print axioms BayesianNetworksProofs.Raw.decodeBody_error_of_missing_table
#print axioms BayesianNetworksProofs.Raw.decodeBody_error_of_bad_table
#print axioms BayesianNetworksProofs.Raw.decodeBody_error_of_size
#print axioms BayesianNetworksProofs.Raw.decodeBody_error_of_bad_row
#print axioms BayesianNetworksProofs.Raw.decodeBody_error_of_bad_column
#print axioms BayesianNetworksProofs.Raw.decodeBody_error_of_missing_column
#print axioms BayesianNetworksProofs.Raw.decodeBody_error_of_hom_out_of_range
#print axioms BayesianNetworksProofs.Raw.decodeBody_error_of_not_integer
#print axioms BayesianNetworksProofs.Raw.decodeBody_error_of_not_string
#print axioms BayesianNetworksProofs.Raw.Tables.computeRank_sound
#print axioms BayesianNetworksProofs.Raw.Tables.computeRank_complete
#print axioms BayesianNetworksProofs.Raw.Tables.valid_iff_exists
#print axioms BayesianNetworksProofs.Raw.Network.valid_iff_tables
#print axioms BayesianNetworksProofs.Raw.Network.compile_eq_of_tables_eq
#print axioms BayesianNetworksProofs.Raw.decode_eq_ok
#print axioms BayesianNetworksProofs.Raw.decode_encode_of_rank
#print axioms BayesianNetworksProofs.Raw.decode_encode
#print axioms BayesianNetworksProofs.Raw.decodeChecked_sound
#print axioms BayesianNetworksProofs.Raw.decodeChecked_isSome_iff
#print axioms BayesianNetworksProofs.Raw.decodeChecked_encode
#print axioms BayesianNetworksProofs.Raw.Network.labelAt_eq
#print axioms BayesianNetworksProofs.Raw.Network.slotAt_eq
#print axioms BayesianNetworksProofs.Raw.decodeChecked_stateLabel
#print axioms BayesianNetworksProofs.Raw.decodeChecked_slotVariable
#print axioms BayesianNetworksProofs.Raw.decodeChecked_compile
#print axioms BayesianNetworksProofs.FinBayesNet.sum_partial_eq_marg
#print axioms BayesianNetworksProofs.FinBayesNet.marg_indicator_eq_clamp
#print axioms BayesianNetworksProofs.FinBayesNet.sum_conditioned_eq_indicator
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.explicit_conditioning_elimination

-- Genuine posterior distributions and global zero-feasibility.
#print axioms BayesianNetworksProofs.FiniteDistribution.normalize
#print axioms BayesianNetworksProofs.FiniteDistribution.normalize_none_iff
#print axioms BayesianNetworksProofs.FiniteDistribution.normalize_value
#print axioms BayesianNetworksProofs.FinBayesNet.posterior_none_iff
#print axioms BayesianNetworksProofs.FinBayesNet.ve_posterior_numerator
#print axioms BayesianNetworksProofs.FinBayesNet.ve_normalized_posterior

-- Actual collect/distribute messages, arbitrary branching and disconnected components.
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.project_private
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.project_multiply
#print axioms BayesianNetworksProofs.Junction.prepare_up
#print axioms BayesianNetworksProofs.Junction.checkGood_iff
#print axioms BayesianNetworksProofs.Junction.checkAssignment_sound
#print axioms BayesianNetworksProofs.Junction.prepare_up_separator
#print axioms BayesianNetworksProofs.Junction.outgoing
#print axioms BayesianNetworksProofs.Junction.distribute_correct
#print axioms BayesianNetworksProofs.Junction.calibrate_correct
#print axioms BayesianNetworksProofs.Junction.graft_good
#print axioms BayesianNetworksProofs.Junction.graft_indices
#print axioms BayesianNetworksProofs.Junction.forest_good
#print axioms BayesianNetworksProofs.Junction.calibrate_eq_ve
#print axioms BayesianNetworksProofs.Junction.belief_mass
#print axioms BayesianNetworksProofs.Junction.queryWeight_correct
#print axioms BayesianNetworksProofs.Junction.queryPosterior_none_iff
#print axioms BayesianNetworksProofs.Junction.queryPosterior_value

-- Actual graph separation, independent of the numerical definition of CI.
#print axioms BayesianNetworksProofs.FinBayesNet.ancestors_upstream
#print axioms BayesianNetworksProofs.FinBayesNet.family_left
#print axioms BayesianNetworksProofs.FinBayesNet.family_right
#print axioms BayesianNetworksProofs.FinBayesNet.d_separation_sound
#print axioms BayesianNetworksProofs.FinBayesNet.d_separation_sound_probability
#print axioms BayesianNetworksProofs.FinBayesNet.ConditionalIndependent.conditional

-- Explicit numerical error and local rounding contracts.
#print axioms BayesianNetworksProofs.Numerical.normalization_l1
#print axioms BayesianNetworksProofs.Numerical.posterior_error
#print axioms BayesianNetworksProofs.Numerical.product_error
#print axioms BayesianNetworksProofs.Numerical.roundedProduct_error
#print axioms BayesianNetworksProofs.Numerical.joint_l1_error
#print axioms BayesianNetworksProofs.Numerical.kernel_query_posterior_error

-- Correct rounding to binary64: `_rational_exponent`, `_nearest_binary64` and `_dyadic` (ADR 0016).
#print axioms BayesianNetworksProofs.Binary64.rationalExponent_spec
#print axioms BayesianNetworksProofs.Binary64.rationalExponent_eq_log
#print axioms BayesianNetworksProofs.Binary64.roundHalfEven_spec
#print axioms BayesianNetworksProofs.Binary64.nearestBinary64_eq
#print axioms BayesianNetworksProofs.Binary64.packWord_spec
#print axioms BayesianNetworksProofs.Binary64.grid_nearest
#print axioms BayesianNetworksProofs.Binary64.magnitudeWord_spec
#print axioms BayesianNetworksProofs.Binary64.signed_word
#print axioms BayesianNetworksProofs.Binary64.nearestBinary64_roundsTo
#print axioms BayesianNetworksProofs.Binary64.dyadic_none_iff
#print axioms BayesianNetworksProofs.Binary64.dyadic_value
#print axioms BayesianNetworksProofs.Binary64.magnitude_injective
#print axioms BayesianNetworksProofs.Binary64.magnitude_lt_threshold
#print axioms BayesianNetworksProofs.Binary64.nearestBinary64_value

-- Forward error bounds under the standard rounding model, and the bridge to binary64.
#print axioms BayesianNetworksProofs.ErrorBounds.rounded_iff
#print axioms BayesianNetworksProofs.ErrorBounds.RelWithin.mul
#print axioms BayesianNetworksProofs.ErrorBounds.RelWithin.add
#print axioms BayesianNetworksProofs.ErrorBounds.RelWithin.round
#print axioms BayesianNetworksProofs.ErrorBounds.RelWithin.div
#print axioms BayesianNetworksProofs.ErrorBounds.roundsTo_relative
#print axioms BayesianNetworksProofs.ErrorBounds.roundsTo_subnormal
#print axioms BayesianNetworksProofs.ErrorBounds.roundsTo_error
#print axioms BayesianNetworksProofs.ErrorBounds.roundsTo_rounded
#print axioms BayesianNetworksProofs.ErrorBounds.nearestBinary64_relative
#print axioms BayesianNetworksProofs.ErrorBounds.nearestBinary64_subnormal
#print axioms BayesianNetworksProofs.ErrorBounds.nearestBinary64_rounded
#print axioms BayesianNetworksProofs.ErrorBounds.SumRun.within
#print axioms BayesianNetworksProofs.ErrorBounds.ProdRun.within
#print axioms BayesianNetworksProofs.ErrorBounds.compProd_forward_error
#print axioms BayesianNetworksProofs.ErrorBounds.sumRun_forward_error
#print axioms BayesianNetworksProofs.ErrorBounds.Run.fst
#print axioms BayesianNetworksProofs.ErrorBounds.Run.good
#print axioms BayesianNetworksProofs.ErrorBounds.eliminateAll_forward_error
#print axioms BayesianNetworksProofs.ErrorBounds.eliminateAll_marg_forward_error
#print axioms BayesianNetworksProofs.ErrorBounds.conditioned_forward_error
#print axioms BayesianNetworksProofs.ErrorBounds.normalize_forward_error
#print axioms BayesianNetworksProofs.ErrorBounds.ve_posterior_forward_error
#print axioms BayesianNetworksProofs.ErrorBounds.logSumExp_forward_error

-- Kernel-checked nonvacuity fixtures, including rational certificate checks.
#print axioms BayesianNetworksProofs.RefinementExamples.raw_structure_checked
#print axioms BayesianNetworksProofs.RefinementExamples.raw_references_checked
#print axioms BayesianNetworksProofs.RefinementExamples.raw_normalization_checked
#print axioms BayesianNetworksProofs.RefinementExamples.raw_diagonal
#print axioms BayesianNetworksProofs.RefinementExamples.raw_compiled_probability
#print axioms BayesianNetworksProofs.RefinementExamples.bad_positions_rejected
#print axioms BayesianNetworksProofs.RefinementExamples.bad_labels_rejected
#print axioms BayesianNetworksProofs.RefinementExamples.unnormalized_data_interpretable
#print axioms BayesianNetworksProofs.RefinementExamples.unnormalized_probability_rejected
#print axioms BayesianNetworksProofs.RefinementExamples.unresolved_reference_rejected
#print axioms BayesianNetworksProofs.RefinementExamples.fork_graph_separated
#print axioms BayesianNetworksProofs.RefinementExamples.fork_conditional_independence
#print axioms BayesianNetworksProofs.RefinementExamples.connected_tree_valid
#print axioms BayesianNetworksProofs.RefinementExamples.connected_tree_check
#print axioms BayesianNetworksProofs.RefinementExamples.connected_assignment_check
#print axioms BayesianNetworksProofs.RefinementExamples.nonempty_separator_belief_exists
#print axioms BayesianNetworksProofs.RefinementExamples.connected_beliefs_match_ve
#print axioms BayesianNetworksProofs.RefinementExamples.forest_valid
#print axioms BayesianNetworksProofs.RefinementExamples.forest_assignment
#print axioms BayesianNetworksProofs.RefinementExamples.forest_zero_mass
#print axioms BayesianNetworksProofs.RefinementExamples.disconnected_query_rejects

-- Direct coverage of the supporting public lemmas, in addition to transitive headline audits.
#print axioms BayesianNetworksProofs.FinBayesNet.restrict_patch
#print axioms BayesianNetworksProofs.FinBayesNet.patch_mem_fibre
#print axioms BayesianNetworksProofs.FinBayesNet.patch_restrict_of_mem
#print axioms BayesianNetworksProofs.FinBayesNet.clamp_agrees
#print axioms BayesianNetworksProofs.FinBayesNet.clamp_patch
#print axioms BayesianNetworksProofs.FinBayesNet.marg_clamp
#print axioms BayesianNetworksProofs.FinBayesNet.fibre_condition
#print axioms BayesianNetworksProofs.FiniteDistribution.mass_nonneg
#print axioms BayesianNetworksProofs.FiniteDistribution.mass_zero_iff
#print axioms BayesianNetworksProofs.FiniteDistribution.mass_pos_iff
#print axioms BayesianNetworksProofs.FiniteDistribution.pushWeight_nonneg
#print axioms BayesianNetworksProofs.FiniteDistribution.mass_pushWeight
#print axioms BayesianNetworksProofs.FinBayesNet.likelihoodWeight_nonneg
#print axioms BayesianNetworksProofs.FinBayesNet.fibre_query
#print axioms BayesianNetworksProofs.FinBayesNet.marginal_eq_query_weight
#print axioms BayesianNetworksProofs.FinBayesNet.joint_nonneg
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.product_condition
#print axioms BayesianNetworksProofs.Raw.Network.valid_iff
#print axioms BayesianNetworksProofs.Raw.Network.stateLabel_injective
#print axioms BayesianNetworksProofs.Raw.Network.compile_closed
#print axioms BayesianNetworksProofs.Raw.Network.kernel_local
#print axioms BayesianNetworksProofs.Raw.Network.kernel_normalised
#print axioms BayesianNetworksProofs.Raw.Network.compiled_joint_normalised
#print axioms BayesianNetworksProofs.Raw.coordinates_ofFn
#print axioms BayesianNetworksProofs.Raw.find_mem
#print axioms BayesianNetworksProofs.Raw.find_exists
#print axioms BayesianNetworksProofs.Raw.column_exists
#print axioms BayesianNetworksProofs.Raw.getD_nonnegative
#print axioms BayesianNetworksProofs.Raw.sum_getD
#print axioms BayesianNetworksProofs.Raw.Table.read_nonnegative
#print axioms BayesianNetworksProofs.Raw.Table.read_normalized
#print axioms BayesianNetworksProofs.Raw.Network.slotIndices_valid
#print axioms BayesianNetworksProofs.Raw.Network.resolvedCPT_nonnegative
#print axioms BayesianNetworksProofs.Raw.Network.resolvedCPT_normalized
#print axioms BayesianNetworksProofs.Raw.Network.resolved_joint_normalized
#print axioms BayesianNetworksProofs.Raw.Network.rawSlotSize_eq
#print axioms BayesianNetworksProofs.Raw.Network.rawSlotSizes_eq
#print axioms BayesianNetworksProofs.Raw.Network.rawNormalized_sound
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.ext
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.multiply_comm
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.multiply_assoc
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.unit_multiply
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.multiply_unit
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.multiply_left_comm
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.combine_value
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.combine_scope
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.project_value
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.project_of_scope
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.project_nonnegative
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.private_factor_constant
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.marginal_value
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.marg_product_disjoint
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.project_project
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.project_inter
#print axioms BayesianNetworksProofs.Junction.bag_subset_vars
#print axioms BayesianNetworksProofs.Junction.full_scope
#print axioms BayesianNetworksProofs.Junction.full_value
#print axioms BayesianNetworksProofs.Junction.prepare_bag
#print axioms BayesianNetworksProofs.Junction.project_three
#print axioms BayesianNetworksProofs.Junction.frame_scope
#print axioms BayesianNetworksProofs.Junction.graft_bag
#print axioms BayesianNetworksProofs.Junction.graft_vars
#print axioms BayesianNetworksProofs.Junction.mem_forestVars
#print axioms BayesianNetworksProofs.Junction.mem_local_scope
#print axioms BayesianNetworksProofs.Junction.mem_full_scope
#print axioms BayesianNetworksProofs.Junction.full_scope_univ
#print axioms BayesianNetworksProofs.Junction.full_product_of_perm
#print axioms BayesianNetworksProofs.Junction.factor_product_nonnegative
#print axioms BayesianNetworksProofs.FinBayesNet.indicator_empty
#print axioms BayesianNetworksProofs.FinBayesNet.separator_event_mass
#print axioms BayesianNetworksProofs.FinBayesNet.separator_cross_product
#print axioms BayesianNetworksProofs.FinBayesNet.eventMass_of_marginal
#print axioms BayesianNetworksProofs.FinBayesNet.subset_ancestors
#print axioms BayesianNetworksProofs.FinBayesNet.left_mem
#print axioms BayesianNetworksProofs.FinBayesNet.left_subset
#print axioms BayesianNetworksProofs.FinBayesNet.left_avoids
#print axioms BayesianNetworksProofs.FinBayesNet.family_subset
#print axioms BayesianNetworksProofs.FinBayesNet.left_closed_edge
#print axioms BayesianNetworksProofs.FinBayesNet.queries_in_sides
#print axioms BayesianNetworksProofs.Numerical.l1_nonneg
#print axioms BayesianNetworksProofs.Numerical.mass_error
#print axioms BayesianNetworksProofs.Numerical.point_normalization_error
#print axioms BayesianNetworksProofs.Numerical.prod_unit_interval
#print axioms BayesianNetworksProofs.Numerical.roundedProduct_range
#print axioms BayesianNetworksProofs.Numerical.push_l1
#print axioms BayesianNetworksProofs.Numerical.evidence_l1
#print axioms BayesianNetworksProofs.RefinementExamples.raw_two_slots
#print axioms BayesianNetworksProofs.RefinementExamples.fork_closed
#print axioms BayesianNetworksProofs.RefinementExamples.fork_local
#print axioms BayesianNetworksProofs.RefinementExamples.fork_normalized
#print axioms BayesianNetworksProofs.RefinementExamples.fork_nonnegative
#print axioms BayesianNetworksProofs.RefinementExamples.fork_cut_edgeless
#print axioms BayesianNetworksProofs.RefinementExamples.connected_assignment
#print axioms BayesianNetworksProofs.RefinementExamples.connected_variables
#print axioms BayesianNetworksProofs.RefinementExamples.root_local
#print axioms BayesianNetworksProofs.RefinementExamples.forest_variables
#print axioms BayesianNetworksProofs.RefinementExamples.forest_nonnegative
#print axioms BayesianNetworksProofs.RefinementExamples.product_zero_of_mem

-- Own-variable open semantics, including partial matching without stochastic premises.
#print axioms BayesianNetworksProofs.OpenFinBayesNet.Composable.marg_restrictA
#print axioms BayesianNetworksProofs.OpenFinBayesNet.Composable.marg_restrictB
#print axioms BayesianNetworksProofs.OpenFinBayesNet.Composable.hidden_compose
#print axioms BayesianNetworksProofs.OpenFinBayesNet.Composable.osem_compose_passthrough
#print axioms BayesianNetworksProofs.OpenFinBayesNet.Composable.hidden_compose_general
#print axioms BayesianNetworksProofs.OpenFinBayesNet.Composable.innerGlued_eq_filter_hidden
#print axioms BayesianNetworksProofs.OpenFinBayesNet.passthrough_formula_holds_on_wire
#print axioms BayesianNetworksProofs.OpenFinBayesNet.Composable.osem_compose_glue
#print axioms BayesianNetworksProofs.OpenFinBayesNet.Composable.osem_compose
#print axioms BayesianNetworksProofs.OpenFinBayesNet.inputs_eq_univ_of_no_mechanisms
#print axioms BayesianNetworksProofs.OpenFinBayesNet.outputs_card_le_inputs_card_of_no_mechanisms
#print axioms BayesianNetworksProofs.OpenFinBayesNet.passthrough_formula_fails

-- Ordered-parent refinement and semiring bucket-elimination oracle.
#print axioms BayesianNetworksProofs.FinBayesNet.ParentOrder.toKernel_local
#print axioms BayesianNetworksProofs.FinBayesNet.ParentOrder.toKernel_ofKernel
#print axioms BayesianNetworksProofs.FinBayesNet.ParentOrder.ofKernel_toKernel
#print axioms BayesianNetworksProofs.FinBayesNet.ParentOrder.local_iff_ordered
#print axioms BayesianNetworksProofs.FinBayesNet.ParentOrder.toKernel_reindex
#print axioms BayesianNetworksProofs.FinBayesNet.ParentOrder.toKernel_normalised
#print axioms BayesianNetworksProofs.FinBayesNet.ParentOrder.sum_joint_ordered
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.product_partition
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.eliminate_correct
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.eliminateAll_correct
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.eliminateAll_order_independent
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.product_ofKernel
#print axioms BayesianNetworksProofs.FinBayesNet.Factor.eliminateAll_joint

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
