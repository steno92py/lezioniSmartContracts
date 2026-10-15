// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode e helper usati in questo file:
//   makeAddr("nome")  crea un indirizzo deterministico con un'etichetta leggibile nei trace;
//   vm.prank(a)       la PROSSIMA call avra' msg.sender = a.
// Tre ruoli distinti: owner (possiede i token), spender (autorizzato), recipient (li riceve).
import { Test } from "forge-std/Test.sol";
import { TestToken } from "./mocks/TestToken.sol";

contract AllowanceFlowTest is Test {
    TestToken internal token;
    address internal owner;
    address internal spender;
    address internal recipient;

    function setUp() public {
        token = new TestToken();
        owner = makeAddr("owner");
        spender = makeAddr("spender");
        recipient = makeAddr("recipient");
        token.mint(owner, 1_000 ether);
    }

    function test_ApproveChangesAuthorizationButMovesNoTokens() public {
        // ACT: l'owner autorizza lo spender.
        vm.prank(owner);
        token.approve(spender, 100 ether);

        // ASSERT: saldi identici, cambia solo l'allowance. approve non trasferisce nulla.
        assertEq(token.balanceOf(owner), 1_000 ether);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(owner, spender), 100 ether);
    }

    function test_TransferFromConsumesExactAllowance() public {
        // ARRANGE: owner autorizza esattamente 100.
        vm.prank(owner);
        token.approve(spender, 100 ether);

        // ACT: a chiamare e' lo SPENDER, ma i token escono dal saldo dell'OWNER.
        vm.prank(spender);
        token.transferFrom(owner, recipient, 100 ether);

        // ASSERT: i token si sono mossi e l'allowance e' stata consumata fino a zero.
        assertEq(token.balanceOf(owner), 900 ether);
        assertEq(token.balanceOf(recipient), 100 ether);
        assertEq(token.allowance(owner, spender), 0);
    }

    // L'allowance non spesa RESTA: lo spender potra' usarla anche in futuro.
    // E' il motivo per cui un'approvazione ampia a un contratto e' un rischio persistente.
    function test_LargerAllowancePersistsAfterPartialSpend() public {
        vm.prank(owner);
        token.approve(spender, 1_000 ether);

        vm.prank(spender);
        token.transferFrom(owner, recipient, 100 ether);

        assertEq(token.allowance(owner, spender), 900 ether);
    }
}

