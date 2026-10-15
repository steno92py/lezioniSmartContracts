// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Per vedere la delegatecall nel trace: forge test --match-contract SimpleProxyTest -vvvv
import { Test } from "forge-std/Test.sol";
import { SimpleProxy } from "../src/lab/SimpleProxy.sol";
import { SimpleLogicV1 } from "../src/lab/SimpleLogicV1.sol";

// Entrambi i test PASSANO perche' l'attacco riesce: documentano le due vulnerabilita'
// dichiarate di SimpleProxy. La versione corretta e' testata in UpgradeableEscrow.t.sol.
contract SimpleProxyTest is Test {
    /// @dev Il test passa mostrando che value e implementation condividono lo slot 0.
    function test_Vulnerable_ApplicationWriteCorruptsImplementationSlot() public {
        SimpleLogicV1 logic = new SimpleLogicV1();
        SimpleProxy proxy = new SimpleProxy(address(logic));

        // Una normale scrittura applicativa, passando dal proxy...
        SimpleLogicV1(address(proxy)).setValue(123);

        // ...ha sovrascritto l'indirizzo dell'implementation: ora il proxy punta a 0x7b (123).
        // uint256(uint160(...)): un address si converte in numero passando da uint160 (20 byte).
        assertEq(uint256(uint160(proxy.implementation())), 123);
    }

    /// @dev Il proxy fragile consente a qualunque caller di sostituire il codice.
    function test_Vulnerable_StrangerCanUpgrade() public {
        SimpleProxy proxy = new SimpleProxy(address(new SimpleLogicV1()));
        address stranger = makeAddr("stranger"); // makeAddr: indirizzo etichettato nei trace
        address replacement = address(new SimpleLogicV1());

        vm.prank(stranger); // la prossima call ha msg.sender = stranger
        proxy.upgradeTo(replacement);

        assertEq(proxy.implementation(), replacement);
    }
}
