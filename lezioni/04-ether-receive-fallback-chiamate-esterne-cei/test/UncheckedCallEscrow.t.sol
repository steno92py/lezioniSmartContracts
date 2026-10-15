// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { UncheckedCallEscrow } from "../src/labs/UncheckedCallEscrow.sol";
import { RejectingSeller } from "./helpers/EtherReceivers.sol";

// Laboratorio: riproduce il difetto di UncheckedCallEscrow con un seller che rifiuta ETH.
// Per seguire la call nella trace: forge test --match-contract UncheckedCallEscrowTest -vvvv
contract UncheckedCallEscrowTest is Test {
    address internal buyer;
    uint256 internal constant PRICE = 5 ether;

    function setUp() public {
        buyer = makeAddr("buyer");
        vm.deal(buyer, 100 ether);
    }

    /// @dev Il test passa dimostrando che una transaction riuscita puo' mentire sul payout.
    // Il test PASSA: il verde documenta il bug, non la correttezza del contratto.
    // Il confronto corretto e' test_RejectingSellerMakesReleaseRevertAtomically.
    function test_DemonstratesFalseReleasedStateAfterFailedPayout() public {
        // Arrange: seller che rifiuta ogni ETH, Escrow finanziato dal buyer.
        RejectingSeller receiver = new RejectingSeller();

        vm.prank(buyer);
        UncheckedCallEscrow broken = new UncheckedCallEscrow(payable(address(receiver)), PRICE);

        vm.prank(buyer);
        broken.fund{ value: PRICE }();

        // Act: nessun expectRevert, e infatti release() NON reverte.
        vm.prank(buyer);
        broken.release();

        // Assert: tre fatti incompatibili tra loro in un Escrow corretto.

        assertEq(uint256(broken.state()), uint256(UncheckedCallEscrow.State.Released)); // "pagato"
        assertEq(address(receiver).balance, 0); // ma il seller non ha ricevuto nulla
        assertEq(address(broken).balance, PRICE); // e i fondi restano bloccati nel contratto
    }
}

