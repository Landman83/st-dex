// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

interface ICompliance {
    function isKYCVerified(address _address) external view returns (bool);
    // Some compliance modules might expose this
    function identityRegistry() external view returns (address);
}

interface IIdentityRegistry {
    function isVerified(address _address) external view returns (bool);
    function hasAttribute(address _address, bytes32 _attribute) external view returns (bool);
}

contract CheckKYCDetailed is Script {
    bytes32 constant KYC_ATTRIBUTE = keccak256("KYC_VERIFIED");
    
    function run() public {
        // Load variables from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address buyerAddress = vm.envAddress("BUYER_ADDRESS");
        address complianceAddress = vm.envAddress("COMPLIANCE_ADDRESS");
        
        // Start broadcast
        vm.startBroadcast(deployerPrivateKey);
        
        // Get compliance contract
        ICompliance compliance = ICompliance(complianceAddress);
        
        // Check KYC status via compliance
        bool isVerifiedCompliance = compliance.isKYCVerified(buyerAddress);
        
        console.log("==== KYC STATUS CHECK ====");
        console.log("Checking for address:", buyerAddress);
        console.log("Compliance Contract:", complianceAddress);
        console.log("KYC Verified via Compliance:", isVerifiedCompliance);
        
        // Attempt to check identity registry if exposed by compliance
        try compliance.identityRegistry() returns (address registryAddress) {
            if (registryAddress != address(0)) {
                IIdentityRegistry registry = IIdentityRegistry(registryAddress);
                
                console.log("\n==== IDENTITY REGISTRY CHECKS ====");
                console.log("Identity Registry found at:", registryAddress);
                
                try registry.isVerified(buyerAddress) returns (bool isVerified) {
                    console.log("isVerified() check:", isVerified);
                } catch {
                    console.log("isVerified() function not available");
                }
                
                try registry.hasAttribute(buyerAddress, KYC_ATTRIBUTE) returns (bool hasKYC) {
                    console.log("hasAttribute(KYC_VERIFIED) check:", hasKYC);
                } catch {
                    console.log("hasAttribute() function not available");
                }
            }
        } catch {
            console.log("\nNo Identity Registry found in Compliance contract");
        }
        
        // Try with optional identity registry address
        try vm.envAddress("IDENTITY_REGISTRY_ADDRESS") returns (address registryAddress) {
            if (registryAddress != address(0)) {
                IIdentityRegistry registry = IIdentityRegistry(registryAddress);
                
                console.log("\n==== EXTERNAL IDENTITY REGISTRY CHECK ====");
                console.log("External Registry at:", registryAddress);
                
                try registry.isVerified(buyerAddress) returns (bool isVerified) {
                    console.log("isVerified() check:", isVerified);
                } catch {
                    console.log("isVerified() function not available");
                }
                
                try registry.hasAttribute(buyerAddress, KYC_ATTRIBUTE) returns (bool hasKYC) {
                    console.log("hasAttribute(KYC_VERIFIED) check:", hasKYC);
                } catch {
                    console.log("hasAttribute() function not available");
                }
            }
        } catch {
            console.log("\nNo IDENTITY_REGISTRY_ADDRESS specified in environment");
        }

        vm.stopBroadcast();
    }
}