// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Test della versione corretta: solo constructor e withdrawFees(), il resto e' identico a
// FixedFeeRegistry ed e' gia' coperto da test/FixedFeeRegistry.t.sol.
import { Test } from "forge-std/Test.sol";
import { FixedFeeRegistryFixed } from "../src/fixed/FixedFeeRegistryFixed.sol";

// Contratto senza receive() ne' fallback(): qualunque invio di ETH verso di lui fallisce.
contract RejectsEther { }

contract FixedFeeRegistryFixedTest is Test {
    FixedFeeRegistryFixed internal registry;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant TREASURY = address(0x7EA5);
    uint256 internal constant FEE = 1 ether;

    function setUp() public {
        registry = new FixedFeeRegistryFixed(TREASURY);
        vm.deal(ALICE, 10 ether);
        vm.deal(BOB, 10 ether);
    }

    // La tesoreria address(0) viene rifiutata: le fee sarebbero perse per sempre.
    function test_RevertWhenTreasuryIsZero() public {
        vm.expectRevert(FixedFeeRegistryFixed.ZeroTreasury.selector);
        new FixedFeeRegistryFixed(address(0));
    }

    // Caso felice: ALICE e BOB si registrano, la tesoreria ritira entrambe le fee.
    function test_TreasuryWithdrawsFees() public {
        vm.prank(ALICE);
        registry.register{ value: FEE }();
        vm.prank(BOB);
        registry.register{ value: FEE }();

        vm.expectEmit(true, false, false, true, address(registry));
        emit FixedFeeRegistryFixed.FeesWithdrawn(TREASURY, 2 * FEE);

        vm.prank(TREASURY);
        registry.withdrawFees();

        assertEq(TREASURY.balance, 2 * FEE, "le fee devono arrivare alla tesoreria");
        assertEq(address(registry).balance, 0, "il contratto non deve trattenere nulla");
        // Il prelievo non tocca la contabilita' storica: la proprieta' continua a valere.
        assertEq(registry.registrationCount(), 2);
        assertEq(registry.totalReceived(), 2 * FEE);
        assertEq(registry.totalReceived(), registry.registrationCount() * FEE);
    }

    // Chi non e' la tesoreria non puo' ritirare, nemmeno chi ha pagato la fee.
    function test_RevertWhenCallerIsNotTreasury() public {
        vm.prank(ALICE);
        registry.register{ value: FEE }();

        vm.expectRevert(abi.encodeWithSelector(FixedFeeRegistryFixed.NotTreasury.selector, ALICE));
        vm.prank(ALICE);
        registry.withdrawFees();

        assertEq(address(registry).balance, FEE, "le fee devono restare nel contratto");
    }

    // Senza fee raccolte non si ritira niente.
    function test_RevertWhenNothingToWithdraw() public {
        vm.expectRevert(FixedFeeRegistryFixed.NothingToWithdraw.selector);
        vm.prank(TREASURY);
        registry.withdrawFees();
    }

    // Le stesse fee non si ritirano due volte.
    function test_RevertOnSecondWithdraw() public {
        vm.prank(ALICE);
        registry.register{ value: FEE }();

        vm.prank(TREASURY);
        registry.withdrawFees();

        vm.expectRevert(FixedFeeRegistryFixed.NothingToWithdraw.selector);
        vm.prank(TREASURY);
        registry.withdrawFees();

        assertEq(TREASURY.balance, FEE, "la tesoreria non deve ricevere piu' del dovuto");
    }

    // Se la tesoreria rifiuta l'ETH, il revert annulla tutto: le fee NON vanno perse.
    function test_RevertWhenTreasuryRejectsEther() public {
        RejectsEther rejecter = new RejectsEther();
        FixedFeeRegistryFixed stuck = new FixedFeeRegistryFixed(address(rejecter));

        vm.prank(ALICE);
        stuck.register{ value: FEE }();

        vm.expectRevert(FixedFeeRegistryFixed.TransferFailed.selector);
        vm.prank(address(rejecter));
        stuck.withdrawFees();

        assertEq(address(stuck).balance, FEE, "l'ETH deve restare nel contratto");
    }
}
