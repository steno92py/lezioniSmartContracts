// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode usati in questo file:
//   makeAddr("nome")  indirizzo deterministico, etichettato nei trace;
//   vm.prank(a)       la PROSSIMA call avra' msg.sender = a.
import { Test } from "forge-std/Test.sol";
import { EducationalERC1967Proxy } from "../src/proxy/EducationalERC1967Proxy.sol";
import { ContextLogic } from "../src/lab/ContextLogic.sol";

contract DelegatecallContextTest is Test {
    function test_DelegatecallUsesLogicCodeWithProxyContext() public {
        // ARRANGE: bytes("") = nessuna inizializzazione.
        ContextLogic logic = new ContextLogic();
        EducationalERC1967Proxy proxy = new EducationalERC1967Proxy(address(logic), bytes(""));
        address alice = makeAddr("alice");

        // ACT. ContextLogic(address(proxy)) non converte nulla: dice al compilatore di usare
        // l'ABI di ContextLogic sull'indirizzo del proxy. Il proxy non ha recordContext(),
        // quindi scatta la sua fallback, che fa delegatecall verso logic.
        vm.prank(alice);
        ContextLogic(address(proxy)).recordContext();

        // ASSERT: nello storage del proxy, msg.sender = alice (non il proxy) e
        // address(this) = proxy (non logic).
        ContextLogic proxied = ContextLogic(address(proxy));
        assertEq(proxied.lastCaller(), alice);
        assertEq(proxied.lastContext(), address(proxy));
        // Lo storage di logic non e' mai stato toccato: il suo codice ha scritto altrove.
        assertEq(logic.lastCaller(), address(0));
        assertEq(logic.lastContext(), address(0));
    }
}
