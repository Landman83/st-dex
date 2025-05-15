// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

interface ICompliance {
    function isKYCVerified(address _address) external view returns (bool);
}

contract CheckKYC is Script {
    function run() public {
        // Load private key from environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address buyerAddress = vm.envAddress("BUYER_ADDRESS");
        address complianceAddress = vm.envAddress("COMPLIANCE_ADDRESS");
        
        // Start broadcast
        vm.startBroadcast(deployerPrivateKey);
        
        // Get compliance contract
        ICompliance compliance = ICompliance(complianceAddress);
        
        // Check KYC status
        bool isVerified = compliance.isKYCVerified(buyerAddress);
        
        // Log results
        console.log("Checking KYC status for address:");
        console.log(buyerAddress);
        console.log("KYC Status in Compliance Contract:", isVerified);

        vm.stopBroadcast();
    }
}