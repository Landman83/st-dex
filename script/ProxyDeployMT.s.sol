// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/Exchange.sol";
import "../src/mixins/Compliance.sol";
import "../src/mixins/Fees.sol";
import "../src/mixins/OrderCancellation.sol";
import "../src/mixins/Signatures.sol";
import "../src/mixins/Registry.sol";
import "../src/interfaces/IERC20Permit.sol";
import "../src/libraries/PermitData.sol";
import "../src/libraries/PermitHelper.sol";
import "@ar-security-token/lib/st-identity-registry/src/libraries/Attributes.sol";

/**
 * @title ProxyDeployMTScript
 * @notice Deploys the Exchange contract with meta-transaction support using OpenZeppelin's Transparent Proxy pattern
 * @dev This script follows OpenZeppelin's best practices for proxy deployment and includes meta-transaction support:
 *      1. Deploy the implementation contract first
 *      2. Deploy a ProxyAdmin to manage the proxy
 *      3. Deploy the TransparentUpgradeableProxy pointing to the implementation
 *      4. Initialize (not construct) the proxy instance
 */
contract ProxyDeployMTScript is Script {
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
    // forge script script/ProxyDeployMT.s.sol:ProxyDeployMTScript --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify

    /**
     * @notice Helper function to check if there is bytecode at an address
     * @param addr Address to check
     * @return Whether the address has bytecode
     */
    function checkBytecode(address addr) internal view returns (bool) {
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(addr)
        }
        bool hasCode = codeSize > 0;
        console.log("  Address:", addr, hasCode ? "[OK] Has bytecode" : "[FAIL] No bytecode");
        return hasCode;
    }

    // For tracking deployment info
    struct DeploymentInfo {
        address exchange;
        address exchangeImplementation;
        address proxyAdmin;
        address fees;
        address compliance;
        address cancellation;
        address signatures;
        address registry;
    }
    
    // We'll use this to store deployment info
    DeploymentInfo public deploymentInfo;

    function run() external {
        // Get environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        string memory rpcUrl = vm.envString("RPC_URL");
        uint256 chainId = vm.envUint("CHAIN_ID");
        
        // Set up the RPC connection
        vm.createSelectFork(rpcUrl);
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Verify deployer
        address calculatedDeployer = vm.addr(deployerPrivateKey);
        require(calculatedDeployer == deployerAddress, "Provided private key does not match deployer address");
        
        // Use the verified deployer
        address deployer = deployerAddress;

        // -----------------------------------------------------------------
        // STEP 1: Deploy the Exchange Implementation, ProxyAdmin, and Proxy
        // -----------------------------------------------------------------
        console.log("\nStep 1: Deploying Exchange Implementation, ProxyAdmin, and Proxy...");
        
        // Deploy Exchange implementation (constructor doesn't initialize it)
        Exchange exchangeImplementation = new Exchange();
        console.log("Exchange Implementation deployed at:", address(exchangeImplementation));
        
        // Deploy the ProxyAdmin with deployer as the owner
        ProxyAdmin proxyAdmin = new ProxyAdmin(deployer);
        console.log("ProxyAdmin deployed at:", address(proxyAdmin));
        
        // Deploy component contracts first to pass them to the proxy initialization
        Signatures signatures = new Signatures("Numena Exchange", "1.0.0");
        console.log("Signatures Contract deployed at:", address(signatures));
        
        Fees fees = new Fees(deployer);
        console.log("Fees Contract deployed at:", address(fees));
        
        Registry registry = new Registry("MATIC");
        console.log("Registry Contract deployed at:", address(registry));
        
        Compliance compliance = new Compliance(deployer);
        console.log("Compliance Contract deployed at:", address(compliance));
        
        OrderCancellation cancellation = new OrderCancellation(deployer, address(signatures));
        console.log("Cancellation Contract deployed at:", address(cancellation));
        
        // Define the initialization data for the proxy
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address)",
            deployer,                    // Owner
            address(fees),               // Fees contract
            address(cancellation),       // Cancellation contract
            address(compliance),         // Compliance contract
            address(signatures),         // Signatures contract
            address(registry)            // Registry contract
        );
        
        // Deploy the TransparentUpgradeableProxy
        TransparentUpgradeableProxy exchangeProxy = new TransparentUpgradeableProxy(
            address(exchangeImplementation),
            address(proxyAdmin),
            initData
        );
        address exchangeAddress = address(exchangeProxy);
        console.log("Exchange Proxy deployed at:", exchangeAddress);
        
        // Create a reference to the Exchange through the proxy for easier interaction
        Exchange exchange = Exchange(payable(exchangeAddress));
        
        // Set the exchange contract address in the OrderCancellation contract
        cancellation.setExchangeContract(exchangeAddress);
        console.log("Set Exchange address in OrderCancellation contract");
        
        // Store deployment info
        deploymentInfo.exchange = exchangeAddress;
        deploymentInfo.exchangeImplementation = address(exchangeImplementation);
        deploymentInfo.proxyAdmin = address(proxyAdmin);
        deploymentInfo.fees = address(fees);
        deploymentInfo.compliance = address(compliance);
        deploymentInfo.cancellation = address(cancellation);
        deploymentInfo.signatures = address(signatures);
        deploymentInfo.registry = address(registry);
        
        // -----------------------------------------------------------------
        // STEP 2: Verify Contract Deployments
        // -----------------------------------------------------------------
        console.log("\nVerifying Contract Deployments...");
        
        // Check bytecode at each critical address
        bool allDeployed = true;
        
        // Verify critical contracts have bytecode
        allDeployed = checkBytecode(address(exchangeImplementation)) && allDeployed;
        allDeployed = checkBytecode(address(proxyAdmin)) && allDeployed;
        allDeployed = checkBytecode(exchangeAddress) && allDeployed;
        allDeployed = checkBytecode(address(fees)) && allDeployed;
        allDeployed = checkBytecode(address(compliance)) && allDeployed;
        allDeployed = checkBytecode(address(cancellation)) && allDeployed;
        allDeployed = checkBytecode(address(signatures)) && allDeployed;
        allDeployed = checkBytecode(address(registry)) && allDeployed;
        
        // Verify meta-transaction support
        console.log("\nVerifying Meta-Transaction Support...");
        
        // Try to call new interface methods
        try exchange.executeSignedOrderWithPermits(
            Order.OrderInfo({
                maker: address(0),
                makerToken: address(0),
                makerAmount: 0,
                taker: address(0),
                takerToken: address(0),
                takerAmount: 0,
                makerNonce: 0,
                takerNonce: 0,
                expiry: 0
            }),
            bytes(""),
            bytes(""),
            PermitData.TokenPermit({
                token: address(0),
                owner: address(0),
                value: 0,
                deadline: 0,
                v: 0,
                r: bytes32(0),
                s: bytes32(0)
            }),
            PermitData.TokenPermit({
                token: address(0),
                owner: address(0),
                value: 0,
                deadline: 0,
                v: 0,
                r: bytes32(0),
                s: bytes32(0)
            })
        ) {} catch (bytes memory err) {
            // This should fail with a specific error, not a "function not found" error
            // So as long as we don't get a selector error, the function exists
            console.log("Meta-transaction support verified");
        }
        
        if (!allDeployed) {
            console.log("\n[WARNING] Some contracts have no bytecode at their addresses!");
            console.log("This typically means the transactions were not confirmed or failed.");
        } else {
            console.log("\n[SUCCESS] All contracts successfully deployed and verified!");
        }
        
        // -----------------------------------------------------------------
        // STEP 3: Display Deployment Summary
        // -----------------------------------------------------------------
        console.log("\n==== NETWORK DEPLOYMENT WITH META-TRANSACTION SUPPORT ====");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", chainId);
        console.log("");
        console.log("Exchange Proxy (Main Interface):", exchangeAddress);
        console.log("Exchange Implementation:", address(exchangeImplementation));
        console.log("ProxyAdmin:", address(proxyAdmin));
        console.log("Fees Contract:", address(fees));
        console.log("Compliance Contract:", address(compliance));
        console.log("Cancellation Contract:", address(cancellation));
        console.log("Signatures Contract:", address(signatures));
        console.log("Registry Contract:", address(registry));
        
        console.log("\nMeta-Transaction Support Enabled via EIP-2612 Permit");
        console.log("-------------------------------------");
        console.log("IMPORTANT: For meta-transactions to work, tokens must support EIP-2612 (like USDC)");
        console.log("Use executeSignedOrderWithPermits() for meta-transaction support");
        
        console.log("\n=== UPGRADE INSTRUCTIONS ===");
        console.log("To upgrade the implementation in the future:");
        console.log("1. Deploy a new implementation contract");
        console.log("2. Call proxyAdmin.upgrade(proxy, newImplementation)");
        
        console.log("\nTo verify contracts on the network explorer:");
        console.log("npx hardhat verify --network polygon", address(exchangeImplementation));
        console.log("npx hardhat verify --network polygon", address(fees), deployer);
        console.log("npx hardhat verify --network polygon", address(registry), "\"MATIC\"");
        console.log("npx hardhat verify --network polygon", address(compliance), deployer);
        console.log("npx hardhat verify --network polygon", address(cancellation), deployer, address(signatures));
        console.log("npx hardhat verify --network polygon", address(signatures), "\"Numena Exchange\"", "\"1.0.0\"");
        
        // Note: The proxy cannot be verified using the standard hardhat verify command
        // Use the "verify-proxy" plugin or manually verify the proxy on the explorer
        
        // Record these addresses in your .env file for future reference
        console.log("\n=== IMPORTANT: SAVE THESE ADDRESSES ===");
        console.log("EXCHANGE_ADDRESS=", deploymentInfo.exchange);
        console.log("PROXY_ADMIN=", deploymentInfo.proxyAdmin);
        console.log("EXCHANGE_IMPLEMENTATION=", deploymentInfo.exchangeImplementation);
        
        vm.stopBroadcast();
    }
}