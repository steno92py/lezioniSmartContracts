// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { UncheckedCallEscrow } from "../src/labs/UncheckedCallEscrow.sol";
import { RejectingSeller } from "./helpers/EtherReceivers.sol";

contract UncheckedCallEscrowTest is Test {
    address internal buyer;
    uint256 internal constant PRICE = 5 ether;

    function setUp() public {
        buyer = makeAddr("buyer");
        vm.deal(buyer, 100 ether);
    }

    /// @dev Il test passa dimostrando che una transaction riuscita puo' mentire sul payout.
    function test_DemonstratesFalseReleasedStateAfterFailedPayout() public {
        RejectingSeller receiver = new RejectingSeller();

        vm.prank(buyer);
        UncheckedCallEscrow broken = new UncheckedCallEscrow(payable(address(receiver)), PRICE);

        vm.prank(buyer);
        broken.fund{ value: PRICE }();

        vm.prank(buyer);
        broken.release();

        assertEq(uint256(broken.state()), uint256(UncheckedCallEscrow.State.Released));
        assertEq(address(receiver).balance, 0);
        assertEq(address(broken).balance, PRICE);
    }
}

