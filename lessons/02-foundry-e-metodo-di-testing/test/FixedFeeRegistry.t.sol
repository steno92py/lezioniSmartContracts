// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Test e' la base di forge-std: fornisce gli assert (assertEq, assertTrue...) e `vm`,
// l'oggetto dei cheatcode di Foundry. Cheatcode usati in questo file:
//   vm.deal(a, x)       assegna x wei all'indirizzo a, dal nulla;
//   vm.prank(a)         la PROSSIMA call avra' msg.sender = a;
//   vm.expectRevert(e)  la PROSSIMA call deve revertire con l'errore e, altrimenti il test
//                       fallisce;
//   vm.expectEmit(...)  la PROSSIMA call deve emettere l'evento indicato.
// I cheatcode esistono solo nel laboratorio: sulla blockchain vera nessuno puo' usarli.
import { Test } from "forge-std/Test.sol";
import { FixedFeeRegistry } from "../src/FixedFeeRegistry.sol";

contract FixedFeeRegistryTest is Test {
    FixedFeeRegistry internal registry;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    // Copia locale della fee: il test dichiara da solo il valore atteso, invece di fidarsi
    // del contratto sotto test.
    uint256 internal constant FEE = 1 ether;

    // setUp() viene eseguita prima di OGNI test: ogni test parte da uno stato pulito
    // e non dipende dall'ordine in cui i test vengono eseguiti.
    function setUp() public {
        registry = new FixedFeeRegistry();

        vm.deal(ALICE, 10 ether);
        vm.deal(BOB, 10 ether);
    }

    // `view`: questo test legge soltanto. Fissa il punto di partenza dei test successivi.
    function test_InitialState() public view {
        assertFalse(registry.registered(ALICE));
        assertFalse(registry.registered(BOB));
        assertEq(registry.registrationCount(), 0);
        assertEq(registry.totalReceived(), 0);
        assertEq(registry.REGISTRATION_FEE(), FEE);
    }

    // TEST POSITIVO (happy path): l'uso previsto dal requisito deve funzionare.
    // Schema di ogni test: ARRANGE (prepara), ACT (esegui la call), ASSERT (verifica).
    function test_Register_SucceedsWithExactFee() public {
        // Arrange: setUp ha creato il registry e finanziato ALICE.

        // Act
        // {value: FEE} imposta il msg.value della call.
        vm.prank(ALICE);
        registry.register{ value: FEE }();

        // Assert
        assertTrue(registry.registered(ALICE));
        assertEq(registry.registrationCount(), 1);
        assertEq(registry.totalReceived(), FEE);
        _assertAccountingProperty();
    }

    function test_Register_EmitsRegisteredEvent() public {
        // I flag dicono cosa confrontare: 1 = primo campo indexed (account), 2 e 3 = altri
        // campi indexed (qui non ce ne sono), 4 = dati non indicizzati (amount).
        // L'ultimo argomento e' il contratto che deve emettere l'evento.
        vm.expectEmit(true, false, false, true, address(registry));
        // Questo emit non e' reale: e' il "modello" dell'evento atteso.
        emit FixedFeeRegistry.Registered(ALICE, FEE);

        vm.prank(ALICE);
        registry.register{ value: FEE }();
    }

    // Identita' indipendenti: la registrazione di ALICE non deve registrare BOB
    // ne' impedirgli di registrarsi.
    function test_Register_TwoDifferentAccountsRemainIndependent() public {
        vm.prank(ALICE);
        registry.register{ value: FEE }();

        // Controllo intermedio: dopo ALICE, BOB e' ancora libero.
        assertTrue(registry.registered(ALICE));
        assertFalse(registry.registered(BOB));

        vm.prank(BOB);
        registry.register{ value: FEE }();

        assertTrue(registry.registered(ALICE));
        assertTrue(registry.registered(BOB));
        assertEq(registry.registrationCount(), 2);
        assertEq(registry.totalReceived(), 2 * FEE);
        _assertAccountingProperty();
    }

    // TEST NEGATIVI sulla fee: tre importi sbagliati, uno per ogni lato del confine.
    // zero e meno della fee sono rifiutati anche da un controllo `<`; solo "troppo alta"
    // distingue la fee ESATTA da una fee MINIMA.
    function test_RevertWhen_FeeIsZero() public {
        _expectWrongFeeAndAssertUnchanged(0);
    }

    function test_RevertWhen_FeeIsTooLow() public {
        _expectWrongFeeAndAssertUnchanged(0.5 ether);
    }

    // TEST DI REGRESSIONE: fissa un bug plausibile, cosi' che non possa tornare inosservato.
    /// @dev Regression test per la mutazione `msg.value < REGISTRATION_FEE`.
    function test_RevertWhen_FeeIsTooHigh() public {
        _expectWrongFeeAndAssertUnchanged(2 ether);
    }

    function test_RevertWhen_AccountRegistersTwice() public {
        // Arrange: ALICE e' gia' registrata; si fotografano i saldi prima del secondo tentativo.
        vm.prank(ALICE);
        registry.register{ value: FEE }();

        uint256 aliceBalanceBefore = ALICE.balance;
        uint256 registryBalanceBefore = address(registry).balance;

        // Act: errore PRECISO, con selettore e argomento (ALICE). Un expectRevert() generico
        // passerebbe con qualunque revert, anche uno dovuto a un motivo diverso.
        vm.expectRevert(abi.encodeWithSelector(FixedFeeRegistry.AlreadyRegistered.selector, ALICE));
        vm.prank(ALICE);
        registry.register{ value: FEE }();

        // Assert: lo stato e' quello di una sola registrazione e l'ETH della call fallita
        // e' tornato ad ALICE. Non basta che la call fallisca: conta cosa resta dopo.
        assertTrue(registry.registered(ALICE));
        assertEq(registry.registrationCount(), 1);
        assertEq(registry.totalReceived(), FEE);
        assertEq(ALICE.balance, aliceBalanceBefore, "la call fallita non deve spendere la fee");
        assertEq(address(registry).balance, registryBalanceBefore);
        _assertAccountingProperty();
    }

    // Helper condiviso dai test sulla fee sbagliata. `internal`: non e' un test (non inizia
    // con test_), lo chiamano gli altri test. Un solo helper = stessi controlli per ogni caso.
    function _expectWrongFeeAndAssertUnchanged(uint256 sent) internal {
        uint256 aliceBalanceBefore = ALICE.balance;
        uint256 registryBalanceBefore = address(registry).balance;

        // L'errore atteso contiene i due valori: quanto e' stato inviato e quanto serviva.
        vm.expectRevert(
            abi.encodeWithSelector(FixedFeeRegistry.ExactFeeRequired.selector, sent, FEE)
        );
        vm.prank(ALICE);
        registry.register{ value: sent }();

        // Revert atomico: nessuna scrittura parziale, nessun ETH trattenuto.
        assertFalse(registry.registered(ALICE));
        assertEq(registry.registrationCount(), 0);
        assertEq(registry.totalReceived(), 0);
        assertEq(ALICE.balance, aliceBalanceBefore, "il revert deve ripristinare il saldo");
        assertEq(address(registry).balance, registryBalanceBefore);
        _assertAccountingProperty();
    }

    // La proprieta' contabile, verificata dopo ogni scenario.
    // Si confronta con la contabilita' interna, non con address(registry).balance: l'ETH
    // puo' arrivare a un indirizzo anche per vie che non passano da register().
    function _assertAccountingProperty() internal view {
        assertEq(registry.totalReceived(), registry.registrationCount() * FEE);
    }
}
