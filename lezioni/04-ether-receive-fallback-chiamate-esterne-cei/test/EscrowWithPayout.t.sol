// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode e helper usati in questo file:
//   makeAddr("nome")      indirizzo con etichetta leggibile nelle trace (un EOA, senza codice);
//   vm.deal(a, x)         assegna x wei all'indirizzo a, dal nulla;
//   vm.prank(a)           la PROSSIMA call (anche un `new`) avra' msg.sender = a;
//   vm.expectRevert(e)    la PROSSIMA call deve revertire con l'errore e (selettore + argomenti).
// Alcuni test chiamano il contratto con una low-level call invece che con vm.expectRevert:
// cosi' si osservano direttamente `success` e i byte dell'errore restituito.
// Per vedere la catena delle call: forge test --match-test <nome> -vvvv
import { Test } from "forge-std/Test.sol";
import { EscrowWithPayout } from "../src/EscrowWithPayout.sol";
import { AcceptingSeller, RejectingSeller, ForceEther } from "./helpers/EtherReceivers.sol";

contract EscrowWithPayoutTest is Test {
    EscrowWithPayout internal escrow;

    address internal buyer;
    address payable internal seller;
    address internal outsider;

    uint256 internal constant PRICE = 5 ether;

    // Ogni test parte da un Escrow nuovo in stato Created, con un seller EOA.
    function setUp() public {
        buyer = makeAddr("buyer");
        seller = payable(makeAddr("seller"));
        outsider = makeAddr("outsider");

        vm.deal(buyer, 100 ether);
        vm.deal(outsider, 100 ether);

        vm.prank(buyer); // il deployer diventa il buyer
        escrow = new EscrowWithPayout(seller, PRICE);
    }

    function test_InitialState() public view {
        assertEq(escrow.buyer(), buyer);
        assertEq(escrow.seller(), seller);
        assertEq(escrow.price(), PRICE);
        _assertState(escrow, EscrowWithPayout.State.Created);
        assertEq(address(escrow).balance, 0);
    }

    function test_BuyerCanFundExactPrice() public {
        _fund(escrow);

        _assertState(escrow, EscrowWithPayout.State.Funded);
        assertEq(address(escrow).balance, PRICE);
    }

    function test_BuyerCanCancelBeforeFunding() public {
        vm.prank(buyer);
        escrow.cancelBeforeFunding();

        _assertState(escrow, EscrowWithPayout.State.Cancelled);
        assertEq(address(escrow).balance, 0);
    }

    // --- PAYOUT: il percorso valido ---------------------------------------------------------

    // Seller EOA: la call trasferisce ETH e basta, non c'e' codice da eseguire.
    function test_ReleasePaysEOASeller() public {
        _fund(escrow);
        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(buyer);
        escrow.release();

        // L'ETH si e' spostato: l'Escrow e' vuoto, il seller ha ricevuto esattamente PRICE.
        _assertState(escrow, EscrowWithPayout.State.Released);
        assertEq(address(escrow).balance, 0);
        assertEq(seller.balance, sellerBalanceBefore + PRICE);
    }

    // Esperimento 1: se il seller e' un contratto, pagarlo significa eseguire il SUO codice.
    //   buyer --release()--> EscrowWithPayout --call{value: PRICE}("")--> AcceptingSeller.receive()
    function test_ReleaseToContractExecutesReceiverCode() public {
        // Arrange: un Escrow dedicato il cui seller e' il contratto AcceptingSeller.
        AcceptingSeller receiver = new AcceptingSeller();
        EscrowWithPayout contractSellerEscrow = _deploy(payable(address(receiver)));
        _fund(contractSellerEscrow);

        assertEq(receiver.totalReceived(), 0);

        vm.prank(buyer);
        contractSellerEscrow.release();

        // Lo storage del receiver e' cambiato: durante release() e' girato codice esterno.
        assertEq(receiver.totalReceived(), PRICE);
        _assertState(contractSellerEscrow, EscrowWithPayout.State.Released);
        assertEq(address(contractSellerEscrow).balance, 0);
    }

    // Esperimento 2: il seller rifiuta l'ETH e il revert annulla l'intera release.
    //   release(): state = Released -> call fallisce -> revert EtherTransferFailed
    //   risultato: come se release() non fosse mai stata chiamata.
    function test_RejectingSellerMakesReleaseRevertAtomically() public {
        RejectingSeller receiver = new RejectingSeller();
        EscrowWithPayout rejectingEscrow = _deploy(payable(address(receiver)));
        _fund(rejectingEscrow);

        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowWithPayout.EtherTransferFailed.selector, address(receiver), PRICE
            )
        );
        vm.prank(buyer);
        rejectingEscrow.release();

        // `state = Released` era gia' stato scritto prima della call: il revert lo ha annullato.
        _assertState(rejectingEscrow, EscrowWithPayout.State.Funded);
        assertEq(address(rejectingEscrow).balance, PRICE);
        assertEq(address(receiver).balance, 0);
    }

    // --- NEGATIVE SPACE: chi e quando ------------------------------------------------------
    // Qui l'errore si verifica per intero, argomenti compresi (chi ha chiamato, quale stato).

    function test_RevertWhen_OutsiderReleases() public {
        _fund(escrow);

        vm.expectRevert(abi.encodeWithSelector(EscrowWithPayout.Unauthorized.selector, outsider));
        vm.prank(outsider);
        escrow.release();

        _assertState(escrow, EscrowWithPayout.State.Funded);
        assertEq(address(escrow).balance, PRICE);
    }

    function test_RevertWhen_ReleasingBeforeFunding() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowWithPayout.WrongState.selector,
                EscrowWithPayout.State.Funded,
                EscrowWithPayout.State.Created
            )
        );
        vm.prank(buyer);
        escrow.release();

        _assertState(escrow, EscrowWithPayout.State.Created);
        assertEq(address(escrow).balance, 0);
    }

    // Stato terminale: una seconda release non deve pagare il seller due volte.
    function test_RevertWhen_ReleasingTwice() public {
        _fund(escrow);

        vm.prank(buyer);
        escrow.release();
        uint256 sellerBalanceAfterFirstRelease = seller.balance;

        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowWithPayout.WrongState.selector,
                EscrowWithPayout.State.Funded,
                EscrowWithPayout.State.Released
            )
        );
        vm.prank(buyer);
        escrow.release();

        assertEq(seller.balance, sellerBalanceAfterFirstRelease);
        _assertState(escrow, EscrowWithPayout.State.Released);
    }

    // --- Esperimento 3: DISPATCH, receive() e fallback() --------------------------------------

    // Calldata vuota + ETH: e' un invio "diretto" che seleziona receive().
    function test_PlainEtherTransferIsRejected() public {
        vm.prank(outsider);
        // Una low-level call NON reverte nel chiamante: restituisce success = false e, in
        // returnData, i byte dell'errore sollevato dal contratto chiamato.
        (bool success, bytes memory returnData) = address(escrow).call{ value: 1 ether }("");

        assertFalse(success);
        // I primi 4 byte dell'errore sono il suo selettore.
        assertEq(bytes4(returnData), EscrowWithPayout.DirectEtherNotAccepted.selector);
        assertEq(address(escrow).balance, 0);
        _assertState(escrow, EscrowWithPayout.State.Created);
    }

    // receive() la sceglie la calldata VUOTA, non la presenza di ETH: anche con 0 wei.
    function test_EmptyCalldataWithZeroValueStillReachesReceive() public {
        vm.prank(outsider);
        (bool success, bytes memory returnData) = address(escrow).call("");

        assertFalse(success);
        assertEq(bytes4(returnData), EscrowWithPayout.DirectEtherNotAccepted.selector);
    }

    // Selettore che non corrisponde a nessuna funzione: finisce in fallback().
    function test_UnknownSelectorIsRejected() public {
        bytes memory unknownCall = hex"deadbeef"; // 4 byte arbitrari usati come selettore

        vm.prank(outsider);
        (bool success, bytes memory returnData) = address(escrow).call(unknownCall);

        assertFalse(success);
        // Si confronta l'errore completo, selettore + argomento: fallback ha restituito proprio
        // il selettore ricevuto (msg.sig). Due `bytes` si confrontano tramite il loro hash.
        assertEq(
            keccak256(returnData),
            keccak256(
                abi.encodeWithSelector(EscrowWithPayout.UnknownCall.selector, bytes4(0xdeadbeef))
            )
        );
        _assertState(escrow, EscrowWithPayout.State.Created);
    }

    // --- Esperimento 4: saldo grezzo e diritto economico -------------------------------------

    // receive() rifiuta ogni invio diretto, eppure il saldo dell'Escrow puo' crescere lo stesso.
    function test_ForcedEtherBypassesReceive() public {
        uint256 forcedAmount = 1 ether;
        // address(this) e' il contratto di test: gli si danno i fondi per creare ForceEther.
        vm.deal(address(this), forcedAmount);
        ForceEther force = new ForceEther{ value: forcedAmount }();

        force.force(payable(address(escrow)));

        // Il saldo e' salito senza passare da receive() ne' da fund(); lo stato non e' cambiato.
        assertEq(address(escrow).balance, forcedAmount);
        _assertState(escrow, EscrowWithPayout.State.Created);
    }

    // Il surplus forzato non diventa un diritto del seller: release() paga `price`,
    // l'importo della contabilita' interna, non address(this).balance.
    function test_ForcedEtherDoesNotIncreaseSellerEntitlement() public {
        uint256 forcedAmount = 1 ether;
        vm.deal(address(this), forcedAmount);
        ForceEther force = new ForceEther{ value: forcedAmount }();
        force.force(payable(address(escrow)));

        _fund(escrow);
        assertEq(address(escrow).balance, PRICE + forcedAmount); // saldo grezzo > prezzo

        uint256 sellerBalanceBefore = seller.balance;
        vm.prank(buyer);
        escrow.release();

        assertEq(seller.balance, sellerBalanceBefore + PRICE); // solo il dovuto
        assertEq(address(escrow).balance, forcedAmount); // il surplus resta nel contratto
        _assertState(escrow, EscrowWithPayout.State.Released);
    }

    // --- Regressioni ereditate dalla Lezione 3 ----------------------------------------------

    function test_RevertWhen_CancellingAfterFunding() public {
        _fund(escrow);

        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowWithPayout.WrongState.selector,
                EscrowWithPayout.State.Created,
                EscrowWithPayout.State.Funded
            )
        );
        vm.prank(buyer);
        escrow.cancelBeforeFunding();

        _assertState(escrow, EscrowWithPayout.State.Funded);
        assertEq(address(escrow).balance, PRICE);
    }

    function test_RevertWhen_FundingWithWrongValue() public {
        uint256 wrongValue = PRICE - 1;

        vm.expectRevert(
            abi.encodeWithSelector(EscrowWithPayout.WrongValue.selector, PRICE, wrongValue)
        );
        vm.prank(buyer);
        escrow.fund{ value: wrongValue }();

        _assertState(escrow, EscrowWithPayout.State.Created);
        assertEq(address(escrow).balance, 0);
    }

    // Tre casi nello stesso test: ogni expectRevert vale solo per la call successiva.
    function test_RevertWhen_ConstructorArgumentsAreInvalid() public {
        vm.expectRevert(EscrowWithPayout.ZeroSeller.selector);
        vm.prank(buyer);
        new EscrowWithPayout(payable(address(0)), PRICE);

        vm.expectRevert(EscrowWithPayout.BuyerEqualsSeller.selector);
        vm.prank(buyer);
        new EscrowWithPayout(payable(buyer), PRICE);

        vm.expectRevert(EscrowWithPayout.ZeroPrice.selector);
        vm.prank(buyer);
        new EscrowWithPayout(seller, 0);
    }

    // Helper `internal`: deploy di un Escrow con un seller diverso da quello di setUp.
    function _deploy(address payable seller_) internal returns (EscrowWithPayout target) {
        vm.prank(buyer);
        target = new EscrowWithPayout(seller_, PRICE);
    }

    function _fund(EscrowWithPayout target) internal {
        vm.prank(buyer);
        target.fund{ value: PRICE }();
    }

    // assertEq non accetta enum: si confrontano i valori numerici.
    function _assertState(EscrowWithPayout target, EscrowWithPayout.State expected) internal view {
        assertEq(uint256(target.state()), uint256(expected));
    }
}
