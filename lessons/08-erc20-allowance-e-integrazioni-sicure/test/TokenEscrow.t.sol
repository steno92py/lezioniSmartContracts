// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode e helper usati in questo file:
//   makeAddr("nome")              indirizzo deterministico con etichetta nei trace;
//   vm.prank(a)                   la PROSSIMA call avra' msg.sender = a;
//   vm.startPrank(a)/stopPrank()  tutte le call nel mezzo avranno msg.sender = a;
//   vm.expectRevert(e)            la PROSSIMA call deve revertire con l'errore e;
//   assertGe(a, b)                verifica a >= b (usato per la solvibilita').
import { Test } from "forge-std/Test.sol";
import { IERC20 } from "../src/token/IERC20.sol";
import { TokenEscrow } from "../src/TokenEscrow.sol";
import { TestToken } from "./mocks/TestToken.sol";

contract TokenEscrowTest is Test {
    TestToken internal token;
    TokenEscrow internal escrow;

    address internal buyer;
    address internal seller;
    address internal stranger;

    uint256 internal constant INITIAL_BALANCE = 1_000 ether;
    uint256 internal constant AMOUNT = 100 ether;

    // Eseguita prima di OGNI test: Escrow nuovo in stato Created, buyer con 1_000 token.
    function setUp() public {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        stranger = makeAddr("stranger");

        token = new TestToken();
        escrow = new TokenEscrow(IERC20(address(token)), buyer, seller);
        token.mint(buyer, INITIAL_BALANCE);
    }

    function test_InitialConfiguration() public view {
        assertEq(address(escrow.token()), address(token));
        assertEq(escrow.buyer(), buyer);
        assertEq(escrow.seller(), seller);
        assertEq(escrow.escrowedAmount(), 0);
        _assertState(TokenEscrow.State.Created);
    }

    function test_DepositMovesTokensAndConsumesExactAllowance() public {
        _approveAndDeposit(AMOUNT, AMOUNT); // approve 100, deposit 100

        // Si controllano tutti e tre i numeri: saldo, allowance, passivita' dell'Escrow.
        assertEq(token.balanceOf(buyer), INITIAL_BALANCE - AMOUNT);
        assertEq(token.balanceOf(address(escrow)), AMOUNT);
        assertEq(token.allowance(buyer, address(escrow)), 0);
        assertEq(escrow.escrowedAmount(), AMOUNT);
        _assertFundedAndSolvent();
    }

    // Approvati 1_000, spesi 100: i 900 restanti restano spendibili dall'Escrow.
    function test_LargerAllowanceRemainsAfterDeposit() public {
        _approveAndDeposit(1_000 ether, AMOUNT);

        assertEq(token.allowance(buyer, address(escrow)), 900 ether);
        _assertFundedAndSolvent();
    }

    function test_ReleasePaysSellerAndEndsPosition() public {
        _deposit(AMOUNT);

        vm.prank(buyer);
        escrow.release();

        assertEq(token.balanceOf(seller), AMOUNT);
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(escrow.escrowedAmount(), 0);
        _assertState(TokenEscrow.State.Released);
    }

    function test_RefundReturnsTokensAndEndsPosition() public {
        _deposit(AMOUNT);

        vm.prank(buyer);
        escrow.refund();

        assertEq(token.balanceOf(buyer), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(escrow.escrowedAmount(), 0);
        _assertState(TokenEscrow.State.Refunded);
    }

    // TEST NEGATIVI: ognuno verifica il motivo PRECISO del revert (selettore e parametri)
    // e poi lo stato, con gli helper _assert... in fondo al file.

    // Nessun approve: fallisce il token, non l'Escrow. SafeERC20Lite rilancia l'errore
    // originale, per questo ci si aspetta TestToken.InsufficientAllowance(escrow, 0, 100).
    function test_RevertWhen_DepositingWithoutAllowance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                TestToken.InsufficientAllowance.selector, address(escrow), 0, AMOUNT
            )
        );
        vm.prank(buyer);
        escrow.deposit(AMOUNT);

        _assertCreatedAndEmpty();
    }

    // CONFINE: allowance di un solo wei sotto il necessario.
    function test_RevertWhen_AllowanceIsInsufficient() public {
        vm.prank(buyer);
        token.approve(address(escrow), AMOUNT - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                TestToken.InsufficientAllowance.selector, address(escrow), AMOUNT - 1, AMOUNT
            )
        );
        vm.prank(buyer);
        escrow.deposit(AMOUNT);

        _assertCreatedAndEmpty();
        // Il revert annulla anche le scritture del token: l'allowance non e' stata consumata.
        assertEq(token.allowance(buyer, address(escrow)), AMOUNT - 1);
    }

    // Allowance sufficiente ma saldo no: autorizzazione e disponibilita' sono controlli diversi.
    function test_RevertWhen_BalanceIsInsufficient() public {
        uint256 tooMuch = INITIAL_BALANCE + 1;
        vm.prank(buyer);
        token.approve(address(escrow), tooMuch);

        vm.expectRevert(
            abi.encodeWithSelector(
                TestToken.InsufficientBalance.selector, buyer, INITIAL_BALANCE, tooMuch
            )
        );
        vm.prank(buyer);
        escrow.deposit(tooMuch);

        _assertCreatedAndEmpty();
        assertEq(token.allowance(buyer, address(escrow)), tooMuch);
    }

    // Business authorization: lo stranger ha token E allowance, ma non e' il buyer.
    // L'autorizzazione ERC-20 non sostituisce il controllo di ruolo del protocollo.
    function test_RevertWhen_StrangerHasTokensAndAllowance() public {
        token.mint(stranger, AMOUNT);
        vm.prank(stranger);
        token.approve(address(escrow), AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(TokenEscrow.OnlyBuyer.selector, stranger));
        vm.prank(stranger);
        escrow.deposit(AMOUNT);

        assertEq(token.balanceOf(stranger), AMOUNT);
        _assertCreatedAndEmpty();
    }

    function test_RevertWhen_DepositIsZero() public {
        vm.expectRevert(TokenEscrow.ZeroAmount.selector);
        vm.prank(buyer);
        escrow.deposit(0);

        _assertCreatedAndEmpty();
    }

    // Transizioni vietate della macchina a stati: ogni funzione e' ammessa da un solo stato.
    function test_RevertWhen_DepositingTwice() public {
        _deposit(AMOUNT);

        _expectInvalidState(TokenEscrow.State.Created, TokenEscrow.State.Funded);
        vm.prank(buyer);
        escrow.deposit(AMOUNT);

        _assertFundedAndSolvent();
    }

    function test_RevertWhen_ReleasingBeforeFunding() public {
        _expectInvalidState(TokenEscrow.State.Funded, TokenEscrow.State.Created);
        vm.prank(buyer);
        escrow.release();

        _assertCreatedAndEmpty();
    }

    function test_RevertWhen_RefundingBeforeFunding() public {
        _expectInvalidState(TokenEscrow.State.Funded, TokenEscrow.State.Created);
        vm.prank(buyer);
        escrow.refund();

        _assertCreatedAndEmpty();
    }

    function test_RevertWhen_ReleasingTwice() public {
        _depositAndRelease();

        _expectInvalidState(TokenEscrow.State.Funded, TokenEscrow.State.Released);
        vm.prank(buyer);
        escrow.release();

        _assertReleasedAndEmpty();
    }

    function test_RevertWhen_RefundingAfterRelease() public {
        _depositAndRelease();

        _expectInvalidState(TokenEscrow.State.Funded, TokenEscrow.State.Released);
        vm.prank(buyer);
        escrow.refund();

        _assertReleasedAndEmpty();
    }

    function test_RevertWhen_StrangerTriesToRelease() public {
        _deposit(AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(TokenEscrow.OnlyBuyer.selector, stranger));
        vm.prank(stranger);
        escrow.release();

        _assertFundedAndSolvent();
    }

    // Test sul constructor: `new` dentro expectRevert verifica che il deploy fallisca.
    // stranger e' un EOA, cioe' un indirizzo senza codice: non puo' essere un token.
    function test_RevertWhen_TokenHasNoCode() public {
        vm.expectRevert(abi.encodeWithSelector(TokenEscrow.InvalidToken.selector, stranger));
        new TokenEscrow(IERC20(stranger), buyer, seller);
    }

    function test_RevertWhen_BuyerIsZero() public {
        vm.expectRevert(TokenEscrow.ZeroAddress.selector);
        new TokenEscrow(IERC20(address(token)), address(0), seller);
    }

    function test_RevertWhen_SellerIsZero() public {
        vm.expectRevert(TokenEscrow.ZeroAddress.selector);
        new TokenEscrow(IERC20(address(token)), buyer, address(0));
    }

    function test_RevertWhen_PartiesAreEqual() public {
        vm.expectRevert(TokenEscrow.SameParty.selector);
        new TokenEscrow(IERC20(address(token)), buyer, buyer);
    }

    // HELPER: non sono test (non iniziano con test_), li chiamano i test sopra.

    // Due parametri separati per poter provare allowance maggiore del deposito.
    function _approveAndDeposit(uint256 approval, uint256 requested) internal {
        vm.startPrank(buyer);
        token.approve(address(escrow), approval);
        escrow.deposit(requested);
        vm.stopPrank();
    }

    function _deposit(uint256 amount) internal {
        _approveAndDeposit(amount, amount);
    }

    function _depositAndRelease() internal {
        _deposit(AMOUNT);
        vm.prank(buyer);
        escrow.release();
    }

    // L'errore InvalidState porta due parametri: stato richiesto e stato attuale.
    function _expectInvalidState(TokenEscrow.State expected, TokenEscrow.State actual) internal {
        vm.expectRevert(abi.encodeWithSelector(TokenEscrow.InvalidState.selector, expected, actual));
    }

    function _assertState(TokenEscrow.State expected) internal view {
        assertEq(uint256(escrow.state()), uint256(expected));
    }

    function _assertCreatedAndEmpty() internal view {
        _assertState(TokenEscrow.State.Created);
        assertEq(escrow.escrowedAmount(), 0);
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    // Proprieta' di solvibilita': in Funded il saldo reale copre la passivita' registrata.
    function _assertFundedAndSolvent() internal view {
        _assertState(TokenEscrow.State.Funded);
        assertGe(token.balanceOf(address(escrow)), escrow.escrowedAmount());
    }

    function _assertReleasedAndEmpty() internal view {
        _assertState(TokenEscrow.State.Released);
        assertEq(escrow.escrowedAmount(), 0);
        assertEq(token.balanceOf(address(escrow)), 0);
    }
}
