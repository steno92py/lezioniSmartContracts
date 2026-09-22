// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "../src/token/IERC20.sol";
import { TokenEscrow } from "../src/TokenEscrow.sol";
import { TestToken } from "./mocks/TestToken.sol";

contract TokenEscrowTest is Test {
    TestToken internal token;
    TokenEscrow internal escrow;

    address internal buyer;
    address internal seller;
    address internal stranger;

    uint256 internal constant INITIAL_BALANCE = 1_000 ether;
    uint256 internal constant AMOUNT = 100 ether;

    function setUp() public {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        stranger = makeAddr("stranger");

        token = new TestToken();
        escrow = new TokenEscrow(IERC20(address(token)), buyer, seller);
        token.mint(buyer, INITIAL_BALANCE);
    }

    function test_InitialConfiguration() public view {
        assertEq(address(escrow.token()), address(token));
        assertEq(escrow.buyer(), buyer);
        assertEq(escrow.seller(), seller);
        assertEq(escrow.escrowedAmount(), 0);
        _assertState(TokenEscrow.State.Created);
    }

    function test_DepositMovesTokensAndConsumesExactAllowance() public {
        _approveAndDeposit(AMOUNT, AMOUNT);

        assertEq(token.balanceOf(buyer), INITIAL_BALANCE - AMOUNT);
        assertEq(token.balanceOf(address(escrow)), AMOUNT);
        assertEq(token.allowance(buyer, address(escrow)), 0);
        assertEq(escrow.escrowedAmount(), AMOUNT);
        _assertFundedAndSolvent();
    }

    function test_LargerAllowanceRemainsAfterDeposit() public {
        _approveAndDeposit(1_000 ether, AMOUNT);

        assertEq(token.allowance(buyer, address(escrow)), 900 ether);
        _assertFundedAndSolvent();
    }

    function test_ReleasePaysSellerAndEndsPosition() public {
        _deposit(AMOUNT);

        vm.prank(buyer);
        escrow.release();

        assertEq(token.balanceOf(seller), AMOUNT);
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(escrow.escrowedAmount(), 0);
        _assertState(TokenEscrow.State.Released);
    }

    function test_RefundReturnsTokensAndEndsPosition() public {
        _deposit(AMOUNT);

        vm.prank(buyer);
        escrow.refund();

        assertEq(token.balanceOf(buyer), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(escrow.escrowedAmount(), 0);
        _assertState(TokenEscrow.State.Refunded);
    }

    function test_RevertWhen_DepositingWithoutAllowance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                TestToken.InsufficientAllowance.selector, address(escrow), 0, AMOUNT
            )
        );
        vm.prank(buyer);
        escrow.deposit(AMOUNT);

        _assertCreatedAndEmpty();
    }

    function test_RevertWhen_AllowanceIsInsufficient() public {
        vm.prank(buyer);
        token.approve(address(escrow), AMOUNT - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                TestToken.InsufficientAllowance.selector, address(escrow), AMOUNT - 1, AMOUNT
            )
        );
        vm.prank(buyer);
        escrow.deposit(AMOUNT);

        _assertCreatedAndEmpty();
        assertEq(token.allowance(buyer, address(escrow)), AMOUNT - 1);
    }

    function test_RevertWhen_BalanceIsInsufficient() public {
        uint256 tooMuch = INITIAL_BALANCE + 1;
        vm.prank(buyer);
        token.approve(address(escrow), tooMuch);

        vm.expectRevert(
            abi.encodeWithSelector(
                TestToken.InsufficientBalance.selector, buyer, INITIAL_BALANCE, tooMuch
            )
        );
        vm.prank(buyer);
        escrow.deposit(tooMuch);

        _assertCreatedAndEmpty();
        assertEq(token.allowance(buyer, address(escrow)), tooMuch);
    }

    function test_RevertWhen_StrangerHasTokensAndAllowance() public {
        token.mint(stranger, AMOUNT);
        vm.prank(stranger);
        token.approve(address(escrow), AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(TokenEscrow.OnlyBuyer.selector, stranger));
        vm.prank(stranger);
        escrow.deposit(AMOUNT);

        assertEq(token.balanceOf(stranger), AMOUNT);
        _assertCreatedAndEmpty();
    }

    function test_RevertWhen_DepositIsZero() public {
        vm.expectRevert(TokenEscrow.ZeroAmount.selector);
        vm.prank(buyer);
        escrow.deposit(0);

        _assertCreatedAndEmpty();
    }

    function test_RevertWhen_DepositingTwice() public {
        _deposit(AMOUNT);

        _expectInvalidState(TokenEscrow.State.Created, TokenEscrow.State.Funded);
        vm.prank(buyer);
        escrow.deposit(AMOUNT);

        _assertFundedAndSolvent();
    }

    function test_RevertWhen_ReleasingBeforeFunding() public {
        _expectInvalidState(TokenEscrow.State.Funded, TokenEscrow.State.Created);
        vm.prank(buyer);
        escrow.release();

        _assertCreatedAndEmpty();
    }

    function test_RevertWhen_RefundingBeforeFunding() public {
        _expectInvalidState(TokenEscrow.State.Funded, TokenEscrow.State.Created);
        vm.prank(buyer);
        escrow.refund();

        _assertCreatedAndEmpty();
    }

    function test_RevertWhen_ReleasingTwice() public {
        _depositAndRelease();

        _expectInvalidState(TokenEscrow.State.Funded, TokenEscrow.State.Released);
        vm.prank(buyer);
        escrow.release();

        _assertReleasedAndEmpty();
    }

    function test_RevertWhen_RefundingAfterRelease() public {
        _depositAndRelease();

        _expectInvalidState(TokenEscrow.State.Funded, TokenEscrow.State.Released);
        vm.prank(buyer);
        escrow.refund();

        _assertReleasedAndEmpty();
    }

    function test_RevertWhen_StrangerTriesToRelease() public {
        _deposit(AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(TokenEscrow.OnlyBuyer.selector, stranger));
        vm.prank(stranger);
        escrow.release();

        _assertFundedAndSolvent();
    }

    function test_RevertWhen_TokenHasNoCode() public {
        vm.expectRevert(abi.encodeWithSelector(TokenEscrow.InvalidToken.selector, stranger));
        new TokenEscrow(IERC20(stranger), buyer, seller);
    }

    function test_RevertWhen_BuyerIsZero() public {
        vm.expectRevert(TokenEscrow.ZeroAddress.selector);
        new TokenEscrow(IERC20(address(token)), address(0), seller);
    }

    function test_RevertWhen_SellerIsZero() public {
        vm.expectRevert(TokenEscrow.ZeroAddress.selector);
        new TokenEscrow(IERC20(address(token)), buyer, address(0));
    }

    function test_RevertWhen_PartiesAreEqual() public {
        vm.expectRevert(TokenEscrow.SameParty.selector);
        new TokenEscrow(IERC20(address(token)), buyer, buyer);
    }

    function _approveAndDeposit(uint256 approval, uint256 requested) internal {
        vm.startPrank(buyer);
        token.approve(address(escrow), approval);
        escrow.deposit(requested);
        vm.stopPrank();
    }

    function _deposit(uint256 amount) internal {
        _approveAndDeposit(amount, amount);
    }

    function _depositAndRelease() internal {
        _deposit(AMOUNT);
        vm.prank(buyer);
        escrow.release();
    }

    function _expectInvalidState(TokenEscrow.State expected, TokenEscrow.State actual) internal {
        vm.expectRevert(abi.encodeWithSelector(TokenEscrow.InvalidState.selector, expected, actual));
    }

    function _assertState(TokenEscrow.State expected) internal view {
        assertEq(uint256(escrow.state()), uint256(expected));
    }

    function _assertCreatedAndEmpty() internal view {
        _assertState(TokenEscrow.State.Created);
        assertEq(escrow.escrowedAmount(), 0);
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    function _assertFundedAndSolvent() internal view {
        _assertState(TokenEscrow.State.Funded);
        assertGe(token.balanceOf(address(escrow)), escrow.escrowedAmount());
    }

    function _assertReleasedAndEmpty() internal view {
        _assertState(TokenEscrow.State.Released);
        assertEq(escrow.escrowedAmount(), 0);
        assertEq(token.balanceOf(address(escrow)), 0);
    }
}
