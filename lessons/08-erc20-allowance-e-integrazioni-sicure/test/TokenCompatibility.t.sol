// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "../src/token/IERC20.sol";
import { SafeERC20Lite } from "../src/token/SafeERC20Lite.sol";
import { TokenEscrow } from "../src/TokenEscrow.sol";
import { VulnerableTokenVault } from "../src/VulnerableTokenVault.sol";
import { FalseReturnToken } from "./mocks/FalseReturnToken.sol";
import { NoReturnToken } from "./mocks/NoReturnToken.sol";
import { FeeToken } from "./mocks/FeeToken.sol";
import { SelectiveFalseToken } from "./mocks/SelectiveFalseToken.sol";

contract TokenCompatibilityTest is Test {
    address internal buyer;
    address internal seller;

    uint256 internal constant AMOUNT = 100 ether;

    function setUp() public {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
    }

    /// @dev Il test passa dimostrando che la call e l'asset transfer non sono sinonimi.
    function test_Vulnerable_FalseReturnCreatesUnbackedCredit() public {
        FalseReturnToken token = new FalseReturnToken();
        VulnerableTokenVault vault = new VulnerableTokenVault(IERC20(address(token)));
        token.mint(buyer, AMOUNT);

        vm.prank(buyer);
        vault.deposit(AMOUNT);

        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(vault.credit(buyer), AMOUNT);
    }

    function test_SafeEscrowRejectsFalseReturnWithoutChangingState() public {
        FalseReturnToken token = new FalseReturnToken();
        TokenEscrow escrow = new TokenEscrow(IERC20(address(token)), buyer, seller);
        token.mint(buyer, AMOUNT);

        vm.prank(buyer);
        token.approve(address(escrow), AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(SafeERC20Lite.SafeTransferFailed.selector, address(token))
        );
        vm.prank(buyer);
        escrow.deposit(AMOUNT);

        assertEq(uint256(escrow.state()), uint256(TokenEscrow.State.Created));
        assertEq(escrow.escrowedAmount(), 0);
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    function test_SafeEscrowSupportsSuccessfulNoReturnToken() public {
        NoReturnToken token = new NoReturnToken();
        TokenEscrow escrow = new TokenEscrow(IERC20(address(token)), buyer, seller);
        token.mint(buyer, AMOUNT);

        vm.startPrank(buyer);
        token.approve(address(escrow), AMOUNT);
        escrow.deposit(AMOUNT);
        escrow.release();
        vm.stopPrank();

        assertEq(token.balanceOf(seller), AMOUNT);
        assertEq(escrow.escrowedAmount(), 0);
        assertEq(uint256(escrow.state()), uint256(TokenEscrow.State.Released));
    }

    function test_FeeTokenAccountsForActualAmountReceived() public {
        (FeeToken token, TokenEscrow escrow) = _fundFeeEscrow();

        assertEq(token.balanceOf(address(escrow)), 90 ether);
        assertEq(escrow.escrowedAmount(), 90 ether);
        assertEq(token.balanceOf(token.FEE_COLLECTOR()), 10 ether);
        assertGe(token.balanceOf(address(escrow)), escrow.escrowedAmount());
    }

    function test_FeeTokenPayoutPolicyLeavesSecondFeeToSeller() public {
        (FeeToken token, TokenEscrow escrow) = _fundFeeEscrow();

        vm.prank(buyer);
        escrow.release();

        assertEq(token.balanceOf(seller), 81 ether);
        assertEq(token.balanceOf(token.FEE_COLLECTOR()), 19 ether);
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(escrow.escrowedAmount(), 0);
        assertEq(uint256(escrow.state()), uint256(TokenEscrow.State.Released));
    }

    function test_FailedPayoutRollsBackEffectsAndState() public {
        SelectiveFalseToken token = new SelectiveFalseToken();
        TokenEscrow escrow = new TokenEscrow(IERC20(address(token)), buyer, seller);
        token.mint(buyer, AMOUNT);

        vm.startPrank(buyer);
        token.approve(address(escrow), AMOUNT);
        escrow.deposit(AMOUNT);
        vm.stopPrank();

        token.setFailDirectTransfers(true);

        vm.expectRevert(
            abi.encodeWithSelector(SafeERC20Lite.SafeTransferFailed.selector, address(token))
        );
        vm.prank(buyer);
        escrow.release();

        assertEq(uint256(escrow.state()), uint256(TokenEscrow.State.Funded));
        assertEq(escrow.escrowedAmount(), AMOUNT);
        assertEq(token.balanceOf(address(escrow)), AMOUNT);
        assertEq(token.balanceOf(seller), 0);
    }

    function _fundFeeEscrow() internal returns (FeeToken token, TokenEscrow escrow) {
        token = new FeeToken();
        escrow = new TokenEscrow(IERC20(address(token)), buyer, seller);
        token.mint(buyer, AMOUNT);

        vm.startPrank(buyer);
        token.approve(address(escrow), AMOUNT);
        escrow.deposit(AMOUNT);
        vm.stopPrank();
    }
}

