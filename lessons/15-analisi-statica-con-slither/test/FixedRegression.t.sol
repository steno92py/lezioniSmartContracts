// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode: vedi la legenda in NoisyFindings.t.sol.
// Ogni finding confermato lascia qui un test di REGRESSIONE: la proprieta' che il fix
// garantisce. Se una modifica futura reintroduce il bug, il test corrispondente diventa rosso.
import {Test} from "forge-std/Test.sol";
import {SafeStaticLab, IStaticAction} from "../src/fixed/SafeStaticLab.sol";
import {RecordingAction, RevertingAction} from "../src/mocks/StaticMocks.sol";

contract FixedRegressionTest is Test {
    address internal admin;
    address internal candidate;
    address internal stranger;
    RecordingAction internal action;
    SafeStaticLab internal lab;

    function setUp() public {
        admin = makeAddr("admin");
        candidate = makeAddr("candidate");
        stranger = makeAddr("stranger");
        action = new RecordingAction();
        lab = new SafeStaticLab(admin, action);
    }

    // Uso legittimo (ST-03): l'admin esegue, ma solo verso l'action fissata al deploy.
    function test_AdminExecutesOnlyImmutableTypedAction() public {
        bytes memory payload = abi.encode("reviewed action");

        vm.prank(admin);
        lab.execute(payload);

        assertTrue(lab.completed());
        // RecordingAction conferma che la call e' avvenuta davvero, con i dati giusti.
        assertEq(action.lastCaller(), address(lab));
        assertEq(action.lastData(), payload);
        assertEq(address(lab.action()), address(action));
    }

    // Regressione ST-01: stessa azione che fallisce, ma ora il fallimento si propaga.
    function test_Regression_FailedActionCannotMarkCompleted() public {
        // Serve un lab dedicato: action e' immutable e si sceglie solo nel constructor.
        RevertingAction failingAction = new RevertingAction();
        SafeStaticLab failingLab = new SafeStaticLab(admin, failingAction);

        vm.expectRevert(RevertingAction.ActionFailed.selector);
        vm.prank(admin);
        failingLab.execute(bytes("fails"));

        // `completed = true` era gia' stato scritto, ma il revert lo ha annullato.
        assertFalse(failingLab.completed());
    }

    // Regressione ST-03: il caller non autorizzato non raggiunge la call esterna.
    function test_Regression_StrangerCannotExecute() public {
        vm.expectRevert(abi.encodeWithSelector(SafeStaticLab.Unauthorized.selector, stranger));
        vm.prank(stranger);
        lab.execute(bytes("unauthorized"));

        assertFalse(lab.completed());
        assertEq(action.lastCaller(), address(0)); // run() non e' mai stata chiamata
    }

    // Le due fasi, una alla volta: dopo la proposta l'admin NON e' ancora cambiato.
    function test_AdminTransferRequiresProposalAndAcceptance() public {
        vm.prank(admin);
        lab.transferAdmin(candidate);
        assertEq(lab.admin(), admin); // fase 1: solo proposta
        assertEq(lab.pendingAdmin(), candidate);

        vm.prank(candidate);
        lab.acceptAdmin();
        assertEq(lab.admin(), candidate); // fase 2: ora si
        assertEq(lab.pendingAdmin(), address(0));
    }

    // Regressione ST-02: la stessa mossa dell'attacker ora reverte.
    function test_Regression_StrangerCannotReplaceAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(SafeStaticLab.Unauthorized.selector, stranger));
        vm.prank(stranger);
        lab.transferAdmin(stranger);

        assertEq(lab.admin(), admin);
    }

    // Due expectRevert nello stesso test: ognuno vale solo per la call immediatamente dopo.
    function test_ConfigurationRejectsZeroAddresses() public {
        vm.expectRevert(SafeStaticLab.ZeroAddress.selector);
        new SafeStaticLab(address(0), action);

        vm.expectRevert(SafeStaticLab.ZeroAddress.selector);
        new SafeStaticLab(admin, IStaticAction(address(0)));
    }
}
