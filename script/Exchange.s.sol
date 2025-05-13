// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../src/Exchange.sol";
import "../src/mixins/AtomicSwap.sol";
import "../src/mixins/Compliance.sol";
import "../src/mixins/Fees.sol";
import "../src/mixins/OrderCancellation.sol";
import "../src/mixins/Signatures.sol";
import "../src/mixins/Registry.sol";

/**
 * @title ExchangeDeploymentScript
 * @notice Script to deploy the Exchange contract and its components
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
        Exchange exchange = new Exchange();

        // Initialize the Exchange
        exchange.initialize(
            deployer,                  // Owner
            address(fees),             // Fees contract
            address(cancellation),     // Cancellation contract
            address(compliance),       // Compliance contract
            address(signatures),       // Signatures contract
            address(registry)          // Registry contract
        );

        console.log("Exchange deployed at:", address(exchange));
        console.log("Fees Contract deployed at:", address(fees));
        console.log("Cancellation Contract deployed at:", address(cancellation));
        console.log("Compliance Contract deployed at:", address(compliance));
        console.log("Signatures Contract deployed at:", address(signatures));
        console.log("Registry Contract deployed at:", address(registry));
        console.log("AtomicSwap Contract deployed at:", address(atomicSwap));

        vm.stopBroadcast();
    }
}