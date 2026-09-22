// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IStaticAction} from "../fixed/SafeStaticLab.sol";
import {INotifier, NotifierFlow} from "../context/NotifierFlow.sol";

contract RecordingAction is IStaticAction {
    address public lastCaller;
    bytes public lastData;

    function run(bytes calldata data) external {
        lastCaller = msg.sender;
        lastData = data;
    }
}

contract RevertingAction is IStaticAction {
    error ActionFailed();

    function run(bytes calldata) external pure {
        revert ActionFailed();
    }
}

contract LabToken {
    event Transfer(address indexed from, address indexed to, uint256 amount);

    mapping(address account => uint256 amount) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "BALANCE");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
}

contract OneShotCallbackNotifier is INotifier {
    error AlreadyConfigured();

    NotifierFlow public flow;
    bool public callbackAttempted;
    bool public callbackSucceeded;

    function configure(NotifierFlow flow_) external {
        if (address(flow) != address(0)) revert AlreadyConfigured();
        flow = flow_;
    }

    function notify() external {
        callbackAttempted = true;
        (callbackSucceeded,) = address(flow).call(abi.encodeCall(NotifierFlow.finish, ()));
    }
}
