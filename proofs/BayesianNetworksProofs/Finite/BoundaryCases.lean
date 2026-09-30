import BayesianNetworksProofs.Finite.OpenSemantics
import Mathlib.Data.Finset.Card

/-!
# BayesianNetworksProofs.Finite.BoundaryCases

**Boundary counterexamples and representation limits** (SPEC §13, §61 and §62.1).

The own-semantics formula `osem_compose_glue` sums over every glued variable, so it needs
disjoint inputs/outputs on both networks. On the binary identity wire, the open semantics is
one, while blindly summing its visible glued state gives two: `passthrough_formula_fails`
refutes that formula with its side conditions removed. `osem_compose_passthrough` is the
formula for arbitrary interfaces: it sums only the inner glued variables, and on the same
wire it gives one (`passthrough_formula_holds_on_wire`).

There is a separate structural limitation: with no mechanisms, the typed-interface rule
forces every variable to be an input. Since outputs are a subset of the apex, their number
cannot exceed the input count. Thus this representation cannot express a mechanism-free
one-input/two-output copying *foot* by listing an apex variable twice. General boundary maps,
including noninjective output legs, are not modelled. This is not a proof that no possible
category or semantic copy construction exists.
-/

set_option autoImplicit false

namespace BayesianNetworksProofs.OpenFinBayesNet

open FinBayesNet

/-- In a mechanism-free network every apex variable is necessarily an input. -/
theorem inputs_eq_univ_of_no_mechanisms (O : OpenFinBayesNet) [IsEmpty O.M] :
    O.inputs = Finset.univ := by
  apply Finset.eq_univ_of_forall
  intro v
  exact O.exogenous_input v fun m => isEmptyElim m

/-- Subset feet cannot represent mechanism-free copying by duplicated output ports. -/
theorem outputs_card_le_inputs_card_of_no_mechanisms (O : OpenFinBayesNet) [IsEmpty O.M] :
    O.outputs.card ≤ O.inputs.card := by
  rw [inputs_eq_univ_of_no_mechanisms]
  exact Finset.card_le_card (Finset.subset_univ _)

/-- The binary pass-through wire, with no mechanism. -/
def binaryWire : OpenFinBayesNet where
  V := Unit
  M := Empty
  states := fun _ => Bool
  target := Empty.elim
  parents := Empty.elim
  inputs := Finset.univ
  outputs := Finset.univ
  target_inj := by intro m; exact isEmptyElim m
  input_exogenous := by intro _ _ m; exact isEmptyElim m
  exogenous_input := by intro v _; exact Finset.mem_univ v
  topo := {
    order := [()]
    nodup := by simp
    complete := by intro v; cases v; simp
    parents_before := by simp
    no_self := by intro m; exact isEmptyElim m
  }

/-- Total matching of the binary wire with itself. -/
def binaryWireMatch : Composable binaryWire binaryWire where
  ι := id
  ι_inj := Function.injective_id
  states_equiv := fun _ => Equiv.refl _

/-- The unique empty mechanism family. -/
def binaryWireKernel : binaryWire.Kernel ℕ := fun m => nomatch m

/-- The retained external input of the composite is fixed to `false`. -/
def binaryWireAssignment : (Composable.compose binaryWireMatch).Assignment
  | .inl _ => false
  | .inr w => False.elim (w.property (Finset.mem_univ w.val))

/-- A checked counterexample to silently removing the no-pass-through side conditions. -/
theorem passthrough_formula_fails :
    osem (Composable.compose binaryWireMatch)
        (Composable.composeKernel binaryWireMatch binaryWireKernel binaryWireKernel)
        binaryWireAssignment = 1 ∧
      marg (binaryWireMatch.glued.map Function.Embedding.inl)
        (fun y => osem binaryWire binaryWireKernel (Composable.restrictA binaryWireMatch y) *
          osem binaryWire binaryWireKernel (Composable.restrictB binaryWireMatch y))
        binaryWireAssignment = 2 := by
  decide

/-- The pass-through formula `osem_compose_passthrough` on the same wire. The glued variable is
an input of `A` and passed straight to `B`'s outputs, so it stays on the composite's interface:
it is not inner, nothing is summed, and the formula gives the true value one. -/
theorem passthrough_formula_holds_on_wire :
    binaryWireMatch.innerGlued = ∅ ∧
      marg (binaryWireMatch.innerGlued.map Function.Embedding.inl)
        (fun y => osem binaryWire binaryWireKernel (Composable.restrictA binaryWireMatch y) *
          osem binaryWire binaryWireKernel (Composable.restrictB binaryWireMatch y))
        binaryWireAssignment = 1 := by
  decide

end BayesianNetworksProofs.OpenFinBayesNet
