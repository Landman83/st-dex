// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../src/exchange/Exchange.sol";
import "../src/exchange/ExchangeProxy.sol";
import "../src/exchange/mixins/AtomicSwap.sol";
import "../src/exchange/mixins/Compliance.sol";
import "../src/exchange/mixins/Fees.sol";
import "../src/exchange/mixins/OrderCancellation.sol";
import "../src/exchange/mixins/Signatures.sol";
import "../src/exchange/mixins/Registry.sol";

/**
 * @title ExchangeDeploymentScript
 * @notice Script to deploy the Exchange contract and its proxy
 */
contract ExchangeDeploymentScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get deployer address
        address deployer = vm.addr(deployerPrivateKey);

        // Deploy Signatures contract first (needed for OrderCancellation)
        Signatures signatures = new Signatures("Numena Exchange", "1.0.0");

        // Deploy all necessary component contracts with their dependencies
        Fees fees = new Fees(deployer);
        Registry registry = new Registry("ETH");
        Compliance compliance = new Compliance(deployer);
        
        // Deploy OrderCancellation which depends on Signatures
        OrderCancellation cancellation = new OrderCancellation(deployer, address(signatures));
        
        // Deploy AtomicSwap which depends on all the other components
        AtomicSwap atomicSwap = new AtomicSwap(
            deployer,
            address(fees),
            address(cancellation),
            address(compliance),
            address(signatures)
        );

        // Deploy the Exchange implementation
        Exchange exchangeImplementation = new Exchange();

        // Deploy the Exchange proxy
        ExchangeProxy exchangeProxy = new ExchangeProxy(
            address(exchangeImplementation),
            deployer // Proxy admin
        );

        // We need to encode the initialization call for the proxy
        bytes memory initializeCalldata = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address)",
            deployer,                  // Owner
            address(fees),             // Fees contract
            address(cancellation),     // Cancellation contract
            address(compliance),       // Compliance contract
            address(signatures),       // Signatures contract
            address(registry)          // Registry contract
        );
        
        // Execute initialization through the proxy's execute function
        (bool success, ) = address(exchangeProxy).call(initializeCalldata);
        require(success, "Initialization failed");

        console.log("Exchange Implementation deployed at:", address(exchangeImplementation));
        console.log("Exchange Proxy deployed at:", address(exchangeProxy));
        console.log("Fees Contract deployed at:", address(fees));
        console.log("Cancellation Contract deployed at:", address(cancellation));
        console.log("Compliance Contract deployed at:", address(compliance));
        console.log("Signatures Contract deployed at:", address(signatures));
        console.log("Registry Contract deployed at:", address(registry));
        console.log("AtomicSwap Contract deployed at:", address(atomicSwap));

        vm.stopBroadcast();
    }
}