// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Ogni test mette lo stesso Escrow davanti a un token con un comportamento diverso (mock).
// Cheatcode usati in questo file:
//   vm.prank(a)                   la PROSSIMA call avra' msg.sender = a;
//   vm.startPrank(a)/stopPrank()  TUTTE le call nel mezzo avranno msg.sender = a;
//   vm.expectRevert(e)            la PROSSIMA call deve revertire con l'errore e.
import { Test } from "forge-std/Test.sol";
import { IERC20 } from "../src/token/IERC20.sol";
import { SafeERC20Lite } from "../src/token/SafeERC20Lite.sol";
import { TokenEscrow } from "../src/TokenEscrow.sol";
import { VulnerableTokenVault } from "../src/VulnerableTokenVault.sol";
import { FalseReturnToken } from "./mocks/FalseReturnToken.sol";
import { NoReturnToken } from "./mocks/NoReturnToken.sol";
import { FeeToken } from "./mocks/FeeToken.sol";
import { SelectiveFalseToken } from "./mocks/SelectiveFalseToken.sol";

contract TokenCompatibilityTest is Test {
    address internal buyer;
    address internal seller;

    uint256 internal constant AMOUNT = 100 ether;

    function setUp() public {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
    }

    /// @dev Il test passa dimostrando che la call e l'asset transfer non sono sinonimi.
    /// Se un giorno il vault venisse corretto, questo test diventerebbe rosso: e' voluto.
    function test_Vulnerable_FalseReturnCreatesUnbackedCredit() public {
        // IERC20(address(token)): conversione di tipo, il vault vede il mock come un IERC20.
        FalseReturnToken token = new FalseReturnToken();
        VulnerableTokenVault vault = new VulnerableTokenVault(IERC20(address(token)));
        token.mint(buyer, AMOUNT);

        vm.prank(buyer);
        vault.deposit(AMOUNT); // nessun revert: il `false` del token passa inosservato

        assertEq(token.balanceOf(address(vault)), 0); // asset ricevuti: 0
        assertEq(vault.credit(buyer), AMOUNT); // credito interno: 100
    }

    // Stesso token, contratto corretto: il `false` diventa un revert e lo stato resta intatto.
    function test_SafeEscrowRejectsFalseReturnWithoutChangingState() public {
        FalseReturnToken token = new FalseReturnToken();
        TokenEscrow escrow = new TokenEscrow(IERC20(address(token)), buyer, seller);
        token.mint(buyer, AMOUNT);

        vm.prank(buyer);
        token.approve(address(escrow), AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(SafeERC20Lite.SafeTransferFailed.selector, address(token))
        );
        vm.prank(buyer);
        escrow.deposit(AMOUNT);

        assertEq(uint256(escrow.state()), uint256(TokenEscrow.State.Created));
        assertEq(escrow.escrowedAmount(), 0);
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    // Il wrapper non deve essere troppo severo: un token senza bool che riesce va accettato.
    function test_SafeEscrowSupportsSuccessfulNoReturnToken() public {
        NoReturnToken token = new NoReturnToken();
        TokenEscrow escrow = new TokenEscrow(IERC20(address(token)), buyer, seller);
        token.mint(buyer, AMOUNT);

        vm.startPrank(buyer);
        token.approve(address(escrow), AMOUNT);
        escrow.deposit(AMOUNT);
        escrow.release();
        vm.stopPrank();

        assertEq(token.balanceOf(seller), AMOUNT);
        assertEq(escrow.escrowedAmount(), 0);
        assertEq(uint256(escrow.state()), uint256(TokenEscrow.State.Released));
    }

    // Richiesti 100, arrivati 90: l'Escrow registra 90 grazie alla misura del saldo.
    function test_FeeTokenAccountsForActualAmountReceived() public {
        (FeeToken token, TokenEscrow escrow) = _fundFeeEscrow();

        // La proprieta' di solvibilita' e' l'ultima riga: saldo reale >= passivita' registrata.
        assertEq(token.balanceOf(address(escrow)), 90 ether);
        assertEq(escrow.escrowedAmount(), 90 ether);
        assertEq(token.balanceOf(token.FEE_COLLECTOR()), 10 ether);
        assertGe(token.balanceOf(address(escrow)), escrow.escrowedAmount());
    }

    // Anche l'uscita e' tassata: dei 90 addebitati il seller riceve 81 (90 - 10%).
    // Il test fissa questa policy: e' una scelta esplicita, non un effetto collaterale.
    function test_FeeTokenPayoutPolicyLeavesSecondFeeToSeller() public {
        (FeeToken token, TokenEscrow escrow) = _fundFeeEscrow();

        vm.prank(buyer);
        escrow.release();

        assertEq(token.balanceOf(seller), 81 ether);
        assertEq(token.balanceOf(token.FEE_COLLECTOR()), 19 ether);
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(escrow.escrowedAmount(), 0);
        assertEq(uint256(escrow.state()), uint256(TokenEscrow.State.Released));
    }

    // Regressione sull'atomicita': release scrive gli effetti PRIMA del transfer (CEI),
    // ma se il transfer fallisce il revert li annulla tutti.
    function test_FailedPayoutRollsBackEffectsAndState() public {
        // ARRANGE: deposito riuscito, poi si "rompe" il transfer in uscita.
        SelectiveFalseToken token = new SelectiveFalseToken();
        TokenEscrow escrow = new TokenEscrow(IERC20(address(token)), buyer, seller);
        token.mint(buyer, AMOUNT);

        vm.startPrank(buyer);
        token.approve(address(escrow), AMOUNT);
        escrow.deposit(AMOUNT);
        vm.stopPrank();

        token.setFailDirectTransfers(true);

        // ACT: il payout fallisce.
        vm.expectRevert(
            abi.encodeWithSelector(SafeERC20Lite.SafeTransferFailed.selector, address(token))
        );
        vm.prank(buyer);
        escrow.release();

        // ASSERT: stato e passivita' come prima della call. Un enum si confronta
        // convertendolo a uint256, perche' assertEq non accetta tipi enum.
        assertEq(uint256(escrow.state()), uint256(TokenEscrow.State.Funded));
        assertEq(escrow.escrowedAmount(), AMOUNT);
        assertEq(token.balanceOf(address(escrow)), AMOUNT);
        assertEq(token.balanceOf(seller), 0);
    }

    // Helper: Escrow finanziato con FeeToken. Restituisce due valori (tupla).
    function _fundFeeEscrow() internal returns (FeeToken token, TokenEscrow escrow) {
        token = new FeeToken();
        escrow = new TokenEscrow(IERC20(address(token)), buyer, seller);
        token.mint(buyer, AMOUNT);

        vm.startPrank(buyer);
        token.approve(address(escrow), AMOUNT);
        escrow.deposit(AMOUNT);
        vm.stopPrank();
    }
}

