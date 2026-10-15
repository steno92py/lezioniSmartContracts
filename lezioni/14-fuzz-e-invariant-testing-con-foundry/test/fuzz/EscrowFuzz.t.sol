// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// FUZZ TEST: un test con parametri. Foundry lo esegue molte volte (runs = 256 in
// foundry.toml) con valori generati per quei parametri, anche casi limite come 0 e max.
// Se un run fallisce, stampa il controesempio e lo riduce a un input piu' semplice.
// Il prefisso testFuzz_ e' una convenzione: a rendere fuzz il test sono i parametri.
// Strumenti per restringere gli input al dominio che interessa:
//   bound(x, min, max)  RIMAPPA x dentro [min, max]: nessun run viene sprecato;
//   vm.assume(cond)     SCARTA il run se cond e' falsa. Utile per escludere pochi valori
//                       puntuali (un indirizzo); se scarta troppo il test fallisce.
import {Test} from "forge-std/Test.sol";
import {SimpleEscrow} from "../../src/fuzz/FuzzTargets.sol";

contract EscrowFuzzTest is Test {
    SimpleEscrow internal escrow;
    address internal buyer;

    function setUp() public {
        buyer = makeAddr("buyer");
        escrow = new SimpleEscrow(buyer);
    }

    // Proprieta': QUALSIASI importo valido viene registrato esattamente.
    // Il dominio parte da 1 perche' 0 e' un input invalido, provato a parte.
    function testFuzz_DepositRecordsEveryValidAmount(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 1, type(uint128).max);

        vm.prank(buyer);
        escrow.deposit(amount);

        assertEq(escrow.escrowedAmount(), amount);
        assertTrue(escrow.funded());
    }

    // Anche il chiamante e' fuzzato. assume e' la scelta giusta qui: bisogna escludere
    // un solo indirizzo (buyer), cosa che bound non sa esprimere.
    function testFuzz_NonBuyerCannotDeposit(address caller, uint256 rawAmount) public {
        vm.assume(caller != buyer);
        vm.assume(caller != address(0));
        uint256 amount = bound(rawAmount, 1, type(uint128).max);

        vm.expectRevert(abi.encodeWithSelector(SimpleEscrow.OnlyBuyer.selector, caller));
        vm.prank(caller);
        escrow.deposit(amount);

        // Test negativo: dopo il revert lo stato deve essere intatto.
        assertFalse(escrow.funded());
        assertEq(escrow.escrowedAmount(), 0);
    }

    // Input con due difetti (caller sbagliato, amount zero): l'errore deve essere OnlyBuyer,
    // per qualunque caller. Fissa l'ordine dei controlli nel contratto.
    function testFuzz_AuthorizationCheckPrecedesAmountValidation(address caller) public {
        vm.assume(caller != buyer);
        vm.assume(caller != address(0));

        vm.expectRevert(abi.encodeWithSelector(SimpleEscrow.OnlyBuyer.selector, caller));
        vm.prank(caller);
        escrow.deposit(0);
    }

    // Due parametri fuzzati: nessuna coppia di importi validi permette un secondo deposito.
    function testFuzz_SecondDepositAlwaysFails(uint128 firstAmount, uint128 secondAmount) public {
        uint256 first = bound(firstAmount, 1, type(uint128).max);
        uint256 second = bound(secondAmount, 1, type(uint128).max);
        vm.prank(buyer);
        escrow.deposit(first);

        vm.expectRevert(SimpleEscrow.AlreadyFunded.selector);
        vm.prank(buyer);
        escrow.deposit(second);

        assertEq(escrow.escrowedAmount(), first); // il primo importo non e' sovrascritto
    }

    // Il caso zero resta un test deterministico: il fuzzer PUO' generare 0, ma nulla lo
    // garantisce. Un caso importante non si affida alla fortuna.
    function test_Regression_ZeroDepositUsesExactError() public {
        vm.expectRevert(SimpleEscrow.ZeroAmount.selector);
        vm.prank(buyer);
        escrow.deposit(0);
    }
}

