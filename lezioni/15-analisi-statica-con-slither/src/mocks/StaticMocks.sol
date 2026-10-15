// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IStaticAction} from "../fixed/SafeStaticLab.sol";
import {INotifier, NotifierFlow} from "../context/NotifierFlow.sol";

// Contratti di supporto per i test: non sono oggetto dell'analisi (filtrati negli script).

// Azione che registra chi l'ha chiamata e con quali dati: i test verificano cosi' che
// SafeStaticLab abbia davvero eseguito la call.
contract RecordingAction is IStaticAction {
    address public lastCaller;
    bytes public lastData;

    function run(bytes calldata data) external {
        lastCaller = msg.sender;
        lastData = data;
    }
}

// Azione che fallisce sempre: serve a vedere cosa succede quando la call esterna reverte.
contract RevertingAction is IStaticAction {
    error ActionFailed();

    // Parametro senza nome: la firma resta quella dell'interfaccia, ma il dato non si usa.
    // `pure`: non legge ne' scrive lo stato.
    function run(bytes calldata) external pure {
        revert ActionFailed();
    }
}

// Token minimale (non ERC20 completo): il "bottino" dimostrativo di ST-03.
contract LabToken {
    event Transfer(address indexed from, address indexed to, uint256 amount);

    mapping(address account => uint256 amount) public balanceOf;

    // Senza controllo di accesso: accettabile solo in un mock di test.
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

// Notifier "ostile": quando NotifierFlow lo chiama, prova a richiamare finish().
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
        // Low-level call: se finish() reverte, il revert NON si propaga qui ma diventa
        // callbackSucceeded = false. Cosi' il test puo' osservare l'esito della callback.
        (callbackSucceeded,) = address(flow).call(abi.encodeCall(NotifierFlow.finish, ()));
    }
}
