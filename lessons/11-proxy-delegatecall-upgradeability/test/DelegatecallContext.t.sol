// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { EducationalERC1967Proxy } from "../src/proxy/EducationalERC1967Proxy.sol";
import { ContextLogic } from "../src/lab/ContextLogic.sol";

contract DelegatecallContextTest is Test {
    function test_DelegatecallUsesLogicCodeWithProxyContext() public {
        ContextLogic logic = new ContextLogic();
        EducationalERC1967Proxy proxy = new EducationalERC1967Proxy(address(logic), bytes(""));
        address alice = makeAddr("alice");

        vm.prank(alice);
        ContextLogic(address(proxy)).recordContext();

        ContextLogic proxied = ContextLogic(address(proxy));
        assertEq(proxied.lastCaller(), alice);
        assertEq(proxied.lastContext(), address(proxy));
        assertEq(logic.lastCaller(), address(0));
        assertEq(logic.lastContext(), address(0));
    }
}

