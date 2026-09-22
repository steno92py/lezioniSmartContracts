// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { MinimumFeeRegistry } from "../src/MinimumFeeRegistry.sol";

/// @notice Questa suite deve fallire: il fallimento dimostra che il test scopre la mutazione.
contract MinimumFeeRegistryMutationTest is Test {
    MinimumFeeRegistry internal registry;

    address internal constant ALICE = address(0xA11CE);

    function setUp() public {
        registry = new MinimumFeeRegistry();
        vm.deal(ALICE, 10 ether);
    }

    function test_RevertWhen_FeeIsTooHigh() public {
        uint256 sent = 2 ether;

        vm.expectRevert(
            abi.encodeWithSelector(
                MinimumFeeRegistry.ExactFeeRequired.selector, sent, registry.REGISTRATION_FEE()
            )
        );
        vm.prank(ALICE);
        registry.register{ value: sent }();
    }
}

