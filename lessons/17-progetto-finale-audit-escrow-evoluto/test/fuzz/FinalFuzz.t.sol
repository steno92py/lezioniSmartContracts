// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {FinalTestBase} from "../helpers/FinalTestBase.sol";
import {EscrowFinalFixed} from "../../src/fixed/EscrowFinalFixed.sol";
import {INotifierFinal} from "../../src/interfaces/IFinalDependencies.sol";
import {TestToken, MockOracle} from "../../src/mocks/FinalMocks.sol";

contract FinalFuzzTest is FinalTestBase {
    function testFuzz_DepositTracksActualStandardTokenBalance(uint96 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1, type(uint96).max);
        TestToken token = new TestToken();
        EscrowFinalFixed escrow = _fixed(token, _freshOracle(), INotifierFinal(address(0)));
        _fundFixed(token, escrow, amount);
        assertEq(escrow.escrowedAmount(), token.balanceOf(address(escrow)));
        assertEq(escrow.escrowedAmount(), amount);
    }

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

    function testFuzz_OracleFreshnessBoundary(uint16 rawAge) public {
        uint256 age = bound(uint256(rawAge), 0, 2 hours);
        TestToken token = new TestToken();
        MockOracle oracle = new MockOracle(VALID_PRICE, block.timestamp - age);
        EscrowFinalFixed escrow = _fixed(token, oracle, INotifierFinal(address(0)));
        _fundFixed(token, escrow, AMOUNT);
        vm.prank(buyer);
        if (age <= 1 hours) {
            escrow.release();
            assertEq(token.balanceOf(seller), AMOUNT);
        } else {
            vm.expectRevert(EscrowFinalFixed.StalePrice.selector);
            escrow.release();
        }
    }

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
