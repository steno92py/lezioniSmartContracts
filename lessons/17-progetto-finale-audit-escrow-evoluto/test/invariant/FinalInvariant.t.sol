// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {EscrowFinalFixed} from "../../src/fixed/EscrowFinalFixed.sol";
import {TestToken, MockOracle} from "../../src/mocks/FinalMocks.sol";
import {INotifierFinal} from "../../src/interfaces/IFinalDependencies.sol";

contract FinalHandler is Test {
    EscrowFinalFixed public immutable escrow;
    TestToken public immutable token;
    MockOracle public immutable oracle;
    address public immutable buyer;
    address public immutable owner;
    address public immutable pauser;

    uint256 public credited;
    bool public terminalSeen;
    bool public terminalBroken;

    constructor(
        EscrowFinalFixed escrow_,
        TestToken token_,
        MockOracle oracle_,
        address buyer_,
        address owner_,
        address pauser_
    ) {
        escrow = escrow_;
        token = token_;
        oracle = oracle_;
        buyer = buyer_;
        owner = owner_;
        pauser = pauser_;
    }

    function deposit(uint96 rawAmount) external {
        if (escrow.state() != EscrowFinalFixed.State.Created || escrow.paused()) return;
        uint256 amount = bound(uint256(rawAmount), 1, 1_000_000 ether);
        token.mint(buyer, amount);
        vm.startPrank(buyer);
        token.approve(address(escrow), amount);
        escrow.deposit(amount);
        vm.stopPrank();
        credited = escrow.escrowedAmount();
        _observe();
    }

    function release() external {
        if (escrow.state() != EscrowFinalFixed.State.Funded || escrow.paused()) return;
        oracle.setPrice(3_000e8, block.timestamp);
        vm.prank(buyer);
        escrow.release();
        _observe();
    }

    function refund() external {
        if (escrow.state() != EscrowFinalFixed.State.Funded) return;
        vm.prank(buyer);
        escrow.refund();
        _observe();
    }

    function pause() external {
        vm.prank(pauser);
        escrow.pause();
        _observe();
    }

    function unpause() external {
        vm.prank(owner);
        escrow.unpause();
        _observe();
    }

    function setFee(uint16 rawFee) external {
        uint256 fee = bound(uint256(rawFee), 0, 1_100);
        vm.prank(owner);
        try escrow.setFee(fee) {} catch {}
        _observe();
    }

    function _observe() private {
        EscrowFinalFixed.State current = escrow.state();
        bool terminal = current == EscrowFinalFixed.State.Released || current == EscrowFinalFixed.State.Refunded;
        if (terminalSeen && !terminal) terminalBroken = true;
        if (terminal) terminalSeen = true;
    }
}

contract FinalInvariantTest is StdInvariant, Test {
    TestToken internal token;
    MockOracle internal oracle;
    EscrowFinalFixed internal escrow;
    FinalHandler internal handler;
    address internal buyer;
    address internal seller;
    address internal owner;
    address internal pauser;

    function setUp() public {
        vm.warp(1_000_000);
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        owner = makeAddr("owner");
        pauser = makeAddr("pauser");
        token = new TestToken();
        oracle = new MockOracle(3_000e8, block.timestamp);
        escrow = new EscrowFinalFixed(token, buyer, seller, owner, pauser, oracle, INotifierFinal(address(0)));
        handler = new FinalHandler(escrow, token, oracle, buyer, owner, pauser);

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = FinalHandler.deposit.selector;
        selectors[1] = FinalHandler.release.selector;
        selectors[2] = FinalHandler.refund.selector;
        selectors[3] = FinalHandler.pause.selector;
        selectors[4] = FinalHandler.unpause.selector;
        selectors[5] = FinalHandler.setFee.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_FundedLiabilityIsBacked() public view {
        if (escrow.state() == EscrowFinalFixed.State.Funded) {
            assertGe(token.balanceOf(address(escrow)), escrow.escrowedAmount());
        }
    }

    function invariant_TerminalStateClearsLiability() public view {
        EscrowFinalFixed.State current = escrow.state();
        if (current == EscrowFinalFixed.State.Released || current == EscrowFinalFixed.State.Refunded) {
            assertEq(escrow.escrowedAmount(), 0);
        }
    }

    function invariant_TerminalStateNeverReopens() public view {
        assertFalse(handler.terminalBroken());
    }

    function invariant_FeeAlwaysWithinBound() public view {
        assertLe(escrow.feeBps(), 1_000);
    }

    function invariant_SellerNeverReceivesMoreThanCredited() public view {
        assertLe(token.balanceOf(seller), handler.credited());
    }
}
