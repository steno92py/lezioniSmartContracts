// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode usati in questo file:
//   makeAddr("nome")             indirizzo deterministico ed etichettato nelle trace;
//   vm.prank(a)                  la PROSSIMA call avra' msg.sender = a;
//   vm.startPrank / stopPrank    come prank, ma per TUTTE le call fino a stopPrank;
//   vm.expectRevert(e)           la PROSSIMA call deve revertire con l'errore e;
//   vm.expectEmit(...)           la PROSSIMA call deve emettere l'evento indicato.
import { Test } from "forge-std/Test.sol";
import { INotifier } from "../src/interfaces/INotifier.sol";
import { NotificationEscrow } from "../src/NotificationEscrow.sol";
import { GoodNotifier } from "../src/mocks/GoodNotifier.sol";
import { RevertingNotifier } from "../src/mocks/RevertingNotifier.sol";

contract NotificationEscrowTest is Test {
    // Copia locale della dichiarazione dell'evento: serve a scrivere `emit` come modello
    // atteso da vm.expectEmit.
    event NotificationFailed(address indexed notifier, bytes reason);

    address internal buyer;
    address internal seller;
    address internal stranger;

    function setUp() public {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        stranger = makeAddr("stranger");
    }

    // Percorso felice: release riuscita e notifier chiamato con gli argomenti giusti.
    function test_ReleaseSucceedsWithNotifier() public {
        GoodNotifier notifier = new GoodNotifier();
        NotificationEscrow escrow = _newEscrow(INotifier(address(notifier)));

        vm.prank(buyer);
        escrow.release();

        assertTrue(escrow.released());
        assertTrue(notifier.called());
        assertEq(notifier.notifiedSeller(), seller);
        assertEq(notifier.notifiedAmount(), 100);
    }

    // Il test centrale: il notifier reverte, ma la release riesce lo stesso E il fallimento
    // resta visibile nell'evento.
    function test_NotifierFailureIsObservableButDoesNotBlockRelease() public {
        RevertingNotifier notifier = new RevertingNotifier();
        NotificationEscrow escrow = _newEscrow(INotifier(address(notifier)));
        // Il `reason` catturato dal catch e' l'errore codificato: qui solo il selector di Nope.
        bytes memory reason = abi.encodeWithSelector(RevertingNotifier.Nope.selector);

        // (true, false, false, true): confronta il primo campo indexed (notifier) e i dati
        // non indicizzati (reason); gli altri due topic non esistono per questo evento.
        vm.expectEmit(true, false, false, true, address(escrow));
        emit NotificationFailed(address(notifier), reason);

        vm.prank(buyer);
        escrow.release();

        assertTrue(escrow.released());
    }

    function test_RevertWhen_StrangerReleases() public {
        GoodNotifier notifier = new GoodNotifier();
        NotificationEscrow escrow = _newEscrow(INotifier(address(notifier)));

        vm.expectRevert(abi.encodeWithSelector(NotificationEscrow.OnlyBuyer.selector, stranger));
        vm.prank(stranger);
        escrow.release();

        // Il revert avviene prima della call esterna: il notifier non e' mai stato toccato.
        assertFalse(escrow.released());
        assertFalse(notifier.called());
    }

    function test_RevertWhen_ReleasingTwice() public {
        GoodNotifier notifier = new GoodNotifier();
        NotificationEscrow escrow = _newEscrow(INotifier(address(notifier)));

        // startPrank: entrambe le release partono dal buyer. Nota l'ordine: expectRevert
        // subito prima della call che deve fallire, cioe' la seconda.
        vm.startPrank(buyer);
        escrow.release();
        vm.expectRevert(NotificationEscrow.AlreadyReleased.selector);
        escrow.release();
        vm.stopPrank();

        assertTrue(escrow.released());
    }

    // Anche il constructor va testato: `stranger` e' un EOA, quindi non ha codice.
    function test_RevertWhen_NotifierHasNoCode() public {
        vm.expectRevert(
            abi.encodeWithSelector(NotificationEscrow.InvalidNotifier.selector, stranger)
        );
        new NotificationEscrow(INotifier(stranger), buyer, seller, 100);
    }

    function _newEscrow(INotifier notifier) internal returns (NotificationEscrow) {
        return new NotificationEscrow(notifier, buyer, seller, 100);
    }
}
