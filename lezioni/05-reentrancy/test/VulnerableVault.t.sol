// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode e helper usati in questo file:
//   makeAddr("nome")    indirizzo deterministico con etichetta leggibile nelle trace;
//   vm.deal(a, x)       assegna x wei all'indirizzo a;
//   vm.prank(a)         la PROSSIMA call avra' msg.sender = a;
//   vm.expectRevert(e)  la PROSSIMA call deve revertire con l'errore e.
// Per vedere i frame annidati withdraw -> receive -> withdraw:
//   forge test --match-test test_DemonstratesReentrantCallbackBreakingAccounting -vvvv
import { Test } from "forge-std/Test.sol";
import { VulnerableVault } from "../src/reentrancy/VulnerableVault.sol";
import { IVault, LocalReentrantReceiver } from "./helpers/ReentrancyReceivers.sol";

contract VulnerableVaultTest is Test {
    VulnerableVault internal vault;

    address internal alice;
    address internal bob;

    function setUp() public {
        vault = new VulnerableVault();
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    // Caso d'uso onesto: il vault vulnerabile funziona con un utente normale (un EOA non
    // esegue codice quando riceve ETH). Il bug si vede solo con un receiver che rientra.
    function test_NormalWithdrawWorks() public {
        // ARRANGE
        vm.prank(alice);
        vault.deposit{ value: 1 ether }();
        uint256 aliceBalanceBefore = alice.balance;

        // ACT
        vm.prank(alice);
        vault.withdraw();

        // ASSERT
        assertEq(vault.credit(alice), 0);
        assertEq(alice.balance, aliceBalanceBefore + 1 ether);
        assertEq(address(vault).balance, 0);
        assertEq(vault.totalCredits(), 0);
    }

    /// @dev Il test passa dimostrando che il contratto vulnerabile diventa insolvente.
    /// Se un giorno diventasse rosso, vorrebbe dire che il vault non e' piu' vulnerabile.
    function test_DemonstratesReentrantCallbackBreakingAccounting() public {
        // ARRANGE: quattro utenti onesti depositano 1 ETH ciascuno. Sono i fondi a rischio.
        address[4] memory users = [makeAddr("u1"), makeAddr("u2"), makeAddr("u3"), makeAddr("u4")];

        for (uint256 i = 0; i < users.length; i++) {
            vm.deal(users[i], 1 ether);
            vm.prank(users[i]);
            vault.deposit{ value: 1 ether }();
        }

        // Il receiver rientra al massimo 4 volte.
        LocalReentrantReceiver receiver = new LocalReentrantReceiver(IVault(address(vault)), 4);

        // Il receiver deposita 1 ETH: il suo credito LEGITTIMO e' di 1 ETH, non di piu'.
        vm.deal(address(this), 1 ether);
        receiver.depositIntoVault{ value: 1 ether }();

        // Fotografia prima dell'attacco: 5 ETH nel vault, tutti coperti da crediti.
        assertEq(address(vault).balance, 5 ether);
        assertEq(vault.credit(address(receiver)), 1 ether);
        assertEq(vault.totalCredits(), 5 ether);

        // ACT: un solo withdraw iniziale, poi 4 rientri dalla receive().
        receiver.startWithdrawal();

        // ASSERT: il receiver ha incassato piu' del suo credito e il vault e' vuoto.
        assertGt(address(receiver).balance, 1 ether, "lo stesso credito e' stato riutilizzato");
        assertEq(address(vault).balance, 0);

        // Somma indipendente dei crediti degli onesti: non ci si fida di totalCredits,
        // che e' proprio il dato corrotto dall'attacco.
        uint256 honestLiabilities;
        for (uint256 i = 0; i < users.length; i++) {
            honestLiabilities += vault.credit(users[i]);
        }

        // I crediti individuali promettono ancora 4 ETH, ma il vault e' vuoto.
        assertEq(honestLiabilities, 4 ether);
        assertGt(honestLiabilities, address(vault).balance, "liabilities > assets");

        // Anche l'aggregato e' stato corrotto dai decrementi ripetuti durante l'unwind.
        // Cinque frame hanno sottratto 1 ETH ciascuno da 5 ETH: totalCredits dice 0, ma
        // gli utenti onesti hanno ancora 4 ETH di crediti.
        assertEq(vault.totalCredits(), 0);
        assertNotEq(vault.totalCredits(), honestLiabilities);
    }

    // TEST NEGATIVI: le guardie di base funzionano anche nella versione vulnerabile.
    // Il bug non e' un controllo mancante, e' l'ordine delle operazioni.
    function test_RevertWhen_DepositIsZero() public {
        vm.expectRevert(VulnerableVault.ZeroDeposit.selector);
        vm.prank(alice);
        vault.deposit(); // senza {value: ...} msg.value e' 0
    }

    function test_RevertWhen_NoCredit() public {
        vm.expectRevert(VulnerableVault.NoCredit.selector);
        vm.prank(alice);
        vault.withdraw();
    }

    // Due withdraw in SEQUENZA (due call separate) sono bloccati correttamente: quando parte
    // il secondo, il primo ha gia' azzerato il credito. Il problema nasce solo con call
    // ANNIDATE, cioe' un withdraw che parte mentre il precedente e' ancora in corso.
    function test_RevertWhen_WithdrawnTwiceSequentially() public {
        vm.prank(alice);
        vault.deposit{ value: 1 ether }();

        vm.prank(alice);
        vault.withdraw();

        vm.expectRevert(VulnerableVault.NoCredit.selector);
        vm.prank(alice);
        vault.withdraw();
    }
}
