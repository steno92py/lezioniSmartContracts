// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode usati in questo file:
//   makeAddr("nome")    indirizzo deterministico ed etichettato nelle trace, senza codice;
//   vm.prank(a)         la PROSSIMA call avra' msg.sender = a;
//   vm.expectRevert(e)  la PROSSIMA call deve revertire con l'errore e.
// Tre attori: admin (gestisce l'allowlist), operator (esegue), stranger (nessun ruolo).
import { Test } from "forge-std/Test.sol";
import { CallUtilsLite } from "../src/utils/CallUtilsLite.sol";
import { AllowlistedExecutor } from "../src/AllowlistedExecutor.sol";
import { GoodDependency, RevertingDependency } from "../src/mocks/ActionDependencies.sol";

contract AllowlistedExecutorTest is Test {
    AllowlistedExecutor internal executor;
    GoodDependency internal allowedDependency;

    address internal admin;
    address internal operator;
    address internal stranger;

    function setUp() public {
        admin = makeAddr("admin");
        operator = makeAddr("operator");
        stranger = makeAddr("stranger");
        executor = new AllowlistedExecutor(admin, operator);
        allowedDependency = new GoodDependency();
    }

    function test_AdminCanAllowAndOperatorCanExecute() public {
        // ARRANGE: l'admin mette il target in allowlist.
        _allow(address(allowedDependency));

        // ACT: l'operator lo esegue.
        vm.prank(operator);
        bytes memory result = executor.execute(
            address(allowedDependency), abi.encodeCall(allowedDependency.execute, ())
        );

        // ASSERT: dipendenza eseguita, return value inoltrato, contatore avanzato.
        assertTrue(allowedDependency.executed());
        assertEq(abi.decode(result, (uint256)), 42);
        assertEq(executor.completedCalls(), 1);
    }

    // Anche l'operator legittimo non puo' chiamare un target che l'admin non ha approvato.
    function test_RevertWhen_TargetIsNotAllowed() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                AllowlistedExecutor.TargetNotAllowed.selector, address(allowedDependency)
            )
        );
        vm.prank(operator);
        executor.execute(address(allowedDependency), abi.encodeCall(allowedDependency.execute, ()));

        assertFalse(allowedDependency.executed());
    }

    function test_AdminCanRevokeTarget() public {
        _allow(address(allowedDependency));
        vm.prank(admin);
        executor.setTargetAllowed(address(allowedDependency), false);

        assertFalse(executor.allowedTarget(address(allowedDependency)));
    }

    // Test di autorizzazione: ogni ruolo e' verificato sulla propria funzione.
    function test_RevertWhen_NonAdminChangesAllowlist() public {
        vm.expectRevert(abi.encodeWithSelector(AllowlistedExecutor.Unauthorized.selector, stranger));
        vm.prank(stranger);
        executor.setTargetAllowed(address(allowedDependency), true);
    }

    function test_RevertWhen_NonOperatorExecutes() public {
        // Il target e' in allowlist: l'unico motivo del revert deve essere il chiamante.
        _allow(address(allowedDependency));

        vm.expectRevert(abi.encodeWithSelector(AllowlistedExecutor.Unauthorized.selector, stranger));
        vm.prank(stranger);
        executor.execute(address(allowedDependency), abi.encodeCall(allowedDependency.execute, ()));
    }

    // Un target fidato puo' comunque fallire: il fallimento risale e il contatore non avanza.
    function test_RevertingAllowedDependencyDoesNotIncrementCounter() public {
        RevertingDependency revertingDependency = new RevertingDependency();
        _allow(address(revertingDependency));

        vm.expectRevert(RevertingDependency.DependencyFailure.selector);
        vm.prank(operator);
        executor.execute(
            address(revertingDependency), abi.encodeCall(revertingDependency.execute, ())
        );

        assertEq(executor.completedCalls(), 0);
    }

    function test_RevertWhen_AllowingTargetWithoutCode() public {
        vm.expectRevert(abi.encodeWithSelector(CallUtilsLite.TargetHasNoCode.selector, stranger));
        vm.prank(admin);
        executor.setTargetAllowed(stranger, true);
    }

    // Helper: mette un target in allowlist come admin.
    function _allow(address target) internal {
        vm.prank(admin);
        executor.setTargetAllowed(target, true);
    }
}
