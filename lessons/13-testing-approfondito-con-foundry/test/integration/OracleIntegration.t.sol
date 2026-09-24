// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Integration test: escrow e oracle insieme, compresa la validazione della risposta.
// Due strategie per controllare l'oracle:
//   MockOracle (contratto)   stato, sequenze e revert configurabili con setAnswer/setShouldRevert;
//   vm.mockCall(a, cd, ret)  ogni call all'indirizzo a con calldata cd restituisce ret, senza
//                            eseguire il codice di a;
//   vm.expectCall(a, cd)     il test fallisce se durante l'esecuzione nessuno chiama a con cd.
import {TestingEscrow} from "../../src/TestingEscrow.sol";
import {ITestOracle} from "../../src/interfaces/ITestDependencies.sol";
import {MockOracle} from "../../src/mocks/TestingMocks.sol";
import {EscrowTestBase} from "../helpers/EscrowTestBase.sol";

contract OracleIntegrationTest is EscrowTestBase {
    // CONFINE della freshness: eta' esattamente MAX_PRICE_AGE e' accettata, un secondo in piu'
    // (test successivo) no. Il confine esatto distingue `>` da `>=` nel contratto.
    function test_PriceExactlyAtFreshnessBoundaryIsAccepted() public {
        oracle.setAnswer(FRESH_PRICE, block.timestamp - escrow.MAX_PRICE_AGE());

        _approveAndDeposit(100 ether);

        assertEq(escrow.depositPrice(), FRESH_PRICE);
    }

    function test_PriceOneSecondPastFreshnessBoundaryIsRejected() public {
        uint256 updatedAt = block.timestamp - escrow.MAX_PRICE_AGE() - 1;
        oracle.setAnswer(FRESH_PRICE, updatedAt);
        _approve(100 ether);

        vm.expectRevert(abi.encodeWithSelector(TestingEscrow.StalePrice.selector, updatedAt, block.timestamp));
        vm.prank(buyer);
        escrow.deposit(100 ether);

        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Created));
    }

    // Due casi nello stesso test: zero e' il confine, -1 il primo valore negativo.
    // I letterali 0 e -1 vengono codificati su 32 byte come l'int256 del payload.
    function test_ZeroAndNegativePricesAreRejected() public {
        oracle.setAnswer(0, block.timestamp);
        _approve(100 ether);
        vm.expectRevert(abi.encodeWithSelector(TestingEscrow.InvalidPrice.selector, 0));
        vm.prank(buyer);
        escrow.deposit(100 ether);

        oracle.setAnswer(-1, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(TestingEscrow.InvalidPrice.selector, -1));
        vm.prank(buyer);
        escrow.deposit(100 ether);
    }

    // Un secondo nel futuro basta: l'oracle dichiara un dato che non puo' ancora esistere.
    function test_FutureOracleTimestampIsRejected() public {
        uint256 future = block.timestamp + 1;
        oracle.setAnswer(FRESH_PRICE, future);
        _approve(100 ether);

        vm.expectRevert(abi.encodeWithSelector(TestingEscrow.InvalidOracleTimestamp.selector, future, block.timestamp));
        vm.prank(buyer);
        escrow.deposit(100 ether);
    }

    // Failure policy: se l'oracle reverte, anche il deposito reverte (l'errore risale la catena
    // di call) e nulla cambia. L'escrow non "indovina" un prezzo di ripiego.
    function test_RevertingDependencyPropagatesAndPreservesState() public {
        oracle.setShouldRevert(true);
        _approve(100 ether);

        // L'errore atteso e' quello del MockOracle, non uno dell'escrow.
        vm.expectRevert(MockOracle.OracleUnavailable.selector);
        vm.prank(buyer);
        escrow.deposit(100 ether);

        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Created));
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    function test_MockCallCanIsolateOracleReturnValue() public {
        int256 mockedPrice = 4_200e8;
        bytes memory callData = abi.encodeCall(ITestOracle.latestPrice, ());
        // Da qui in poi latestPrice() sull'oracle restituisce questa coppia, qualunque sia
        // il suo stato interno: il test controlla un singolo return senza configurare il mock.
        vm.mockCall(address(oracle), callData, abi.encode(mockedPrice, block.timestamp));
        // Verifica che l'escrow abbia davvero interrogato l'oracle...
        vm.expectCall(address(oracle), callData);

        _approveAndDeposit(100 ether);

        // ...e lo stato prova che ha usato proprio il valore restituito.
        assertEq(escrow.depositPrice(), mockedPrice);
    }
}

