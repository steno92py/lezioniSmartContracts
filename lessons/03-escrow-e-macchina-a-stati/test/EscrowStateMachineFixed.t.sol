// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Test della versione corretta: solo release(), il resto e' identico a EscrowStateMachine
// ed e' gia' coperto da test/EscrowStateMachine.t.sol.
import { Test } from "forge-std/Test.sol";
import { EscrowStateMachineFixed } from "../src/fixed/EscrowStateMachineFixed.sol";

// Seller che e' un contratto senza receive() ne' fallback(): qualunque invio di ETH verso di
// lui fallisce. Puo' pero' chiamare release(), perche' come seller e' autorizzato.
contract RejectingSeller {
    function callRelease(EscrowStateMachineFixed escrow) external {
        escrow.release();
    }
}

contract EscrowStateMachineFixedTest is Test {
    EscrowStateMachineFixed internal escrow;

    address internal buyer;
    address internal seller;
    address internal outsider;

    uint256 internal constant PRICE = 5 ether;

    function setUp() public {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        outsider = makeAddr("outsider");

        vm.deal(buyer, 100 ether);

        vm.prank(buyer);
        escrow = new EscrowStateMachineFixed(seller, PRICE);
    }

    // Caso felice: fund -> approveRelease -> release. L'ETH esce verso il seller.
    function test_SellerReleasesAfterApproval() public {
        _fundAndApprove();

        vm.expectEmit(true, true, false, true, address(escrow));
        emit EscrowStateMachineFixed.Released(buyer, seller, PRICE);

        vm.prank(seller);
        escrow.release();

        _assertState(EscrowStateMachineFixed.State.Released);
        assertEq(seller.balance, PRICE, "il prezzo deve arrivare al seller");
        assertEq(address(escrow).balance, 0, "il contratto non deve trattenere nulla");
    }

    // CHI: il buyer non puo' incassare al posto del seller.
    function test_RevertWhen_BuyerReleases() public {
        _fundAndApprove();

        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateMachineFixed.Unauthorized.selector, buyer)
        );
        vm.prank(buyer);
        escrow.release();

        _assertState(EscrowStateMachineFixed.State.ReleaseApproved);
        assertEq(address(escrow).balance, PRICE);
    }

    // CHI: un outsider nemmeno.
    function test_RevertWhen_OutsiderReleases() public {
        _fundAndApprove();

        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateMachineFixed.Unauthorized.selector, outsider)
        );
        vm.prank(outsider);
        escrow.release();

        _assertState(EscrowStateMachineFixed.State.ReleaseApproved);
        assertEq(address(escrow).balance, PRICE);
    }

    // QUANDO: senza l'approvazione del buyer il seller non incassa, anche se l'ETH e' dentro.
    function test_RevertWhen_ReleaseBeforeApproval() public {
        vm.prank(buyer);
        escrow.fund{ value: PRICE }();

        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowStateMachineFixed.WrongState.selector,
                EscrowStateMachineFixed.State.ReleaseApproved,
                EscrowStateMachineFixed.State.Funded
            )
        );
        vm.prank(seller);
        escrow.release();

        _assertState(EscrowStateMachineFixed.State.Funded);
        assertEq(address(escrow).balance, PRICE);
    }

    // Released e' terminale: lo stesso prezzo non si incassa due volte.
    function test_RevertWhen_ReleaseTwice() public {
        _fundAndApprove();
        vm.prank(seller);
        escrow.release();

        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowStateMachineFixed.WrongState.selector,
                EscrowStateMachineFixed.State.ReleaseApproved,
                EscrowStateMachineFixed.State.Released
            )
        );
        vm.prank(seller);
        escrow.release();

        assertEq(seller.balance, PRICE, "il seller non deve ricevere piu' del prezzo");
    }

    // Se il seller rifiuta l'ETH, il revert annulla tutto: lo stato torna ReleaseApproved
    // e i fondi restano nell'Escrow.
    function test_RevertWhen_SellerRejectsEther() public {
        RejectingSeller rejecting = new RejectingSeller();
        vm.prank(buyer);
        EscrowStateMachineFixed rejectingEscrow =
            new EscrowStateMachineFixed(address(rejecting), PRICE);

        vm.startPrank(buyer);
        rejectingEscrow.fund{ value: PRICE }();
        rejectingEscrow.approveRelease();
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowStateMachineFixed.EtherTransferFailed.selector, address(rejecting), PRICE
            )
        );
        rejecting.callRelease(rejectingEscrow);

        assertEq(
            uint256(rejectingEscrow.state()),
            uint256(EscrowStateMachineFixed.State.ReleaseApproved),
            "lo stato deve tornare ReleaseApproved"
        );
        assertEq(address(rejectingEscrow).balance, PRICE, "l'ETH deve restare nel contratto");
    }

    function _fundAndApprove() internal {
        vm.startPrank(buyer);
        escrow.fund{ value: PRICE }();
        escrow.approveRelease();
        vm.stopPrank();
    }

    function _assertState(EscrowStateMachineFixed.State expected) internal view {
        assertEq(uint256(escrow.state()), uint256(expected));
    }
}
