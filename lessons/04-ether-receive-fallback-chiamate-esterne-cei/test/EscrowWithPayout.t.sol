// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { EscrowWithPayout } from "../src/EscrowWithPayout.sol";
import { AcceptingSeller, RejectingSeller, ForceEther } from "./helpers/EtherReceivers.sol";

contract EscrowWithPayoutTest is Test {
    EscrowWithPayout internal escrow;

    address internal buyer;
    address payable internal seller;
    address internal outsider;

    uint256 internal constant PRICE = 5 ether;

    function setUp() public {
        buyer = makeAddr("buyer");
        seller = payable(makeAddr("seller"));
        outsider = makeAddr("outsider");

        vm.deal(buyer, 100 ether);
        vm.deal(outsider, 100 ether);

        vm.prank(buyer);
        escrow = new EscrowWithPayout(seller, PRICE);
    }

    function test_InitialState() public view {
        assertEq(escrow.buyer(), buyer);
        assertEq(escrow.seller(), seller);
        assertEq(escrow.price(), PRICE);
        _assertState(escrow, EscrowWithPayout.State.Created);
        assertEq(address(escrow).balance, 0);
    }

    function test_BuyerCanFundExactPrice() public {
        _fund(escrow);

        _assertState(escrow, EscrowWithPayout.State.Funded);
        assertEq(address(escrow).balance, PRICE);
    }

    function test_BuyerCanCancelBeforeFunding() public {
        vm.prank(buyer);
        escrow.cancelBeforeFunding();

        _assertState(escrow, EscrowWithPayout.State.Cancelled);
        assertEq(address(escrow).balance, 0);
    }

    function test_ReleasePaysEOASeller() public {
        _fund(escrow);
        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(buyer);
        escrow.release();

        _assertState(escrow, EscrowWithPayout.State.Released);
        assertEq(address(escrow).balance, 0);
        assertEq(seller.balance, sellerBalanceBefore + PRICE);
    }

    function test_ReleaseToContractExecutesReceiverCode() public {
        AcceptingSeller receiver = new AcceptingSeller();
        EscrowWithPayout contractSellerEscrow = _deploy(payable(address(receiver)));
        _fund(contractSellerEscrow);

        assertEq(receiver.totalReceived(), 0);

        vm.prank(buyer);
        contractSellerEscrow.release();

        assertEq(receiver.totalReceived(), PRICE);
        _assertState(contractSellerEscrow, EscrowWithPayout.State.Released);
        assertEq(address(contractSellerEscrow).balance, 0);
    }

    function test_RejectingSellerMakesReleaseRevertAtomically() public {
        RejectingSeller receiver = new RejectingSeller();
        EscrowWithPayout rejectingEscrow = _deploy(payable(address(receiver)));
        _fund(rejectingEscrow);

        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowWithPayout.EtherTransferFailed.selector, address(receiver), PRICE
            )
        );
        vm.prank(buyer);
        rejectingEscrow.release();

        _assertState(rejectingEscrow, EscrowWithPayout.State.Funded);
        assertEq(address(rejectingEscrow).balance, PRICE);
        assertEq(address(receiver).balance, 0);
    }

    function test_RevertWhen_OutsiderReleases() public {
        _fund(escrow);

        vm.expectRevert(abi.encodeWithSelector(EscrowWithPayout.Unauthorized.selector, outsider));
        vm.prank(outsider);
        escrow.release();

        _assertState(escrow, EscrowWithPayout.State.Funded);
        assertEq(address(escrow).balance, PRICE);
    }

    function test_RevertWhen_ReleasingBeforeFunding() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowWithPayout.WrongState.selector,
                EscrowWithPayout.State.Funded,
                EscrowWithPayout.State.Created
            )
        );
        vm.prank(buyer);
        escrow.release();

        _assertState(escrow, EscrowWithPayout.State.Created);
        assertEq(address(escrow).balance, 0);
    }

    function test_RevertWhen_ReleasingTwice() public {
        _fund(escrow);

        vm.prank(buyer);
        escrow.release();
        uint256 sellerBalanceAfterFirstRelease = seller.balance;

        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowWithPayout.WrongState.selector,
                EscrowWithPayout.State.Funded,
                EscrowWithPayout.State.Released
            )
        );
        vm.prank(buyer);
        escrow.release();

        assertEq(seller.balance, sellerBalanceAfterFirstRelease);
        _assertState(escrow, EscrowWithPayout.State.Released);
    }

    function test_PlainEtherTransferIsRejected() public {
        vm.prank(outsider);
        (bool success, bytes memory returnData) = address(escrow).call{ value: 1 ether }("");

        assertFalse(success);
        assertEq(bytes4(returnData), EscrowWithPayout.DirectEtherNotAccepted.selector);
        assertEq(address(escrow).balance, 0);
        _assertState(escrow, EscrowWithPayout.State.Created);
    }

    function test_EmptyCalldataWithZeroValueStillReachesReceive() public {
        vm.prank(outsider);
        (bool success, bytes memory returnData) = address(escrow).call("");

        assertFalse(success);
        assertEq(bytes4(returnData), EscrowWithPayout.DirectEtherNotAccepted.selector);
    }

    function test_UnknownSelectorIsRejected() public {
        bytes memory unknownCall = hex"deadbeef";

        vm.prank(outsider);
        (bool success, bytes memory returnData) = address(escrow).call(unknownCall);

        assertFalse(success);
        assertEq(
            keccak256(returnData),
            keccak256(
                abi.encodeWithSelector(EscrowWithPayout.UnknownCall.selector, bytes4(0xdeadbeef))
            )
        );
        _assertState(escrow, EscrowWithPayout.State.Created);
    }

    function test_ForcedEtherBypassesReceive() public {
        uint256 forcedAmount = 1 ether;
        vm.deal(address(this), forcedAmount);
        ForceEther force = new ForceEther{ value: forcedAmount }();

        force.force(payable(address(escrow)));

        assertEq(address(escrow).balance, forcedAmount);
        _assertState(escrow, EscrowWithPayout.State.Created);
    }

    function test_ForcedEtherDoesNotIncreaseSellerEntitlement() public {
        uint256 forcedAmount = 1 ether;
        vm.deal(address(this), forcedAmount);
        ForceEther force = new ForceEther{ value: forcedAmount }();
        force.force(payable(address(escrow)));

        _fund(escrow);
        assertEq(address(escrow).balance, PRICE + forcedAmount);

        uint256 sellerBalanceBefore = seller.balance;
        vm.prank(buyer);
        escrow.release();

        assertEq(seller.balance, sellerBalanceBefore + PRICE);
        assertEq(address(escrow).balance, forcedAmount);
        _assertState(escrow, EscrowWithPayout.State.Released);
    }

    function test_RevertWhen_CancellingAfterFunding() public {
        _fund(escrow);

        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowWithPayout.WrongState.selector,
                EscrowWithPayout.State.Created,
                EscrowWithPayout.State.Funded
            )
        );
        vm.prank(buyer);
        escrow.cancelBeforeFunding();

        _assertState(escrow, EscrowWithPayout.State.Funded);
        assertEq(address(escrow).balance, PRICE);
    }

    function test_RevertWhen_FundingWithWrongValue() public {
        uint256 wrongValue = PRICE - 1;

        vm.expectRevert(
            abi.encodeWithSelector(EscrowWithPayout.WrongValue.selector, PRICE, wrongValue)
        );
        vm.prank(buyer);
        escrow.fund{ value: wrongValue }();

        _assertState(escrow, EscrowWithPayout.State.Created);
        assertEq(address(escrow).balance, 0);
    }

    function test_RevertWhen_ConstructorArgumentsAreInvalid() public {
        vm.expectRevert(EscrowWithPayout.ZeroSeller.selector);
        vm.prank(buyer);
        new EscrowWithPayout(payable(address(0)), PRICE);

        vm.expectRevert(EscrowWithPayout.BuyerEqualsSeller.selector);
        vm.prank(buyer);
        new EscrowWithPayout(payable(buyer), PRICE);

        vm.expectRevert(EscrowWithPayout.ZeroPrice.selector);
        vm.prank(buyer);
        new EscrowWithPayout(seller, 0);
    }

    function _deploy(address payable seller_) internal returns (EscrowWithPayout target) {
        vm.prank(buyer);
        target = new EscrowWithPayout(seller_, PRICE);
    }

    function _fund(EscrowWithPayout target) internal {
        vm.prank(buyer);
        target.fund{ value: PRICE }();
    }

    function _assertState(EscrowWithPayout target, EscrowWithPayout.State expected) internal view {
        assertEq(uint256(target.state()), uint256(expected));
    }
}
