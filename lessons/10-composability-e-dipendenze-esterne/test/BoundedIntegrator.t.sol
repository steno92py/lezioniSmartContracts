// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { IRouter } from "../src/interfaces/IRouter.sol";
import { BoundedIntegrator } from "../src/BoundedIntegrator.sol";
import { GoodRouter, WeirdRouter, RevertingRouter } from "../src/mocks/RouterMocks.sol";

contract BoundedIntegratorTest is Test {
    function test_AcceptsSemanticallyValidOutput() public {
        GoodRouter router = new GoodRouter();
        BoundedIntegrator integrator = new BoundedIntegrator(IRouter(address(router)));

        assertEq(integrator.execute(500, 900), 1_000);
        assertEq(integrator.lastOutput(), 1_000);
    }

    function test_RevertWhen_ABICompatibleRouterReturnsTooLittle() public {
        WeirdRouter router = new WeirdRouter();
        BoundedIntegrator integrator = new BoundedIntegrator(IRouter(address(router)));

        vm.expectRevert(
            abi.encodeWithSelector(BoundedIntegrator.InsufficientOutput.selector, 900, 1)
        );
        integrator.execute(500, 900);

        assertEq(integrator.lastOutput(), 0);
    }

    function test_PreviouslyGoodRouterCanChangeBehaviorAtSameAddress() public {
        GoodRouter router = new GoodRouter();
        BoundedIntegrator integrator = new BoundedIntegrator(IRouter(address(router)));

        integrator.execute(500, 900);
        assertEq(integrator.lastOutput(), 1_000);

        router.setOutput(1);

        vm.expectRevert(
            abi.encodeWithSelector(BoundedIntegrator.InsufficientOutput.selector, 900, 1)
        );
        integrator.execute(500, 900);

        assertEq(integrator.lastOutput(), 1_000);
    }

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
        address emptyTarget = makeAddr("router");
        vm.expectRevert(
            abi.encodeWithSelector(BoundedIntegrator.InvalidRouter.selector, emptyTarget)
        );
        new BoundedIntegrator(IRouter(emptyTarget));
    }
}
