// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {TestingEscrow} from "../../src/TestingEscrow.sol";
import {ConfigurableToken, MockOracle} from "../../src/mocks/TestingMocks.sol";

contract ConfigurationTest is Test {
    ConfigurableToken internal token;
    MockOracle internal oracle;

    address internal buyer = makeAddr("buyer");
    address internal seller = makeAddr("seller");
    address internal owner = makeAddr("owner");

    function setUp() public {
        token = new ConfigurableToken();
        oracle = new MockOracle();
    }

    function test_ConstructorRejectsZeroToken() public {
        vm.expectRevert(TestingEscrow.ZeroAddress.selector);
        new TestingEscrow(address(0), address(oracle), buyer, seller, owner, block.timestamp + 1 days);
    }

    function test_ConstructorRejectsZeroOracle() public {
        vm.expectRevert(TestingEscrow.ZeroAddress.selector);
        new TestingEscrow(address(token), address(0), buyer, seller, owner, block.timestamp + 1 days);
    }

    function test_ConstructorRejectsZeroBuyer() public {
        vm.expectRevert(TestingEscrow.ZeroAddress.selector);
        new TestingEscrow(address(token), address(oracle), address(0), seller, owner, block.timestamp + 1 days);
    }

    function test_ConstructorRejectsZeroSeller() public {
        vm.expectRevert(TestingEscrow.ZeroAddress.selector);
        new TestingEscrow(address(token), address(oracle), buyer, address(0), owner, block.timestamp + 1 days);
    }

    function test_ConstructorRejectsZeroOwner() public {
        vm.expectRevert(TestingEscrow.ZeroAddress.selector);
        new TestingEscrow(address(token), address(oracle), buyer, seller, address(0), block.timestamp + 1 days);
    }
}

