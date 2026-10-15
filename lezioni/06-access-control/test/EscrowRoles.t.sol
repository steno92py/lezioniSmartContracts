// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode e helper: makeAddr, vm.prank, vm.expectRevert (legenda in AccessControl.t.sol).
//
// Insidia di questo file: un getter come escrow.PAUSER_ROLE() e' una external call.
//   vm.prank(x); escrow.grantRole(escrow.PAUSER_ROLE(), y);
// Qui il prank verrebbe consumato dal getter, e grantRole partirebbe con il msg.sender
// sbagliato. Percio' i role ID si leggono PRIMA di vm.prank, oppure dentro gli argomenti di
// vm.expectRevert, che vengono calcolati prima che il prank sia attivo.
import { Test } from "forge-std/Test.sol";
import { EscrowRoles } from "../src/access/EscrowRoles.sol";

contract EscrowRolesTest is Test {
    address internal admin;
    address internal pauser;
    address internal arbiter;
    address internal stranger;

    EscrowRoles internal escrow;

    function setUp() public {
        admin = makeAddr("admin");
        pauser = makeAddr("pauser");
        arbiter = makeAddr("arbiter");
        stranger = makeAddr("stranger");
        escrow = new EscrowRoles(admin, pauser, arbiter);
    }

    // `view`: il test legge soltanto, senza modificare lo stato.
    // Fotografia della permission matrix subito dopo il deploy: chi ha quale ruolo, e chi no.
    function test_InitialPermissionMatrix() public view {
        assertTrue(escrow.hasRole(escrow.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(escrow.hasRole(escrow.PAUSER_ROLE(), pauser));
        assertTrue(escrow.hasRole(escrow.ARBITER_ROLE(), arbiter));

        // Le celle "no" contano quanto le celle "si'".
        assertFalse(escrow.hasRole(escrow.PAUSER_ROLE(), admin));
        assertFalse(escrow.hasRole(escrow.ARBITER_ROLE(), pauser));
        assertEq(escrow.getRoleAdmin(escrow.PAUSER_ROLE()), escrow.DEFAULT_ADMIN_ROLE());
    }

    // Separazione dei ruoli: ogni ruolo sblocca la sua operazione e non quella dell'altro.
    function test_PauserCanPauseButCannotResolveDispute() public {
        vm.prank(pauser);
        escrow.setPaused(true);
        assertTrue(escrow.paused());

        vm.expectRevert(
            abi.encodeWithSelector(EscrowRoles.MissingRole.selector, pauser, escrow.ARBITER_ROLE())
        );
        vm.prank(pauser);
        escrow.resolveDispute();
    }

    function test_ArbiterCanResolveButCannotPause() public {
        vm.prank(arbiter);
        escrow.resolveDispute();
        assertTrue(escrow.disputeResolved());

        vm.expectRevert(
            abi.encodeWithSelector(EscrowRoles.MissingRole.selector, arbiter, escrow.PAUSER_ROLE())
        );
        vm.prank(arbiter);
        escrow.setPaused(true);
    }

    // Ciclo di vita completo di un ruolo: concesso -> usato -> revocato -> non piu' usabile.
    function test_AdminCanGrantAndRevokeRole() public {
        // I getter sono external calls: li valutiamo prima del prank one-shot.
        bytes32 pauserRole = escrow.PAUSER_ROLE();

        vm.prank(admin);
        escrow.grantRole(pauserRole, stranger);

        vm.prank(stranger);
        escrow.setPaused(true);
        assertTrue(escrow.paused());

        vm.prank(admin);
        escrow.revokeRole(pauserRole, stranger);

        // Dopo la revoca il privilegio deve sparire davvero, non solo sulla carta.
        vm.expectRevert(
            abi.encodeWithSelector(EscrowRoles.MissingRole.selector, stranger, pauserRole)
        );
        vm.prank(stranger);
        escrow.setPaused(false);
    }

    // Least privilege: amministrare un ruolo non significa possederlo.
    function test_AdminDoesNotImplicitlyHaveOperationalRoles() public {
        vm.expectRevert(
            abi.encodeWithSelector(EscrowRoles.MissingRole.selector, admin, escrow.PAUSER_ROLE())
        );
        vm.prank(admin);
        escrow.setPaused(true);
    }

    // Possedere un ruolo non significa poterlo concedere: il pauser non amministra nulla.
    function test_RevertWhen_NonAdminGrantsRole() public {
        bytes32 arbiterRole = escrow.ARBITER_ROLE();
        bytes32 adminRole = escrow.DEFAULT_ADMIN_ROLE();

        // L'errore riporta il ruolo MANCANTE: quello admin, non ARBITER_ROLE.
        vm.expectRevert(abi.encodeWithSelector(EscrowRoles.MissingRole.selector, pauser, adminRole));
        vm.prank(pauser);
        escrow.grantRole(arbiterRole, stranger);

        assertFalse(escrow.hasRole(arbiterRole, stranger));
    }
}
