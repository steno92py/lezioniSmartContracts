// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {WithdrawalVault} from "../../src/WithdrawalVault.sol";
import {ReentrantReceiver, RejectEther} from "../../src/mocks/TestingMocks.sol";

contract ReentrancyRegressionTest is Test {
    WithdrawalVault internal vault;

    function setUp() public {
        vault = new WithdrawalVault();
        vm.deal(address(this), 10 ether);
    }

    function test_Regression_ReentrantCallbackCannotWithdrawTwice() public {
        ReentrantReceiver receiver = new ReentrantReceiver(vault);
        address honestUser = makeAddr("honest-user");
        vault.depositFor{value: 1 ether}(address(receiver));
        vault.depositFor{value: 2 ether}(honestUser);

        receiver.attack();

        assertTrue(receiver.callbackAttempted());
        assertFalse(receiver.secondWithdrawalSucceeded());
        assertEq(address(receiver).balance, 1 ether);
        assertEq(vault.credit(address(receiver)), 0);
        assertEq(vault.credit(honestUser), 2 ether);
        assertEq(vault.totalLiabilities(), 2 ether);
        assertEq(address(vault).balance, 2 ether);
    }

    function test_Regression_RevertingRecipientRollsBackCredit() public {
        RejectEther rejector = new RejectEther();
        vault.depositFor{value: 1 ether}(address(rejector));

        vm.expectRevert(WithdrawalVault.EtherTransferFailed.selector);
        rejector.claim(vault);

        assertEq(vault.credit(address(rejector)), 1 ether);
        assertEq(vault.totalLiabilities(), 1 ether);
        assertEq(address(vault).balance, 1 ether);
    }

    function test_WithdrawWithoutCreditUsesExactErrorPayload() public {
        address stranger = makeAddr("stranger");
        vm.expectRevert(abi.encodeWithSelector(WithdrawalVault.NoCredit.selector, stranger));
        vm.prank(stranger);
        vault.withdraw();
    }

    function test_DepositRejectsZeroBeneficiary() public {
        uint256 balanceBefore = address(this).balance;
        vm.expectRevert(WithdrawalVault.ZeroAddress.selector);
        vault.depositFor{value: 1 ether}(address(0));

        assertEq(address(this).balance, balanceBefore);
        assertEq(address(vault).balance, 0);
    }

    function test_DepositRejectsZeroAmount() public {
        address beneficiary = makeAddr("beneficiary");
        vm.expectRevert(WithdrawalVault.ZeroAmount.selector);
        vault.depositFor(beneficiary);

        assertEq(vault.credit(beneficiary), 0);
        assertEq(vault.totalLiabilities(), 0);
    }

    receive() external payable {}
}
