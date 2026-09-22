// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {RemediatedEscrow} from "../../src/fixed/RemediatedEscrow.sol";
import {MockToken, MockOracle} from "../../src/mocks/AuditMocks.sol";
import {ISettlementNotifier} from "../../src/interfaces/IAuditDependencies.sol";

contract EscrowHandler {
    RemediatedEscrow public escrow;
    MockToken public token;

    function configure(RemediatedEscrow escrow_, MockToken token_, uint256 amount) external {
        require(address(escrow) == address(0), "CONFIGURED");
        escrow = escrow_;
        token = token_;
        token.approve(address(escrow_), amount);
        escrow_.deposit(amount);
    }

    function release() external {
        try escrow.release() {} catch {}
    }

    function refund() external {
        try escrow.refund() {} catch {}
    }
}

contract RemediatedInvariantTest is StdInvariant, Test {
    uint256 internal constant AMOUNT = 100 ether;

    MockToken internal token;
    RemediatedEscrow internal escrow;
    EscrowHandler internal handler;
    address internal seller;

    function setUp() public {
        vm.warp(1_000_000);
        seller = makeAddr("seller");
        address governance = makeAddr("governance");
        address guardian = makeAddr("guardian");

        token = new MockToken();
        MockOracle oracle = new MockOracle(100e8, block.timestamp);
        handler = new EscrowHandler();
        escrow = new RemediatedEscrow(
            address(handler),
            seller,
            governance,
            guardian,
            token,
            oracle,
            ISettlementNotifier(address(0)),
            100e8,
            1 hours
        );

        token.mint(address(handler), AMOUNT);
        handler.configure(escrow, token, AMOUNT);
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = EscrowHandler.release.selector;
        selectors[1] = EscrowHandler.refund.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_AssetsAlwaysCoverLiability() public view {
        assertGe(token.balanceOf(address(escrow)), escrow.liability());
    }

    function invariant_TerminalStateHasNoLiability() public view {
        RemediatedEscrow.State current = escrow.state();
        if (current == RemediatedEscrow.State.Released || current == RemediatedEscrow.State.Refunded) {
            assertEq(escrow.liability(), 0);
        }
    }

    function invariant_SellerCannotReceiveMoreThanOneSettlement() public view {
        assertLe(token.balanceOf(seller), AMOUNT);
    }
}
