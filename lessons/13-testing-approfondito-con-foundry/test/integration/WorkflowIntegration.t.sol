// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Integration test del flusso completo: configurazione, deposito e rilascio in sequenza.
import {TestingEscrow} from "../../src/TestingEscrow.sol";
import {EscrowTestBase} from "../helpers/EscrowTestBase.sol";

contract WorkflowIntegrationTest is EscrowTestBase {
    function test_FullDepositAndReleaseWorkflowPreservesEconomicAccounting() public {
        uint256 amount = 400 ether;
        vm.prank(owner);
        escrow.setFee(500); // 5%

        _approveAndDeposit(amount);
        // Invariante economico a meta' flusso: i token posseduti coprono cio' che e' dovuto.
        assertEq(token.balanceOf(address(escrow)), escrow.liability());

        vm.prank(buyer);
        escrow.release();

        // 400 ether = 380 al seller + 20 (5%) all'owner + 0 rimasti nell'escrow.
        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Released));
        assertEq(token.balanceOf(seller), 380 ether);
        assertEq(token.balanceOf(owner), 20 ether);
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(escrow.liability(), 0);
    }

    // Test di isolamento: il test precedente ha modificato fee e stato, ma setUp() riparte
    // da zero prima di ogni test. Nessun test dipende dall'ordine di esecuzione degli altri.
    function test_EachTestStartsFromSetUpState() public view {
        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Created));
        assertEq(escrow.depositedAmount(), 0);
        assertEq(token.balanceOf(buyer), BUYER_BALANCE);
    }
}

