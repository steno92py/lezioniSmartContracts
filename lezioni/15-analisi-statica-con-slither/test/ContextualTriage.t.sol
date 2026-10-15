// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode: vedi la legenda in NoisyFindings.t.sol.
// ST-05 non e' un finding confermato: questi test sono l'EVIDENZA del triage. Non provano
// una sicurezza universale, ma che nel modello attuale la callback non ripete finish().
import {Test} from "forge-std/Test.sol";
import {NotifierFlow} from "../src/context/NotifierFlow.sol";
import {OneShotCallbackNotifier} from "../src/mocks/StaticMocks.sol";

contract ContextualTriageTest is Test {
    function test_CallbackCannotRepeatTerminalTransition() public {
        // ARRANGE: flow conosce notifier (constructor), notifier conosce flow (configure).
        OneShotCallbackNotifier notifier = new OneShotCallbackNotifier();
        NotifierFlow flow = new NotifierFlow(notifier);
        notifier.configure(flow);

        // ACT:  test --finish()--> flow --notify()--> notifier --finish()--> flow (AlreadyDone)
        flow.finish();

        assertTrue(flow.done());
        // La callback c'e' stata (tentativo registrato) ma e' fallita: niente doppia transizione.
        assertTrue(notifier.callbackAttempted());
        assertFalse(notifier.callbackSucceeded());
    }

    function test_SecondFinishUsesExactTerminalError() public {
        OneShotCallbackNotifier notifier = new OneShotCallbackNotifier();
        NotifierFlow flow = new NotifierFlow(notifier);
        notifier.configure(flow);
        flow.finish();

        // Verifica il MOTIVO preciso: un revert qualunque potrebbe nascondere un altro guasto.
        vm.expectRevert(NotifierFlow.AlreadyDone.selector);
        flow.finish();
        assertTrue(flow.done());
    }
}
