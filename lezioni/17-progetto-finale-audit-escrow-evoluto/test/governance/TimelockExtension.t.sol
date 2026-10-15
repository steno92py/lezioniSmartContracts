// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Governance ritardata: l'owner dell'escrow e' il timelock, non una persona.
// Flusso: il proposer programma (schedule), passa DELAY, l'executor esegue (execute),
// e solo allora il timelock chiama escrow.setOracle come msg.sender autorizzato.
// Cheatcode usati in questo file:
//   makeAddr("nome")     indirizzo deterministico con etichetta;
//   vm.warp(t)           imposta block.timestamp: simula il passare del tempo;
//   vm.prank(a)          la PROSSIMA call avra' msg.sender = a;
//   vm.expectRevert(e)   la PROSSIMA call deve revertire con l'errore e.
import {Test} from "forge-std/Test.sol";
import {EscrowFinalFixed} from "../../src/fixed/EscrowFinalFixed.sol";
import {FinalTimelock} from "../../src/extensions/FinalTimelock.sol";
import {TestToken, MockOracle} from "../../src/mocks/FinalMocks.sol";
import {INotifierFinal} from "../../src/interfaces/IFinalDependencies.sol";

contract TimelockExtensionTest is Test {
    uint256 internal constant DELAY = 2 days;
    address internal proposer;
    address internal executor;
    FinalTimelock internal timelock;
    EscrowFinalFixed internal escrow;
    MockOracle internal replacement;

    function setUp() public {
        vm.warp(1_000_000);
        proposer = makeAddr("multisig-proposer");
        executor = makeAddr("executor");
        timelock = new FinalTimelock(DELAY, proposer, executor);
        TestToken token = new TestToken();
        MockOracle oracle = new MockOracle(3_000e8, block.timestamp);
        replacement = new MockOracle(4_000e8, block.timestamp);
        escrow = new EscrowFinalFixed(
            token,
            makeAddr("buyer"),
            makeAddr("seller"),
            // owner_ = timelock: ogni funzione onlyOwner passa dal ritardo.
            address(timelock),
            makeAddr("pauser"),
            oracle,
            INotifierFinal(address(0))
        );
    }

    // Il proposer ha un ruolo nel timelock, non nell'escrow: chiamare direttamente fallisce.
    function test_ProposerCannotDirectlyChangeOracle() public {
        vm.prank(proposer);
        vm.expectRevert(EscrowFinalFixed.OnlyOwner.selector);
        escrow.setOracle(replacement);
    }

    // Programmata ma senza vm.warp: il ritardo non e' trascorso.
    function test_TimelockCannotExecuteBeforeDelay() public {
        (bytes memory data, bytes32 salt) = _scheduleOracleChange();
        vm.prank(executor);
        vm.expectRevert(FinalTimelock.NotReady.selector);
        timelock.execute(address(escrow), data, salt);
    }

    function test_TimelockExecutesOracleChangeAfterDelay() public {
        (bytes memory data, bytes32 salt) = _scheduleOracleChange();
        // Esattamente DELAY secondi dopo: execute accetta block.timestamp >= readyAt.
        vm.warp(block.timestamp + DELAY);
        vm.prank(executor);
        timelock.execute(address(escrow), data, salt);
        assertEq(address(escrow.oracle()), address(replacement));
    }

    function _scheduleOracleChange() internal returns (bytes memory data, bytes32 salt) {
        // La chiamata da ritardare, codificata come calldata: selettore di setOracle + argomento.
        data = abi.encodeCall(EscrowFinalFixed.setOracle, (replacement));
        salt = keccak256("oracle-change");
        vm.prank(proposer);
        timelock.schedule(address(escrow), data, salt);
    }
}
