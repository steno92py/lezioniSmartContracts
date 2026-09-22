// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Vm} from "forge-std/Vm.sol";
import {FinalTestBase} from "../helpers/FinalTestBase.sol";
import {EscrowFinal} from "../../src/EscrowFinal.sol";
import {INotifierFinal} from "../../src/interfaces/IFinalDependencies.sol";
import {TestToken, FeeToken, FalsePayoutToken, MockOracle, RevertingNotifier} from "../../src/mocks/FinalMocks.sol";

contract TargetFindingsTest is FinalTestBase {
    function test_F01_NominalAccountingExceedsReceivedAssets() public {
        FeeToken token = new FeeToken();
        MockOracle oracle = _freshOracle();
        EscrowFinal escrow = _target(token, oracle, INotifierFinal(address(0)));

        _fundTarget(token, escrow, AMOUNT);

        assertEq(token.balanceOf(address(escrow)), 90 ether);
        assertEq(escrow.escrowedAmount(), AMOUNT);
        assertLt(token.balanceOf(address(escrow)), escrow.escrowedAmount());
    }

    function test_F02_StaleOracleStillAllowsRelease() public {
        TestToken token = new TestToken();
        MockOracle oracle = new MockOracle(VALID_PRICE, block.timestamp - 2 hours);
        EscrowFinal escrow = _target(token, oracle, INotifierFinal(address(0)));
        _fundTarget(token, escrow, AMOUNT);

        vm.prank(buyer);
        escrow.release();

        assertEq(uint256(escrow.state()), uint256(EscrowFinal.State.Released));
        assertEq(token.balanceOf(seller), AMOUNT);
    }

    function test_F03_FalseReturnCreatesFalseTerminalSuccess() public {
        FalsePayoutToken token = new FalsePayoutToken();
        MockOracle oracle = _freshOracle();
        EscrowFinal escrow = _target(token, oracle, INotifierFinal(address(0)));
        _fundTarget(token, escrow, AMOUNT);

        vm.prank(buyer);
        escrow.release();

        assertEq(uint256(escrow.state()), uint256(EscrowFinal.State.Released));
        assertEq(escrow.escrowedAmount(), 0);
        assertEq(token.balanceOf(seller), 0);
        assertEq(token.balanceOf(address(escrow)), AMOUNT);
    }

    function test_F04_StrangerCanReplaceOracle() public {
        TestToken token = new TestToken();
        MockOracle oracle = _freshOracle();
        MockOracle attackerOracle = new MockOracle(1, block.timestamp);
        EscrowFinal escrow = _target(token, oracle, INotifierFinal(address(0)));

        vm.prank(stranger);
        escrow.setOracle(attackerOracle);

        assertEq(address(escrow.oracle()), address(attackerOracle));
    }

    function test_F05_NotifierFailureIsSilentButSettlementContinues() public {
        TestToken token = new TestToken();
        MockOracle oracle = _freshOracle();
        RevertingNotifier notifier = new RevertingNotifier();
        EscrowFinal escrow = _target(token, oracle, notifier);
        _fundTarget(token, escrow, AMOUNT);

        vm.recordLogs();
        vm.prank(buyer);
        escrow.release();
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1, "solo Released: il notifier failure non e' osservabile");
        assertEq(entries[0].topics[0], keccak256("Released(uint256,uint256)"));
        assertEq(token.balanceOf(seller), AMOUNT);
    }
}

