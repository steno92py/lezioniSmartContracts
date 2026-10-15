// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Unit test delle funzioni amministrative: chi puo' cambiare fee e oracle, entro quali limiti.
// Cheatcode: vm.prank, vm.expectRevert, vm.expectEmit (vedi Deposit.t.sol).
import {TestingEscrow} from "../../src/TestingEscrow.sol";
import {MockOracle} from "../../src/mocks/TestingMocks.sol";
import {EscrowTestBase} from "../helpers/EscrowTestBase.sol";

contract AdministrationTest is EscrowTestBase {
    event FeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    function test_OwnerUpdatesFeeWithEventAndState() public {
        // FeeUpdated non ha campi indexed: si confrontano solo i dati (ultimo bool a true).
        vm.expectEmit(false, false, false, true, address(escrow));
        emit FeeUpdated(0, 250);
        vm.prank(owner);
        escrow.setFee(250);

        assertEq(escrow.feeBps(), 250);
    }

    // CONFINE di `fee <= 1000`: 999 (dentro), 1000 (limite esatto, incluso), 1001 (fuori).
    // Se `>` diventasse `>=` nel contratto, il test su 1000 diventerebbe rosso.
    function test_FeeBoundary999Succeeds() public {
        vm.prank(owner);
        escrow.setFee(999);
        assertEq(escrow.feeBps(), 999);
    }

    function test_FeeBoundary1000Succeeds() public {
        vm.prank(owner);
        escrow.setFee(1_000);
        assertEq(escrow.feeBps(), 1_000);
    }

    function test_FeeBoundary1001RevertsAndPreservesOldFee() public {
        vm.expectRevert(abi.encodeWithSelector(TestingEscrow.FeeTooHigh.selector, 1_001));
        vm.prank(owner);
        escrow.setFee(1_001);
        assertEq(escrow.feeBps(), 0); // la fee precedente (0) resta in vigore
    }

    function test_StrangerCannotSetFee() public {
        vm.expectRevert(abi.encodeWithSelector(TestingEscrow.Unauthorized.selector, stranger));
        vm.prank(stranger);
        escrow.setFee(250);
        assertEq(escrow.feeBps(), 0);
    }

    function test_OwnerUpdatesOracleWithEventAndState() public {
        MockOracle replacement = new MockOracle();

        // OracleUpdated ha due campi indexed e nessun dato: si confrontano i primi due topic.
        vm.expectEmit(true, true, false, false, address(escrow));
        emit OracleUpdated(address(oracle), address(replacement));
        vm.prank(owner);
        escrow.setOracle(address(replacement));

        assertEq(address(escrow.oracle()), address(replacement));
    }

    // Chiamato dall'owner, cosi' l'unico motivo di revert possibile e' l'indirizzo zero.
    function test_ZeroOracleIsRejected() public {
        vm.expectRevert(TestingEscrow.ZeroAddress.selector);
        vm.prank(owner);
        escrow.setOracle(address(0));
        assertEq(address(escrow.oracle()), address(oracle));
    }

    function test_StrangerCannotSetOracle() public {
        MockOracle replacement = new MockOracle();
        vm.expectRevert(abi.encodeWithSelector(TestingEscrow.Unauthorized.selector, stranger));
        vm.prank(stranger);
        escrow.setOracle(address(replacement));
    }
}

