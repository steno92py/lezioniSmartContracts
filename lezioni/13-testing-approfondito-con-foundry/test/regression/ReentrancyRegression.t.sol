// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Regression test: ognuno fissa un bug plausibile che non deve tornare, anche dopo refactoring.
// Cheatcode usati: vm.deal(a, x) assegna x wei ad a; makeAddr, vm.prank, vm.expectRevert.
// Per seguire la catena di call del rientro:
//   forge test --match-test test_Regression_ReentrantCallbackCannotWithdrawTwice -vvvv
import {Test} from "forge-std/Test.sol";
import {WithdrawalVault} from "../../src/WithdrawalVault.sol";
import {ReentrantReceiver, RejectEther} from "../../src/mocks/TestingMocks.sol";

contract ReentrancyRegressionTest is Test {
    WithdrawalVault internal vault;

    function setUp() public {
        vault = new WithdrawalVault();
        vm.deal(address(this), 10 ether); // il contratto di test paga i depositi
    }

    function test_Regression_ReentrantCallbackCannotWithdrawTwice() public {
        // ARRANGE: l'attaccante ha 1 ether di credito. L'utente onesto aggiunge 2 ether:
        // senza altri fondi nel vault un secondo prelievo fallirebbe comunque per mancanza
        // di ETH, e il test non dimostrerebbe nulla sulla protezione.
        ReentrantReceiver receiver = new ReentrantReceiver(vault);
        address honestUser = makeAddr("honest-user");
        vault.depositFor{value: 1 ether}(address(receiver));
        vault.depositFor{value: 2 ether}(honestUser);

        // ACT
        receiver.attack();

        // ASSERT: il rientro e' stato TENTATO (altrimenti il test non proverebbe niente)...
        assertTrue(receiver.callbackAttempted());
        // ...ma NON e' riuscito.
        assertFalse(receiver.secondWithdrawalSucceeded());
        // L'attaccante ha ricevuto solo il suo credito; quello dell'utente onesto e' intatto.
        assertEq(address(receiver).balance, 1 ether);
        assertEq(vault.credit(address(receiver)), 0);
        assertEq(vault.credit(honestUser), 2 ether);
        assertEq(vault.totalLiabilities(), 2 ether);
        assertEq(address(vault).balance, 2 ether);
    }

    // Un destinatario che rifiuta gli ETH non deve perdere il credito: il revert annulla
    // l'azzeramento fatto prima della call.
    function test_Regression_RevertingRecipientRollsBackCredit() public {
        RejectEther rejector = new RejectEther();
        vault.depositFor{value: 1 ether}(address(rejector));

        // Il revert nasce nel vault e risale attraverso rejector.claim fino al test.
        vm.expectRevert(WithdrawalVault.EtherTransferFailed.selector);
        rejector.claim(vault);

        assertEq(vault.credit(address(rejector)), 1 ether);
        assertEq(vault.totalLiabilities(), 1 ether);
        assertEq(address(vault).balance, 1 ether);
    }

    function test_WithdrawWithoutCreditUsesExactErrorPayload() public {
        address stranger = makeAddr("stranger");
        vm.expectRevert(abi.encodeWithSelector(WithdrawalVault.NoCredit.selector, stranger));
        vm.prank(stranger);
        vault.withdraw();
    }

    function test_DepositRejectsZeroBeneficiary() public {
        uint256 balanceBefore = address(this).balance;
        vm.expectRevert(WithdrawalVault.ZeroAddress.selector);
        vault.depositFor{value: 1 ether}(address(0));

        // L'ETH inviato con la call fallita torna al mittente: nessun wei resta nel vault.
        assertEq(address(this).balance, balanceBefore);
        assertEq(address(vault).balance, 0);
    }

    function test_DepositRejectsZeroAmount() public {
        address beneficiary = makeAddr("beneficiary");
        vm.expectRevert(WithdrawalVault.ZeroAmount.selector);
        vault.depositFor(beneficiary); // senza {value: ...} msg.value e' 0

        assertEq(vault.credit(beneficiary), 0);
        assertEq(vault.totalLiabilities(), 0);
    }

    // Permette al contratto di test di ricevere ETH.
    receive() external payable {}
}
