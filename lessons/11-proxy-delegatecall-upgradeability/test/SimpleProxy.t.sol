// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { SimpleProxy } from "../src/lab/SimpleProxy.sol";
import { SimpleLogicV1 } from "../src/lab/SimpleLogicV1.sol";

contract SimpleProxyTest is Test {
    /// @dev Il test passa mostrando che value e implementation condividono lo slot 0.
    function test_Vulnerable_ApplicationWriteCorruptsImplementationSlot() public {
        SimpleLogicV1 logic = new SimpleLogicV1();
        SimpleProxy proxy = new SimpleProxy(address(logic));

        SimpleLogicV1(address(proxy)).setValue(123);

        assertEq(uint256(uint160(proxy.implementation())), 123);
    }

    /// @dev Il proxy fragile consente a qualunque caller di sostituire il codice.
    function test_Vulnerable_StrangerCanUpgrade() public {
        SimpleProxy proxy = new SimpleProxy(address(new SimpleLogicV1()));
        address stranger = makeAddr("stranger");
        address replacement = address(new SimpleLogicV1());

        vm.prank(stranger);
        proxy.upgradeTo(replacement);

        assertEq(proxy.implementation(), replacement);
    }
}

