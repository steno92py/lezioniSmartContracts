// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode usati in questo file:
//   vm.prank(a)         la PROSSIMA call avra' msg.sender = a;
//   vm.prank(a, b)      come sopra, e in piu' tx.origin = b;
//   vm.expectRevert(e)  la PROSSIMA call deve revertire con l'errore e.
// Per vedere la catena owner -> Forwarder -> vault:
//   forge test --match-contract TxOriginVaultTest -vvvv
import { Test } from "forge-std/Test.sol";
import { TxOriginVault, DirectCallerVault, Forwarder } from "../src/access/TxOriginVault.sol";

contract TxOriginVaultTest is Test {
    address internal owner;

    function setUp() public {
        owner = makeAddr("owner");
    }

    // Questo test PASSA perche' dimostra che l'attacco riesce: documenta la vulnerabilita'.
    function test_Vulnerable_TxOriginAllowsIndirectCall() public {
        TxOriginVault target = new TxOriginVault(owner);
        Forwarder forwarder = new Forwarder();

        // L'owner avvia la transazione chiamando il Forwarder, non il vault.
        vm.prank(owner, owner);
        forwarder.forwardSet(target, 123);

        // Il valore e' cambiato anche se a chiamare setProtectedValue e' stato il Forwarder.
        assertEq(target.protectedValue(), 123);
    }

    // Test di regressione: stessa catena sulla versione corretta, che deve rifiutarla.
    function test_Fixed_MsgSenderRejectsIndirectCall() public {
        DirectCallerVault target = new DirectCallerVault(owner);
        Forwarder forwarder = new Forwarder();

        // Il revert nasce nel vault e risale attraverso il Forwarder fino al test.
        // Il parametro dell'errore conferma chi e' stato respinto: il Forwarder, non l'owner.
        vm.expectRevert(
            abi.encodeWithSelector(DirectCallerVault.Unauthorized.selector, address(forwarder))
        );
        vm.prank(owner, owner);
        forwarder.forwardSet(target, 123);

        assertEq(target.protectedValue(), 0);
    }

    // La correzione non deve bloccare l'uso legittimo: l'owner che chiama direttamente passa.
    function test_Fixed_OwnerCanCallDirectly() public {
        DirectCallerVault target = new DirectCallerVault(owner);

        vm.prank(owner);
        target.setProtectedValue(123);

        assertEq(target.protectedValue(), 123);
    }
}
