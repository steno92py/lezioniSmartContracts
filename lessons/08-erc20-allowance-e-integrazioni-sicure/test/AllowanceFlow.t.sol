// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { TestToken } from "./mocks/TestToken.sol";

contract AllowanceFlowTest is Test {
    TestToken internal token;
    address internal owner;
    address internal spender;
    address internal recipient;

    function setUp() public {
        token = new TestToken();
        owner = makeAddr("owner");
        spender = makeAddr("spender");
        recipient = makeAddr("recipient");
        token.mint(owner, 1_000 ether);
    }

    function test_ApproveChangesAuthorizationButMovesNoTokens() public {
        vm.prank(owner);
        token.approve(spender, 100 ether);

        assertEq(token.balanceOf(owner), 1_000 ether);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(owner, spender), 100 ether);
    }

    function test_TransferFromConsumesExactAllowance() public {
        vm.prank(owner);
        token.approve(spender, 100 ether);

        vm.prank(spender);
        token.transferFrom(owner, recipient, 100 ether);

        assertEq(token.balanceOf(owner), 900 ether);
        assertEq(token.balanceOf(recipient), 100 ether);
        assertEq(token.allowance(owner, spender), 0);
    }

    function test_LargerAllowancePersistsAfterPartialSpend() public {
        vm.prank(owner);
        token.approve(spender, 1_000 ether);

        vm.prank(spender);
        token.transferFrom(owner, recipient, 100 ether);

        assertEq(token.allowance(owner, spender), 900 ether);
    }
}

