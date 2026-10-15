// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Fuzz test: una funzione di test con parametri. Foundry la esegue molte volte
// (256 run, vedi [fuzz] in foundry.toml) con input generati, cercando un controesempio.
// Cheatcode e helper usati in questo file:
//   bound(x, min, max)   riporta x nell'intervallo [min, max] senza scartare il run;
//   vm.assume(cond)      scarta il run se cond e' falsa (da usare solo per casi rari);
//   vm.prank / vm.expectRevert   come nelle altre suite.
import {FinalTestBase} from "../helpers/FinalTestBase.sol";
import {EscrowFinalFixed} from "../../src/fixed/EscrowFinalFixed.sol";
import {INotifierFinal} from "../../src/interfaces/IFinalDependencies.sol";
import {TestToken, MockOracle} from "../../src/mocks/FinalMocks.sol";

contract FinalFuzzTest is FinalTestBase {
    // Con un token standard, ricevuto == richiesto per qualunque importo.
    // uint96 limita gia' il dominio; bound esclude lo zero, che revert per specifica.
    function testFuzz_DepositTracksActualStandardTokenBalance(uint96 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1, type(uint96).max);
        TestToken token = new TestToken();
        EscrowFinalFixed escrow = _fixed(token, _freshOracle(), INotifierFinal(address(0)));
        _fundFixed(token, escrow, amount);
        assertEq(escrow.escrowedAmount(), token.balanceOf(address(escrow)));
        assertEq(escrow.escrowedAmount(), amount);
    }

    // L'intervallo 0..1_100 attraversa il confine 1_000: il test sceglie il ramo atteso
    // in base all'input (oracolo del test) e verifica entrambi i lati.
    function testFuzz_FeeBoundary(uint16 rawFee) public {
        uint256 fee = bound(uint256(rawFee), 0, 1_100);
        TestToken token = new TestToken();
        EscrowFinalFixed escrow = _fixed(token, _freshOracle(), INotifierFinal(address(0)));
        vm.prank(owner);
        if (fee <= 1_000) {
            escrow.setFee(fee);
            assertEq(escrow.feeBps(), fee);
        } else {
            vm.expectRevert(EscrowFinalFixed.FeeTooHigh.selector);
            escrow.setFee(fee);
        }
    }

    // Eta' del prezzo tra 0 e 2 ore: fino a 1 ora inclusa release riesce, oltre revert.
    function testFuzz_OracleFreshnessBoundary(uint16 rawAge) public {
        uint256 age = bound(uint256(rawAge), 0, 2 hours);
        TestToken token = new TestToken();
        MockOracle oracle = new MockOracle(VALID_PRICE, block.timestamp - age);
        EscrowFinalFixed escrow = _fixed(token, oracle, INotifierFinal(address(0)));
        _fundFixed(token, escrow, AMOUNT);
        // prank prima dell'if: vale per la release di entrambi i rami.
        vm.prank(buyer);
        if (age <= 1 hours) {
            escrow.release();
            assertEq(token.balanceOf(seller), AMOUNT);
        } else {
            vm.expectRevert(EscrowFinalFixed.StalePrice.selector);
            escrow.release();
        }
    }

    // Il fuzzer genera il chiamante: qualunque indirizzo diverso dall'owner deve fallire.
    function testFuzz_UnauthorizedAccountCannotSetOracle(address caller) public {
        vm.assume(caller != owner);
        TestToken token = new TestToken();
        EscrowFinalFixed escrow = _fixed(token, _freshOracle(), INotifierFinal(address(0)));
        MockOracle replacement = _freshOracle();
        vm.prank(caller);
        vm.expectRevert(EscrowFinalFixed.OnlyOwner.selector);
        escrow.setOracle(replacement);
    }
}
