// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode usati in questo file:
//   makeAddr("nome")    indirizzo deterministico, etichettato nei trace;
//   vm.prank(a)         la PROSSIMA call avra' msg.sender = a;
//   vm.expectRevert(e)  la PROSSIMA call deve revertire con l'errore e;
//   vm.deal(a, x)       assegna x wei all'indirizzo a.
// expectRevert e prank sono cheatcode, non call: l'ordine tra i due non conta, entrambi
// si applicano alla prima call vera che segue.
import { Test } from "forge-std/Test.sol";
import { EducationalERC1967Proxy } from "../src/proxy/EducationalERC1967Proxy.sol";
import { UpgradeableEscrowV1 } from "../src/upgrade/UpgradeableEscrowV1.sol";
import { UpgradeableEscrowV2 } from "../src/upgrade/UpgradeableEscrowV2.sol";
import { UnsafeLayoutV2 } from "../src/upgrade/UnsafeLayoutV2.sol";
import {
    NotUUPSImplementation,
    WrongUUIDImplementation
} from "../src/upgrade/NotUUPSImplementation.sol";

contract UpgradeableEscrowTest is Test {
    UpgradeableEscrowV1 internal implementationV1; // il codice, al suo indirizzo
    EducationalERC1967Proxy internal proxy; // il proxy: indirizzo e storage dell'escrow
    UpgradeableEscrowV1 internal escrow; // lo stesso indirizzo del proxy, con l'ABI dell'escrow

    address internal owner;
    address internal buyer;
    address internal seller;
    address internal feeRecipient;
    address internal stranger;

    // Il deploy "corretto": implementation, poi proxy inizializzato nella stessa transazione.
    function setUp() public {
        owner = makeAddr("owner");
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        feeRecipient = makeAddr("fee-recipient");
        stranger = makeAddr("stranger");

        implementationV1 = new UpgradeableEscrowV1();
        // abi.encodeCall: calldata di initialize(owner, buyer, seller), con controllo dei tipi.
        bytes memory initializationData =
            abi.encodeCall(UpgradeableEscrowV1.initialize, (owner, buyer, seller));
        proxy = new EducationalERC1967Proxy(address(implementationV1), initializationData);
        escrow = UpgradeableEscrowV1(address(proxy));
    }

    // --- DEPLOY E INIZIALIZZAZIONE ---

    function test_DeploymentAtomicallyInitializesProxyStorage() public view {
        assertEq(proxy.implementation(), address(implementationV1));
        assertEq(escrow.owner(), owner);
        assertEq(escrow.buyer(), buyer);
        assertEq(escrow.seller(), seller);
        assertEq(escrow.initializationVersion(), 1);
        assertEq(escrow.version(), 1);
    }

    // Un secondo initialize permetterebbe di riscrivere l'owner. Deve fallire, e dopo il
    // revert l'owner deve essere ancora quello originale.
    function test_RevertWhen_ProxyInitializeRunsTwice() public {
        vm.expectRevert(
            abi.encodeWithSelector(UpgradeableEscrowV1.AlreadyInitialized.selector, uint64(1))
        );
        escrow.initialize(stranger, stranger, owner);

        assertEq(escrow.owner(), owner);
    }

    // L'istanza dell'implementation, chiamata direttamente, e' bloccata dal suo constructor:
    // la versione vale type(uint64).max, quindi initialize non passa mai.
    function test_ImplementationInstanceIsLocked() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                UpgradeableEscrowV1.AlreadyInitialized.selector, type(uint64).max
            )
        );
        implementationV1.initialize(owner, buyer, seller);
    }

    function test_RevertWhen_ProxyImplementationHasNoCode() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                EducationalERC1967Proxy.ImplementationHasNoCode.selector, stranger
            )
        );
        new EducationalERC1967Proxy(stranger, bytes(""));
    }

    // Atomicita': se initialize fallisce, il proxy non viene nemmeno creato.
    // L'errore atteso e' quello dell'implementation, rilanciato dal proxy.
    function test_FailedAtomicInitializationRevertsProxyDeployment() public {
        bytes memory invalidInitialization =
            abi.encodeCall(UpgradeableEscrowV1.initialize, (address(0), buyer, seller));

        vm.expectRevert(UpgradeableEscrowV1.InvalidAddress.selector);
        new EducationalERC1967Proxy(address(implementationV1), invalidInitialization);
    }

    function test_RevertWhen_InitialPartiesAreEqual() public {
        bytes memory invalidInitialization =
            abi.encodeCall(UpgradeableEscrowV1.initialize, (owner, buyer, buyer));

        vm.expectRevert(UpgradeableEscrowV1.SameParty.selector);
        new EducationalERC1967Proxy(address(implementationV1), invalidInitialization);
    }

    // Questo test PASSA perche' l'attacco riesce: proxy creato senza initializationData,
    // e il primo che chiama initialize diventa owner. La difesa e' il deploy atomico di setUp.

    /// @dev Il test passa dimostrando il takeover di un proxy lasciato non inizializzato.
    function test_Vulnerable_UninitializedProxyCanBeClaimedByStranger() public {
        EducationalERC1967Proxy uninitialized =
            new EducationalERC1967Proxy(address(implementationV1), bytes(""));
        UpgradeableEscrowV1 exposed = UpgradeableEscrowV1(address(uninitialized));

        vm.prank(stranger);
        exposed.initialize(stranger, buyer, seller);

        assertEq(exposed.owner(), stranger);
        assertEq(exposed.initializationVersion(), 1);
    }

    // --- UPGRADE ---

    // Il percorso felice: stato V1 reale (funded), upgrade + migrazione, poi si confronta TUTTO
    // lo stato prima/dopo. Un upgrade che "funziona" ma perde un campo e' un bug.
    function test_AuthorizedUpgradePreservesStateAndRunsMigration() public {
        _fund(10_000);
        UpgradeableEscrowV2 implementationV2 = new UpgradeableEscrowV2();

        vm.prank(owner);
        escrow.upgradeToAndCall(
            address(implementationV2),
            abi.encodeCall(UpgradeableEscrowV2.initializeV2, (250, feeRecipient))
        );

        // Stesso indirizzo, nuova ABI: ora il proxy "parla" V2.
        UpgradeableEscrowV2 upgraded = UpgradeableEscrowV2(address(proxy));
        _assertV1StatePreserved(upgraded);
        assertEq(proxy.implementation(), address(implementationV2));
        assertEq(upgraded.initializationVersion(), 2);
        assertEq(upgraded.feeBps(), 250);
        assertEq(upgraded.feeRecipient(), feeRecipient);
        assertEq(upgraded.feeOnAmount(), 250); // 10_000 * 250 / 10_000: amount V1 letto dalla V2
        assertEq(upgraded.version(), 2);
    }

    // Test di regressione sull'autorizzazione dell'upgrade (onlyOwner).
    // Dopo il revert l'implementation non deve essere cambiata.
    function test_RevertWhen_StrangerAttemptsUpgrade() public {
        UpgradeableEscrowV2 implementationV2 = new UpgradeableEscrowV2();

        vm.expectRevert(abi.encodeWithSelector(UpgradeableEscrowV1.Unauthorized.selector, stranger));
        vm.prank(stranger);
        escrow.upgradeToAndCall(address(implementationV2), bytes(""));

        assertEq(proxy.implementation(), address(implementationV1));
        assertEq(escrow.version(), 1);
    }

    // Migrazione fallita (fee 1_001 bps, oltre il tetto): l'implementation era gia' stata
    // scritta prima della migrazione, ma il revert annulla tutto. Si resta sulla V1.
    function test_FailedMigrationRollsBackImplementationUpgrade() public {
        UpgradeableEscrowV2 implementationV2 = new UpgradeableEscrowV2();

        vm.expectRevert(
            abi.encodeWithSelector(UpgradeableEscrowV2.FeeTooHigh.selector, uint256(1_001))
        );
        vm.prank(owner);
        escrow.upgradeToAndCall(
            address(implementationV2),
            abi.encodeCall(UpgradeableEscrowV2.initializeV2, (1_001, feeRecipient))
        );

        assertEq(proxy.implementation(), address(implementationV1));
        assertEq(escrow.initializationVersion(), 1);
        assertEq(escrow.version(), 1);
    }

    // Stesso rollback, causato da un altro controllo della migrazione.
    function test_ZeroRecipientMigrationRollsBackImplementationUpgrade() public {
        UpgradeableEscrowV2 implementationV2 = new UpgradeableEscrowV2();

        vm.expectRevert(UpgradeableEscrowV1.InvalidAddress.selector);
        vm.prank(owner);
        escrow.upgradeToAndCall(
            address(implementationV2),
            abi.encodeCall(UpgradeableEscrowV2.initializeV2, (250, address(0)))
        );

        assertEq(proxy.implementation(), address(implementationV1));
        assertEq(escrow.initializationVersion(), 1);
        assertEq(escrow.version(), 1);
    }

    // Anche l'owner puo' sbagliare: i controlli sulla nuova implementation lo proteggono.
    function test_RevertWhen_NewImplementationHasNoCode() public {
        vm.expectRevert(
            abi.encodeWithSelector(UpgradeableEscrowV1.ImplementationHasNoCode.selector, stranger)
        );
        vm.prank(owner);
        escrow.upgradeToAndCall(stranger, bytes(""));

        assertEq(proxy.implementation(), address(implementationV1));
    }

    function test_RevertWhen_V2InitializerRunsTwice() public {
        UpgradeableEscrowV2 upgraded = _upgradeToV2(250);

        vm.expectRevert(
            abi.encodeWithSelector(UpgradeableEscrowV1.AlreadyInitialized.selector, uint64(2))
        );
        vm.prank(owner);
        upgraded.initializeV2(300, feeRecipient);

        assertEq(upgraded.feeBps(), 250); // il valore della prima migrazione e' intatto
    }

    // Dopo l'upgrade le regole della V1 devono valere ancora: stranger rifiutato, buyer accettato.
    function test_PostUpgradeBusinessAuthorizationStillWorks() public {
        UpgradeableEscrowV2 upgraded = _upgradeToV2(250);

        vm.expectRevert(abi.encodeWithSelector(UpgradeableEscrowV1.Unauthorized.selector, stranger));
        vm.prank(stranger);
        upgraded.fund(100);

        vm.prank(buyer);
        upgraded.fund(100);
        assertEq(upgraded.amount(), 100);
        assertTrue(upgraded.funded());
    }

    // --- LOGICA APPLICATIVA ---

    function test_RevertWhen_FundingAmountIsZero() public {
        vm.expectRevert(UpgradeableEscrowV1.ZeroAmount.selector);
        vm.prank(buyer);
        escrow.fund(0);

        assertFalse(escrow.funded());
    }

    function test_RevertWhen_FundingTwice() public {
        _fund(100);

        vm.expectRevert(UpgradeableEscrowV1.AlreadyFunded.selector);
        vm.prank(buyer);
        escrow.fund(200);

        assertEq(escrow.amount(), 100); // il primo importo non viene sovrascritto
    }

    // --- COMPATIBILITA' DELLA NUOVA IMPLEMENTATION ---

    // Senza proxiableUUID: la call reverte e il ramo catch la trasforma in NotUUPSImplementation.
    function test_RevertWhen_NewImplementationIsNotUUPSCompatible() public {
        NotUUPSImplementation incompatible = new NotUUPSImplementation();
        assertEq(incompatible.version(), 404); // e' un contratto funzionante, solo non UUPS

        vm.expectRevert(
            abi.encodeWithSelector(
                UpgradeableEscrowV1.NotUUPSImplementation.selector, address(incompatible)
            )
        );
        vm.prank(owner);
        escrow.upgradeToAndCall(address(incompatible), bytes(""));

        assertEq(proxy.implementation(), address(implementationV1));
    }

    function test_RevertWhen_ProxiableUUIDUsesWrongSlot() public {
        WrongUUIDImplementation incompatible = new WrongUUIDImplementation();
        bytes32 wrongSlot = bytes32(uint256(123));

        vm.expectRevert(
            abi.encodeWithSelector(UpgradeableEscrowV1.UnsupportedProxiableUUID.selector, wrongSlot)
        );
        vm.prank(owner);
        escrow.upgradeToAndCall(address(incompatible), bytes(""));

        assertEq(proxy.implementation(), address(implementationV1));
    }

    // receive() del proxy inoltra all'implementation, che non ha receive ne' fallback payable:
    // l'invio di ETH reverte. Una call a basso livello non propaga il revert, restituisce
    // success = false: per questo qui non serve expectRevert.
    function test_ReceiveRevertsWhenImplementationCannotAcceptEther() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(proxy).call{ value: 1 ether }(bytes(""));

        assertFalse(success);
        assertEq(address(proxy).balance, 0);
    }

    // Questo test PASSA perche' l'upgrade dannoso riesce: UnsafeLayoutV2 supera il controllo
    // UUID, ma legge gli slot 1 e 2 con i nomi scambiati. Il controllo UUPS non guarda il layout.

    /// @dev Il test dimostra che UUID/ERC-1967 non validano il layout applicativo.
    function test_Vulnerable_IncompatibleLayoutReinterpretsExistingState() public {
        UnsafeLayoutV2 badImplementation = new UnsafeLayoutV2();

        vm.prank(owner);
        escrow.upgradeToAndCall(address(badImplementation), bytes(""));

        UnsafeLayoutV2 broken = UnsafeLayoutV2(address(proxy));
        assertEq(broken.seller(), buyer);
        assertEq(broken.buyer(), seller);
        assertEq(broken.version(), 99);
    }

    // --- GUARD DI CONTESTO (onlyActiveProxy e proxiableUUID) ---

    // Chiamata diretta all'implementation: address(this) == SELF, quindi onlyActiveProxy reverte.
    // Nessun prank: il controllo di contesto scatta prima di quello sull'owner.
    function test_RevertWhen_UpgradeIsCalledDirectlyOnImplementation() public {
        UpgradeableEscrowV2 implementationV2 = new UpgradeableEscrowV2();

        vm.expectRevert(UpgradeableEscrowV1.MustBeCalledThroughActiveProxy.selector);
        implementationV1.upgradeToAndCall(address(implementationV2), bytes(""));
    }

    // Il caso opposto: proxiableUUID deve rifiutarsi quando passa dal proxy.
    function test_RevertWhen_ProxiableUUIDIsCalledThroughProxy() public {
        vm.expectRevert(UpgradeableEscrowV1.MustNotBeCalledThroughProxy.selector);
        escrow.proxiableUUID();
    }

    // Helper `internal`: non sono test, li usano i test qui sopra.
    function _fund(uint256 value) internal {
        vm.prank(buyer);
        escrow.fund(value);
    }

    function _upgradeToV2(uint256 feeBps) internal returns (UpgradeableEscrowV2 upgraded) {
        UpgradeableEscrowV2 implementationV2 = new UpgradeableEscrowV2();
        vm.prank(owner);
        escrow.upgradeToAndCall(
            address(implementationV2),
            abi.encodeCall(UpgradeableEscrowV2.initializeV2, (feeBps, feeRecipient))
        );
        upgraded = UpgradeableEscrowV2(address(proxy));
    }

    // Ogni campo della V1, uno per uno: e' il controllo che l'upgrade non ha spostato slot.
    function _assertV1StatePreserved(UpgradeableEscrowV2 upgraded) internal view {
        assertEq(upgraded.owner(), owner);
        assertEq(upgraded.buyer(), buyer);
        assertEq(upgraded.seller(), seller);
        assertEq(upgraded.amount(), 10_000);
        assertTrue(upgraded.funded());
    }
}
