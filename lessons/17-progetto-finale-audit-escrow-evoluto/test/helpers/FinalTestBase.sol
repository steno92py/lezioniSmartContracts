// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {IERC20Final, IPriceOracleFinal, INotifierFinal} from "../../src/interfaces/IFinalDependencies.sol";
import {EscrowFinal} from "../../src/EscrowFinal.sol";
import {EscrowFinalFixed} from "../../src/fixed/EscrowFinalFixed.sol";
import {TestToken, MockOracle} from "../../src/mocks/FinalMocks.sol";

abstract contract FinalTestBase is Test {
    uint256 internal constant AMOUNT = 100 ether;
    int256 internal constant VALID_PRICE = 3_000e8;

    address internal buyer;
    address internal seller;
    address internal owner;
    address internal pauser;
    address internal stranger;

    function setUp() public virtual {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        owner = makeAddr("owner");
        pauser = makeAddr("pauser");
        stranger = makeAddr("stranger");
        vm.warp(1_000_000);
    }

    function _target(IERC20Final token, IPriceOracleFinal oracle, INotifierFinal notifier)
        internal
        returns (EscrowFinal)
    {
        return new EscrowFinal(token, buyer, seller, owner, pauser, oracle, notifier);
    }

    function _fixed(IERC20Final token, IPriceOracleFinal oracle, INotifierFinal notifier)
        internal
        returns (EscrowFinalFixed)
    {
        return new EscrowFinalFixed(token, buyer, seller, owner, pauser, oracle, notifier);
    }

    function _fundTarget(TestToken token, EscrowFinal escrow, uint256 amount) internal {
        token.mint(buyer, amount);
        vm.startPrank(buyer);
        token.approve(address(escrow), amount);
        escrow.deposit(amount);
        vm.stopPrank();
    }

    function _fundFixed(TestToken token, EscrowFinalFixed escrow, uint256 amount) internal {
        token.mint(buyer, amount);
        vm.startPrank(buyer);
        token.approve(address(escrow), amount);
        escrow.deposit(amount);
        vm.stopPrank();
    }

    function _freshOracle() internal returns (MockOracle) {
        return new MockOracle(VALID_PRICE, block.timestamp);
    }
}

