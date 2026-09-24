// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode e helper usati in questo file:
//   makeAddr("nome")    indirizzo deterministico ed etichettato nelle trace; NON ha codice;
//   vm.expectRevert(e)  la PROSSIMA call deve revertire con l'errore e.
// Per vedere la catena delle call: forge test --match-contract LowLevelCallsTest -vvvv
import { Test } from "forge-std/Test.sol";
import { CallUtilsLite } from "../src/utils/CallUtilsLite.sol";
import { UncheckedDependency } from "../src/UncheckedDependency.sol";
import { CheckedDependency } from "../src/CheckedDependency.sol";
import { GoodDependency, RevertingDependency } from "../src/mocks/ActionDependencies.sol";

contract LowLevelCallsTest is Test {
    // I due test Vulnerable_ PASSANO perche' l'attacco riesce: documentano il bug.

    /// @dev Il test passa dimostrando che il caller registra un successo inesistente.
    function test_Vulnerable_RevertCreatesFalseSuccess() public {
        UncheckedDependency consumer = new UncheckedDependency();
        RevertingDependency dependency = new RevertingDependency();

        // abi.encodeCall(f, (args)) costruisce la calldata di f controllando i tipi degli
        // argomenti a compile time. Qui execute() non ha argomenti: ().
        // Nessun expectRevert: la dipendenza reverte, ma run() NON reverte.
        consumer.run(address(dependency), abi.encodeCall(dependency.execute, ()));

        assertTrue(consumer.completed());
    }

    /// @dev Una low-level call verso un EOA puo' restituire true pur non eseguendo codice.
    function test_Vulnerable_NoCodeStillCreatesFalseSuccess() public {
        UncheckedDependency consumer = new UncheckedDependency();

        // hex"" = calldata vuota. Il target e' un indirizzo senza codice.
        consumer.run(makeAddr("empty-target"), hex"");

        assertTrue(consumer.completed());
    }

    // Da qui la versione corretta: stessi scenari, esito opposto.

    function test_CheckedCallCompletesOnlyAfterDependencyRuns() public {
        CheckedDependency consumer = new CheckedDependency();
        GoodDependency dependency = new GoodDependency();

        bytes memory result =
            consumer.run(address(dependency), abi.encodeCall(dependency.execute, ()));

        // La dipendenza e' stata eseguita davvero, e il return value arriva come bytes:
        // abi.decode lo riconverte nel tipo atteso.
        assertTrue(dependency.executed());
        assertTrue(consumer.completed());
        assertEq(abi.decode(result, (uint256)), 42);
    }

    function test_CheckedCallBubblesRevertAndKeepsState() public {
        CheckedDependency consumer = new CheckedDependency();
        RevertingDependency dependency = new RevertingDependency();

        // Revert bubbling: si attende l'errore ORIGINALE della dipendenza, non CallFailed.
        vm.expectRevert(RevertingDependency.DependencyFailure.selector);
        consumer.run(address(dependency), abi.encodeCall(dependency.execute, ()));

        // Regressione del primo test vulnerabile: nessun falso successo.
        assertFalse(consumer.completed());
    }

    function test_CheckedCallRejectsTargetWithoutCode() public {
        CheckedDependency consumer = new CheckedDependency();
        address emptyTarget = makeAddr("empty-target");

        // Regressione del secondo test vulnerabile: il code check blocca l'EOA.
        vm.expectRevert(abi.encodeWithSelector(CallUtilsLite.TargetHasNoCode.selector, emptyTarget));
        consumer.run(emptyTarget, hex"");

        assertFalse(consumer.completed());
    }

    function test_RevertWhen_CheckedCallRunsTwice() public {
        CheckedDependency consumer = new CheckedDependency();
        GoodDependency dependency = new GoodDependency();
        bytes memory data = abi.encodeCall(dependency.execute, ());

        // Prima esecuzione valida, seconda rifiutata.
        consumer.run(address(dependency), data);

        vm.expectRevert(CheckedDependency.AlreadyCompleted.selector);
        consumer.run(address(dependency), data);
    }
}
