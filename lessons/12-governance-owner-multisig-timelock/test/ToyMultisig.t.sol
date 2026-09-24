// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode e helper usati in questo file:
//   makeAddr("nome")    indirizzo deterministico ed etichettato nelle trace;
//   vm.prank(a)         la PROSSIMA call avra' msg.sender = a;
//   vm.expectRevert(e)  la PROSSIMA call deve revertire con l'errore e.
// Configurazione: 2-of-3 con alice, bob, carol. stranger non e' owner.
import { Test } from "forge-std/Test.sol";
import { ToyMultisig } from "../src/governance/ToyMultisig.sol";
import { CallTarget } from "../src/mocks/GovernanceTargets.sol";

contract ToyMultisigTest is Test {
    ToyMultisig internal multisig;
    CallTarget internal target;

    address internal alice;
    address internal bob;
    address internal carol;
    address internal stranger;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        stranger = makeAddr("stranger");

        // `new address[](3)`: array in memory di lunghezza fissa 3, poi riempito.
        address[] memory signers = new address[](3);
        signers[0] = alice;
        signers[1] = bob;
        signers[2] = carol;
        multisig = new ToyMultisig(signers, 2);
        target = new CallTarget();
    }

    // Test di sola lettura (`view`): verifica che il deploy abbia la configurazione attesa.
    function test_ConfigurationIsTwoOfThree() public view {
        address[] memory signers = multisig.owners();
        assertEq(signers.length, 3);
        assertEq(multisig.threshold(), 2);
        assertTrue(multisig.isOwner(alice));
        assertTrue(multisig.isOwner(bob));
        assertTrue(multisig.isOwner(carol));
    }

    function test_TwoApprovalsExecuteTransaction() public {
        // ARRANGE: proposta + due approvazioni.
        uint256 id = _submitSetValue(42);
        _approve(id, alice);
        _approve(id, bob);

        // ACT: esegue carol, che non ha approvato: basta essere owner.
        vm.prank(carol);
        bytes memory result = multisig.execute(id);

        // ASSERT: effetto sul target, return value inoltrato, stato della tx.
        assertEq(target.value(), 42);
        assertEq(abi.decode(result, (uint256)), 42);
        // Destructuring: le virgole saltano i valori restituiti che non servono.
        (,,, uint256 approvals, bool executed) = multisig.transaction(id);
        assertEq(approvals, 2);
        assertTrue(executed);
    }

    // CONFINE: 1 approvazione su 2 non basta (con 2 il test precedente passa).
    function test_RevertWhen_ThresholdIsNotReached() public {
        uint256 id = _submitSetValue(42);
        _approve(id, alice);

        vm.expectRevert(abi.encodeWithSelector(ToyMultisig.ThresholdNotReached.selector, 1, 2));
        vm.prank(bob);
        multisig.execute(id);

        assertEq(target.value(), 0);
    }

    // Lo stesso signer conta una volta: altrimenti alice da sola raggiungerebbe 2.
    function test_RevertWhen_OwnerApprovesTwice() public {
        uint256 id = _submitSetValue(42);
        _approve(id, alice);

        vm.expectRevert(abi.encodeWithSelector(ToyMultisig.AlreadyApproved.selector, id, alice));
        vm.prank(alice);
        multisig.approve(id);
    }

    // Un test, tre porte: submit, approve ed execute devono respingere un non-owner.
    function test_RevertWhen_NonOwnerSubmitsApprovesOrExecutes() public {
        bytes memory data = abi.encodeCall(target.setValue, (42));

        vm.expectRevert(abi.encodeWithSelector(ToyMultisig.NotOwner.selector, stranger));
        vm.prank(stranger);
        multisig.submit(address(target), 0, data);

        // Si usa una tx che esiste davvero: cosi' l'unico motivo possibile del revert e' il
        // chiamante, qualunque sia l'ordine dei controlli nel contratto.
        uint256 id = _submitSetValue(42);
        vm.expectRevert(abi.encodeWithSelector(ToyMultisig.NotOwner.selector, stranger));
        vm.prank(stranger);
        multisig.approve(id);

        vm.expectRevert(abi.encodeWithSelector(ToyMultisig.NotOwner.selector, stranger));
        vm.prank(stranger);
        multisig.execute(id);
    }

    function test_RevertWhen_ExecutingTwice() public {
        uint256 id = _submitSetValue(42);
        _approve(id, alice);
        _approve(id, bob);
        vm.prank(alice);
        multisig.execute(id);

        vm.expectRevert(abi.encodeWithSelector(ToyMultisig.AlreadyExecuted.selector, id));
        vm.prank(bob);
        multisig.execute(id);
    }

    // ATOMICITA': execute scrive executed = true prima della call, ma il revert del target
    // annulla anche quella scrittura. La tx resta non eseguita.
    function test_FailedTargetCallLeavesTransactionExecutable() public {
        vm.prank(alice);
        uint256 id = multisig.submit(address(target), 0, abi.encodeCall(target.fail, ()));
        _approve(id, alice);
        _approve(id, bob);

        // L'errore del target arriva incapsulato dentro CallFailed(reason).
        bytes memory reason = abi.encodeWithSelector(CallTarget.ForcedFailure.selector);
        vm.expectRevert(abi.encodeWithSelector(ToyMultisig.CallFailed.selector, reason));
        vm.prank(carol);
        multisig.execute(id);

        (,,,, bool executed) = multisig.transaction(id);
        assertFalse(executed);
    }

    function test_RevertForUnknownTransaction() public {
        vm.expectRevert(abi.encodeWithSelector(ToyMultisig.UnknownTransaction.selector, 99));
        vm.prank(alice);
        multisig.approve(99);
    }

    function test_RevertWhen_TargetHasNoCode() public {
        vm.expectRevert(abi.encodeWithSelector(ToyMultisig.InvalidTarget.selector, stranger));
        vm.prank(alice);
        multisig.submit(stranger, 0, bytes(""));
    }

    // Tre configurazioni invalide al deploy: threshold 0, threshold > owner, owner duplicato.
    function test_RevertForInvalidConstructorConfiguration() public {
        address[] memory oneSigner = new address[](1);
        oneSigner[0] = alice;

        vm.expectRevert(abi.encodeWithSelector(ToyMultisig.InvalidThreshold.selector, 0, 1));
        new ToyMultisig(oneSigner, 0);

        vm.expectRevert(abi.encodeWithSelector(ToyMultisig.InvalidThreshold.selector, 2, 1));
        new ToyMultisig(oneSigner, 2);

        address[] memory duplicates = new address[](2);
        duplicates[0] = alice;
        duplicates[1] = alice;
        vm.expectRevert(abi.encodeWithSelector(ToyMultisig.DuplicateOwner.selector, alice));
        new ToyMultisig(duplicates, 2);
    }

    // Helper: alice propone target.setValue(newValue) senza ETH.
    function _submitSetValue(uint256 newValue) internal returns (uint256 id) {
        vm.prank(alice);
        id = multisig.submit(address(target), 0, abi.encodeCall(target.setValue, (newValue)));
    }

    function _approve(uint256 id, address signer) internal {
        vm.prank(signer);
        multisig.approve(id);
    }
}
