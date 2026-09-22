// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {CreditVault} from "../../../src/invariant/CreditVault.sol";
import {ExactToken} from "../../../src/invariant/ExactToken.sol";

contract VaultHandler is Test {
    uint256 public constant MAX_ACTION_AMOUNT = 1_000 ether;
    uint256 public constant INITIAL_ACTOR_BALANCE = 1_000_000_000 ether;

    CreditVault public immutable vault;
    ExactToken public immutable token;

    address[] internal actors;

    uint256 public ghostDeposited;
    uint256 public ghostWithdrawn;
    uint256 public callsDeposit;
    uint256 public callsWithdraw;
    uint256 public callsAdversarialWithdraw;
    uint256 public noOpWithdraw;

    constructor(CreditVault vault_, ExactToken token_) {
        vault = vault_;
        token = token_;

        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));

        for (uint256 i; i < actors.length; ++i) {
            token.mint(actors[i], INITIAL_ACTOR_BALANCE);
            vm.prank(actors[i]);
            token.approve(address(vault), type(uint256).max);
        }
    }

    function deposit(uint256 actorSeed, uint256 rawAmount) external {
        address selectedActor = _actor(actorSeed);
        uint256 amount = bound(rawAmount, 1, MAX_ACTION_AMOUNT);

        vm.prank(selectedActor);
        vault.deposit(amount);

        ghostDeposited += amount;
        callsDeposit += 1;
    }

    function withdraw(uint256 actorSeed, uint256 rawAmount) external {
        address selectedActor = _actor(actorSeed);
        uint256 available = vault.credit(selectedActor);
        if (available == 0) {
            noOpWithdraw += 1;
            return;
        }
        uint256 amount = bound(rawAmount, 1, available);

        vm.prank(selectedActor);
        vault.withdraw(amount);

        ghostWithdrawn += amount;
        callsWithdraw += 1;
    }

    function withdrawTooMuch(uint256 actorSeed, uint256 rawExtra) external {
        address selectedActor = _actor(actorSeed);
        uint256 available = vault.credit(selectedActor);
        uint256 extra = bound(rawExtra, 1, MAX_ACTION_AMOUNT);
        uint256 requested = available + extra;
        uint256 totalBefore = vault.totalCredit();
        uint256 balanceBefore = token.balanceOf(address(vault));

        vm.expectRevert(
            abi.encodeWithSelector(CreditVault.InsufficientCredit.selector, selectedActor, requested, available)
        );
        vm.prank(selectedActor);
        vault.withdraw(requested);

        assertEq(vault.credit(selectedActor), available);
        assertEq(vault.totalCredit(), totalBefore);
        assertEq(token.balanceOf(address(vault)), balanceBefore);
        callsAdversarialWithdraw += 1;
    }

    function actor(uint256 index) external view returns (address) {
        return actors[index];
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }
}
