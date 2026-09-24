// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode: vm.expectRevert(e), la PROSSIMA call deve revertire con l'errore e.
// Ogni test crea il proprio router: il tipo di router e' la variabile dell'esperimento.
import { Test } from "forge-std/Test.sol";
import { IRouter } from "../src/interfaces/IRouter.sol";
import { BoundedIntegrator } from "../src/BoundedIntegrator.sol";
import { GoodRouter, WeirdRouter, RevertingRouter } from "../src/mocks/RouterMocks.sol";

contract BoundedIntegratorTest is Test {
    function test_AcceptsSemanticallyValidOutput() public {
        GoodRouter router = new GoodRouter();
        // IRouter(address(router)): stesso indirizzo, visto attraverso l'interfaccia.
        BoundedIntegrator integrator = new BoundedIntegrator(IRouter(address(router)));

        // Minimo 900, il router restituisce 1000: accettato.
        assertEq(integrator.execute(500, 900), 1_000);
        assertEq(integrator.lastOutput(), 1_000);
    }

    // ABI contro semantica: WeirdRouter non reverte e restituisce un uint256 valido, ma 1 e'
    // sotto il minimo. Solo il controllo nel consumer se ne accorge.
    function test_RevertWhen_ABICompatibleRouterReturnsTooLittle() public {
        WeirdRouter router = new WeirdRouter();
        BoundedIntegrator integrator = new BoundedIntegrator(IRouter(address(router)));

        vm.expectRevert(
            abi.encodeWithSelector(BoundedIntegrator.InsufficientOutput.selector, 900, 1)
        );
        integrator.execute(500, 900);

        assertEq(integrator.lastOutput(), 0);
    }

    // Stesso indirizzo, comportamento diverso: aver funzionato ieri non garantisce nulla oggi.
    function test_PreviouslyGoodRouterCanChangeBehaviorAtSameAddress() public {
        GoodRouter router = new GoodRouter();
        BoundedIntegrator integrator = new BoundedIntegrator(IRouter(address(router)));

        // 1. Prima esecuzione valida.
        integrator.execute(500, 900);
        assertEq(integrator.lastOutput(), 1_000);

        // 2. Il router cambia comportamento.
        router.setOutput(1);

        // 3. La seconda esecuzione viene rifiutata...
        vm.expectRevert(
            abi.encodeWithSelector(BoundedIntegrator.InsufficientOutput.selector, 900, 1)
        );
        integrator.execute(500, 900);

        // 4. ...e l'ultimo output valido resta quello di prima.
        assertEq(integrator.lastOutput(), 1_000);
    }

    // Call high-level: il revert del router risale col suo errore originale.
    function test_RouterRevertPropagatesAndStateDoesNotChange() public {
        RevertingRouter router = new RevertingRouter();
        BoundedIntegrator integrator = new BoundedIntegrator(IRouter(address(router)));

        vm.expectRevert(RevertingRouter.RouterUnavailable.selector);
        integrator.execute(500, 900);

        assertEq(integrator.lastOutput(), 0);
    }

    function test_RevertWhen_MinimumOutputIsZero() public {
        GoodRouter router = new GoodRouter();
        BoundedIntegrator integrator = new BoundedIntegrator(IRouter(address(router)));

        vm.expectRevert(BoundedIntegrator.ZeroMinimumOutput.selector);
        integrator.execute(500, 0);
    }

    function test_RevertWhen_RouterHasNoCode() public {
        // makeAddr restituisce un indirizzo senza codice.
        address emptyTarget = makeAddr("router");
        vm.expectRevert(
            abi.encodeWithSelector(BoundedIntegrator.InvalidRouter.selector, emptyTarget)
        );
        new BoundedIntegrator(IRouter(emptyTarget));
    }
}
