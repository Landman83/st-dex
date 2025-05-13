// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../src/Exchange.sol";
import "../src/mixins/Compliance.sol";
import "../src/mixins/Fees.sol";
import "../src/mixins/OrderCancellation.sol";
import "../src/mixins/Signatures.sol";
import "../src/mixins/Registry.sol";

/**
 * @title ExchangeDeploymentScript
 * @notice Script to deploy the Exchange contract and its components to Polygon Mainnet
 */
contract ExchangeDeploymentScript is Script {
    // Environment variables:
    // - DEPLOYER_ADDRESS: The address that will deploy the contracts
    // - PRIVATE_KEY: The private key for signing transactions
    // - RPC_URL: The RPC URL for the Polygon Mainnet
    // - CHAIN_ID: The chain ID for Polygon Mainnet (137)
    //
    // Create a .env file with these variables before running:
    // ```
    // DEPLOYER_ADDRESS=0xYourDeployerAddress
    // PRIVATE_KEY=0xYourPrivateKey
    // RPC_URL=https://polygon-rpc.com
    // CHAIN_ID=137
    // ```
    //
    // Run script with:
    // forge script script/Exchange.s.sol:ExchangeDeploymentScript --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify

    function run() external {
        // Get environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        string memory rpcUrl = vm.envString("RPC_URL");
        uint256 chainId = vm.envUint("CHAIN_ID");

        // Verify we're deploying to Polygon
        require(chainId == 137, "This script is configured for Polygon Mainnet (Chain ID 137)");

        // Set up the RPC connection
        vm.createSelectFork(rpcUrl);

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Verify deployer
        address calculatedDeployer = vm.addr(deployerPrivateKey);
        require(calculatedDeployer == deployerAddress, "Provided private key does not match deployer address");

        // Use the verified deployer
        address deployer = deployerAddress;

        // Deploy Signatures contract first (needed for OrderCancellation)
        Signatures signatures = new Signatures("Numena Exchange", "1.0.0");

        // Deploy all necessary component contracts with their dependencies
        Fees fees = new Fees(deployer);
        Registry registry = new Registry("ETH");
        Compliance compliance = new Compliance(deployer);

        // Deploy OrderCancellation which depends on Signatures
        OrderCancellation cancellation = new OrderCancellation(deployer, address(signatures));

        // NOTE: We don't need to deploy AtomicSwap as a separate component anymore
        // as its functionality is integrated into the Exchange contract

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

        // Log deployment information
        console.log("\n==== POLYGON MAINNET DEPLOYMENT ====");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", chainId);
        console.log("");
        console.log("Exchange deployed at:", address(exchange));
        console.log("Fees Contract deployed at:", address(fees));
        console.log("Cancellation Contract deployed at:", address(cancellation));
        console.log("Compliance Contract deployed at:", address(compliance));
        console.log("Signatures Contract deployed at:", address(signatures));
        console.log("Registry Contract deployed at:", address(registry));

        console.log("\nAttributes-Based Compliance System Enabled");
        console.log("-------------------------------------");
        console.log("IMPORTANT: Security tokens must implement IToken with attributeRegistry() to work with this exchange.");
        console.log("Verify contracts on PolygonScan: https://polygonscan.com");

        console.log("\nTo verify contracts on Polygonscan:");
        console.log("npx hardhat verify --network polygon", address(exchange));
        console.log("npx hardhat verify --network polygon", address(fees), deployer);
        console.log("npx hardhat verify --network polygon", address(registry), "\"ETH\"");
        console.log("npx hardhat verify --network polygon", address(compliance), deployer);
        console.log("npx hardhat verify --network polygon", address(cancellation), deployer, address(signatures));
        console.log("npx hardhat verify --network polygon", address(signatures), "\"Numena Exchange\"", "\"1.0.0\"");

        vm.stopBroadcast();
    }
}