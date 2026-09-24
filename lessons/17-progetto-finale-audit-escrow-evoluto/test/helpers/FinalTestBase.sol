// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Base comune delle suite: ruoli, costanti e funzioni di setup condivise.
// Cheatcode usati qui (disponibili tramite `vm`, ereditato da Test):
//   makeAddr("nome")          indirizzo deterministico con etichetta leggibile nelle trace;
//   vm.warp(t)                imposta block.timestamp a t;
//   vm.startPrank(a) / stop   TUTTE le call successive, fino a stopPrank, hanno msg.sender = a.
import {Test} from "forge-std/Test.sol";
import {IERC20Final, IPriceOracleFinal, INotifierFinal} from "../../src/interfaces/IFinalDependencies.sol";
import {EscrowFinal} from "../../src/EscrowFinal.sol";
import {EscrowFinalFixed} from "../../src/fixed/EscrowFinalFixed.sol";
import {TestToken, MockOracle} from "../../src/mocks/FinalMocks.sol";

// `abstract`: non viene eseguita da sola, solo ereditata dalle suite concrete.
abstract contract FinalTestBase is Test {
    uint256 internal constant AMOUNT = 100 ether; // 100 * 10^18: 100 token da 18 decimali
    int256 internal constant VALID_PRICE = 3_000e8;

    address internal buyer;
    address internal seller;
    address internal owner;
    address internal pauser;
    address internal stranger; // nessun ruolo: serve a provare i controlli di accesso

    // `virtual`: una suite figlia puo' estenderla con override e super.setUp().
    function setUp() public virtual {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        owner = makeAddr("owner");
        pauser = makeAddr("pauser");
        stranger = makeAddr("stranger");
        // Timestamp lontano da zero: cosi' `block.timestamp - 2 hours` non va in underflow.
        vm.warp(1_000_000);
    }

    // Fabbriche: stesso setup di ruoli per target e remediation, cambiano solo le dipendenze.
    function _target(IERC20Final token, IPriceOracleFinal oracle, INotifierFinal notifier)
        internal
        returns (EscrowFinal)
    {
        return new EscrowFinal(token, buyer, seller, owner, pauser, oracle, notifier);
    }

    function _fixed(IERC20Final token, IPriceOracleFinal oracle, INotifierFinal notifier)
        internal
        returns (EscrowFinalFixed)
    {
        return new EscrowFinalFixed(token, buyer, seller, owner, pauser, oracle, notifier);
    }

    // Percorso completo di deposito: conia i token al buyer, approve verso l'escrow, deposit.
    // approve e deposit devono partire dal buyer, per questo sono dentro startPrank.
    function _fundTarget(TestToken token, EscrowFinal escrow, uint256 amount) internal {
        token.mint(buyer, amount);
        vm.startPrank(buyer);
        token.approve(address(escrow), amount);
        escrow.deposit(amount);
        vm.stopPrank();
    }

    function _fundFixed(TestToken token, EscrowFinalFixed escrow, uint256 amount) internal {
        token.mint(buyer, amount);
        vm.startPrank(buyer);
        token.approve(address(escrow), amount);
        escrow.deposit(amount);
        vm.stopPrank();
    }

    // Oracle con prezzo valido aggiornato adesso (eta' zero).
    function _freshOracle() internal returns (MockOracle) {
        return new MockOracle(VALID_PRICE, block.timestamp);
    }
}
