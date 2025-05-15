// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../src/mixins/Registry.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title RegisterTokensScript
 * @notice Registers tokens in the existing Registry contract
 * @dev This script is designed to register tokens after the exchange has been deployed
 */
contract RegisterTokensScript is Script {
    // Environment variables:
    // - DEPLOYER_ADDRESS: The address that will deploy the contracts
    // - PRIVATE_KEY: The private key for signing transactions
    // - RPC_URL: The RPC URL for the Polygon Mainnet
    // - REGISTRY_ADDRESS: The address of the registry contract
    // - SECURITY_TOKEN_ADDRESS: Address of the security token (STKN) to register
    // - CASH_TOKEN_ADDRESS: Address of the cash token (tUSD) to register
    //
    // Create a .env file with these variables before running:
    // ```
    // DEPLOYER_ADDRESS=0xYourDeployerAddress
    // PRIVATE_KEY=0xYourPrivateKey
    // RPC_URL=https://polygon-rpc.com
    // REGISTRY_ADDRESS=0xdC6653689D8750596dF388862e8A5be317FEaBbA
    // SECURITY_TOKEN_ADDRESS=0x6f0b2dc87027407F17057602E4819274D8c20325
    // CASH_TOKEN_ADDRESS=0xb633A20A12cc65ECafB048F5a36573Cc27c77353
    // ```
    //
    // Run script with:
    // forge script script/RegisterTokens.s.sol:RegisterTokensScript --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast

    function run() external {
        // Get environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        string memory rpcUrl = vm.envString("RPC_URL");
        address registryAddress = vm.envAddress("REGISTRY_ADDRESS");
        
        // Get token addresses to register
        address securityTokenAddress = vm.envAddress("SECURITY_TOKEN_ADDRESS");
        address cashTokenAddress = vm.envAddress("CASH_TOKEN_ADDRESS");
        
        // Set up the RPC connection
        vm.createSelectFork(rpcUrl);
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Verify deployer
        address calculatedDeployer = vm.addr(deployerPrivateKey);
        require(calculatedDeployer == deployerAddress, "Provided private key does not match deployer address");
        
        // Connect to the registry contract
        Registry registry = Registry(registryAddress);
        
        console.log("\n==== TOKEN REGISTRATION SCRIPT ====");
        console.log("Registry Contract:", registryAddress);
        console.log("Security Token:", securityTokenAddress);
        console.log("Cash Token:", cashTokenAddress);
        
        // -----------------------------------------------------------------
        // Register tokens in the Registry
        // -----------------------------------------------------------------
        console.log("\nRegistering Tokens in the Registry...");
        
        // Register Security Token (STKN)
        try ERC20(securityTokenAddress).symbol() returns (string memory symbol) {
            try ERC20(securityTokenAddress).decimals() returns (uint8 decimals) {
                console.log(string(abi.encodePacked("Registering Security Token: ", symbol, " (", addressToString(securityTokenAddress), ")")));
                
                // Check if already registered
                bool alreadyRegistered = false;
                try registry.isRegisteredAsset(securityTokenAddress) returns (bool registered) {
                    alreadyRegistered = registered;
                } catch {}
                
                if (!alreadyRegistered) {
                    // Register the token (isSecurityToken set to false to avoid issues with AttributeRegistry checks)
                    registry.registerToken(securityTokenAddress, symbol, decimals, false);
                    
                    // Confirm the token registration
                    registry.confirmTokenRegistration(securityTokenAddress, symbol, decimals, false);
                    
                    console.log(string(abi.encodePacked("Security Token ", symbol, " registered successfully")));
                } else {
                    console.log(string(abi.encodePacked("Security Token ", symbol, " already registered")));
                }
            } catch {
                console.log("Failed to get decimals for security token");
            }
        } catch {
            console.log("Failed to get symbol for security token");
        }
        
        // Register Cash Token (tUSD)
        try ERC20(cashTokenAddress).symbol() returns (string memory symbol) {
            try ERC20(cashTokenAddress).decimals() returns (uint8 decimals) {
                console.log(string(abi.encodePacked("Registering Cash Token: ", symbol, " (", addressToString(cashTokenAddress), ")")));
                
                // Check if already registered
                bool alreadyRegistered = false;
                try registry.isRegisteredAsset(cashTokenAddress) returns (bool registered) {
                    alreadyRegistered = registered;
                } catch {}
                
                if (!alreadyRegistered) {
                    // Register the token (isSecurityToken set to false for normal ERC20 tokens)
                    registry.registerToken(cashTokenAddress, symbol, decimals, false);
                    
                    // Confirm the token registration
                    registry.confirmTokenRegistration(cashTokenAddress, symbol, decimals, false);
                    
                    console.log(string(abi.encodePacked("Cash Token ", symbol, " registered successfully")));
                } else {
                    console.log(string(abi.encodePacked("Cash Token ", symbol, " already registered")));
                }
            } catch {
                console.log("Failed to get decimals for cash token");
            }
        } catch {
            console.log("Failed to get symbol for cash token");
        }
        
        // Verify token registration by checking the registry
        bool isStkRegistered = registry.isRegisteredAsset(securityTokenAddress);
        bool isTusdRegistered = registry.isRegisteredAsset(cashTokenAddress);
        
        console.log("\nVerification Result:");
        console.log("Security Token (STKN) registered:", isStkRegistered ? "YES" : "NO");
        console.log("Cash Token (tUSD) registered:", isTusdRegistered ? "YES" : "NO");
        
        // -----------------------------------------------------------------
        // Display Summary
        // -----------------------------------------------------------------
        console.log("\n==== REGISTRATION SUMMARY ====");
        console.log("Registry Contract:", registryAddress);
        console.log("Registered Tokens:");
        console.log("- Security Token (STKN):", securityTokenAddress, isStkRegistered ? "REGISTERED" : "FAILED");
        console.log("- Cash Token (tUSD):", cashTokenAddress, isTusdRegistered ? "REGISTERED" : "FAILED");
        
        vm.stopBroadcast();
    }
    
    /**
     * @dev Helper function to convert an address to a string
     * @param addr The address to convert
     * @return The address as a string
     */
    function addressToString(address addr) internal pure returns (string memory) {
        bytes memory addressBytes = abi.encodePacked(addr);
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(42); // "0x" + 40 hex characters
        
        result[0] = "0";
        result[1] = "x";
        
        for (uint256 i = 0; i < 20; i++) {
            uint8 val = uint8(addressBytes[i]);
            result[2 + i * 2] = hexChars[uint256(val >> 4)];
            result[3 + i * 2] = hexChars[uint256(val & 0x0f)];
        }
        
        return string(result);
    }
}