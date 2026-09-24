// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode e helper usati in questo file:
//   makeAddr("nome")    indirizzo deterministico con etichetta leggibile nelle trace;
//   vm.prank(a)         la PROSSIMA call avra' msg.sender = a;
//   vm.startPrank(a)    TUTTE le call successive avranno msg.sender = a...
//   vm.stopPrank()      ...fino a questo punto;
//   vm.expectRevert(e)  la PROSSIMA call deve revertire con l'errore e.
// Regola della lezione: per ogni privilegio almeno un test positivo (chi deve poter
// chiamare ci riesce) e uno negativo (chi non deve, viene respinto e lo stato non cambia).
import { Test } from "forge-std/Test.sol";
import { EscrowAdminVulnerable } from "../src/access/EscrowAdminVulnerable.sol";
import { EscrowAdmin } from "../src/access/EscrowAdmin.sol";

contract AccessControlTest is Test {
    // Un attore per ogni colonna della permission matrix del README.
    address internal buyer;
    address internal seller;
    address internal admin;
    address internal stranger;

    EscrowAdminVulnerable internal vulnerable;
    EscrowAdmin internal secureEscrow;

    function setUp() public {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        admin = makeAddr("admin");
        stranger = makeAddr("stranger");

        // Stessi attori per le due versioni: i test le confrontano a parita' di condizioni.
        vulnerable = new EscrowAdminVulnerable(buyer, seller, admin);
        secureEscrow = new EscrowAdmin(buyer, seller, admin);
    }

    /// @dev Il test passa dimostrando che il ruolo dichiarato non viene applicato.
    function test_Vulnerable_StrangerCanPause() public {
        assertFalse(vulnerable.paused());

        // Uno stranger qualunque, senza alcun ruolo...
        vm.prank(stranger);
        vulnerable.setPaused(true);

        // ...riesce a cambiare lo stato: e' il bug.
        assertTrue(vulnerable.paused());
    }

    // Test positivo: l'admin puo' usare il privilegio in entrambe le direzioni.
    function test_AdminCanPauseAndUnpause() public {
        vm.startPrank(admin);
        secureEscrow.setPaused(true);
        assertTrue(secureEscrow.paused()); // anche questo getter gira con msg.sender = admin

        secureEscrow.setPaused(false);
        vm.stopPrank();

        assertFalse(secureEscrow.paused());
    }

    // Regression test del bug: lo stesso attacco sulla versione corretta deve fallire.
    function test_RevertWhen_StrangerTriesToPause() public {
        _expectUnauthorized(stranger);
        assertFalse(secureEscrow.paused());
    }

    // Buyer e seller hanno un ruolo nell'escrow, ma non quello amministrativo:
    // essere "qualcuno" nel contratto non da' privilegi impliciti.
    function test_BuyerIsNotImplicitlyAdmin() public {
        _expectUnauthorized(buyer);
    }

    function test_SellerIsNotImplicitlyAdmin() public {
        _expectUnauthorized(seller);
    }

    // `new` e' anch'essa una call: expectRevert si applica al deploy.
    function test_RevertWhen_ConstructorReceivesZeroAddress() public {
        vm.expectRevert(EscrowAdmin.ZeroAddress.selector);
        new EscrowAdmin(address(0), seller, admin);
    }

    // Helper per i test negativi: verifica errore, parametro (chi ha chiamato) e stato invariato.
    function _expectUnauthorized(address caller) internal {
        // Errore con parametro: si confrontano selettore E indirizzo del chiamante respinto.
        vm.expectRevert(abi.encodeWithSelector(EscrowAdmin.Unauthorized.selector, caller));
        vm.prank(caller);
        secureEscrow.setPaused(true);

        assertFalse(secureEscrow.paused());
    }
}
