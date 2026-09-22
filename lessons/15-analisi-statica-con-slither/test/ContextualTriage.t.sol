// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {NotifierFlow} from "../src/context/NotifierFlow.sol";
import {OneShotCallbackNotifier} from "../src/mocks/StaticMocks.sol";

contract ContextualTriageTest is Test {
    function test_CallbackCannotRepeatTerminalTransition() public {
        OneShotCallbackNotifier notifier = new OneShotCallbackNotifier();
        NotifierFlow flow = new NotifierFlow(notifier);
        notifier.configure(flow);

        flow.finish();

        assertTrue(flow.done());
        assertTrue(notifier.callbackAttempted());
        assertFalse(notifier.callbackSucceeded());
    }

    function test_SecondFinishUsesExactTerminalError() public {
        OneShotCallbackNotifier notifier = new OneShotCallbackNotifier();
        NotifierFlow flow = new NotifierFlow(notifier);
        notifier.configure(flow);
        flow.finish();

        vm.expectRevert(NotifierFlow.AlreadyDone.selector);
        flow.finish();
        assertTrue(flow.done());
    }
}

