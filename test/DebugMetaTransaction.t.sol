// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Exchange.sol";
import "../src/interfaces/IERC20Permit.sol";
import "../src/libraries/Order.sol";
import "../src/libraries/PermitData.sol";

interface IComplianceChecker {
    function hasAttribute(address token, address user, bytes32 attribute) external view returns (bool);
    function isSecurityToken(address token) external view returns (bool);
}

interface IIdentityRegistry {
    function hasAttribute(address user, bytes32 attribute) external view returns (bool);
    function isVerified(address user) external view returns (bool);
}

interface IRegistry {
    function isRegisteredAsset(address asset) external view returns (bool);
}

interface IERC20Metadata {
    function decimals() external view returns (uint8);
}

contract DebugMetaTransaction is Test {
    // Contract addresses (loaded from .env)
    address payable exchangeAddress;
    address securityTokenAddress;
    address cashTokenAddress;
    address complianceAddress;
    address identityRegistryAddress;
    
    // User addresses
    address sellerAddress;
    address buyerAddress;
    
    // Interfaces
    Exchange exchange;
    IERC20 securityToken;
    IERC20 cashToken;
    IComplianceChecker compliance;
    IIdentityRegistry identityRegistry;
    IRegistry registry;
    
    // Test data
    bytes32 constant KYC_VERIFIED = keccak256("KYC_VERIFIED");
    
    function setUp() public {
        // Load environment variables
        exchangeAddress = payable(vm.envAddress("EXCHANGE_ADDRESS"));
        securityTokenAddress = vm.envAddress("SECURITY_TOKEN_ADDRESS");
        cashTokenAddress = vm.envAddress("CASH_TOKEN_ADDRESS");
        complianceAddress = vm.envAddress("COMPLIANCE_ADDRESS");
        identityRegistryAddress = vm.envAddress("IDENTITY_REGISTRY_ADDRESS");
        sellerAddress = vm.envAddress("SELLER_ADDRESS");
        buyerAddress = vm.envAddress("BUYER_ADDRESS");
        
        // Connect to contracts
        exchange = Exchange(payable(exchangeAddress));
        securityToken = IERC20(securityTokenAddress);
        cashToken = IERC20(cashTokenAddress);
        compliance = IComplianceChecker(complianceAddress);
        identityRegistry = IIdentityRegistry(identityRegistryAddress);
        
        // Get registry from environment variable
        address registryAddress = vm.envAddress("REGISTRY_ADDRESS");
        registry = IRegistry(registryAddress);
        
        // Log setup information
        console.log("=== Meta-Transaction Debug Test Setup ===");
        console.log("Exchange:", exchangeAddress);
        console.log("Security Token:", securityTokenAddress);
        console.log("Cash Token:", cashTokenAddress);
        console.log("Compliance:", complianceAddress);
        console.log("Identity Registry:", identityRegistryAddress);
        console.log("Seller:", sellerAddress);
        console.log("Buyer:", buyerAddress);
        console.log("Registry (from env):", registryAddress);
    }
    
    function testMetaTransactionDebug() public {
        console.log("\n=== Starting Meta-Transaction Debug Test ===");
        
        // Check token balances
        console.log("\n--- Token Balances ---");
        uint256 sellerSecurityBalance = securityToken.balanceOf(sellerAddress);
        uint256 buyerCashBalance = cashToken.balanceOf(buyerAddress);
        uint256 securityDecimals = IERC20Metadata(securityTokenAddress).decimals();
        uint256 cashDecimals = IERC20Metadata(cashTokenAddress).decimals();
        
        console.log("Seller security token balance:", sellerSecurityBalance / (10**securityDecimals));
        console.log("Buyer cash token balance:", buyerCashBalance / (10**cashDecimals));
        
        // Check token registration
        console.log("\n--- Token Registration Status ---");
        bool securityRegistered = registry.isRegisteredAsset(securityTokenAddress);
        bool cashRegistered = registry.isRegisteredAsset(cashTokenAddress);
        
        console.log("Security token registered:", securityRegistered);
        console.log("Cash token registered:", cashRegistered);
        
        // Check compliance settings
        console.log("\n--- Compliance Status ---");
        bool isSecurityTokenType = compliance.isSecurityToken(securityTokenAddress);
        bool isCashTokenType = compliance.isSecurityToken(cashTokenAddress);
        
        console.log("Security token is security token type:", isSecurityTokenType);
        console.log("Cash token is security token type:", isCashTokenType);
        
        // Check KYC via Compliance
        bool sellerSecurityKYC = false;
        bool buyerSecurityKYC = false;
        bool sellerCashKYC = false;
        bool buyerCashKYC = false;
        
        try compliance.hasAttribute(securityTokenAddress, sellerAddress, KYC_VERIFIED) returns (bool result) {
            sellerSecurityKYC = result;
            console.log("Seller KYC for security token (via compliance):", result);
        } catch {
            console.log("Error checking seller KYC for security token");
        }
        
        try compliance.hasAttribute(securityTokenAddress, buyerAddress, KYC_VERIFIED) returns (bool result) {
            buyerSecurityKYC = result;
            console.log("Buyer KYC for security token (via compliance):", result);
        } catch {
            console.log("Error checking buyer KYC for security token");
        }
        
        try compliance.hasAttribute(cashTokenAddress, sellerAddress, KYC_VERIFIED) returns (bool result) {
            sellerCashKYC = result;
            console.log("Seller KYC for cash token (via compliance):", result);
        } catch {
            console.log("Error checking seller KYC for cash token");
        }
        
        try compliance.hasAttribute(cashTokenAddress, buyerAddress, KYC_VERIFIED) returns (bool result) {
            buyerCashKYC = result;
            console.log("Buyer KYC for cash token (via compliance):", result);
        } catch {
            console.log("Error checking buyer KYC for cash token");
        }
        
        // Check KYC via Identity Registry
        console.log("\n--- Identity Registry Status ---");
        bool sellerIdentityKYC = false;
        bool buyerIdentityKYC = false;
        
        try identityRegistry.hasAttribute(sellerAddress, KYC_VERIFIED) returns (bool result) {
            sellerIdentityKYC = result;
            console.log("Seller KYC (via identity registry):", result);
        } catch {
            console.log("Error checking seller KYC via identity registry");
        }
        
        try identityRegistry.hasAttribute(buyerAddress, KYC_VERIFIED) returns (bool result) {
            buyerIdentityKYC = result;
            console.log("Buyer KYC (via identity registry):", result);
        } catch {
            console.log("Error checking buyer KYC via identity registry");
        }
        
        try identityRegistry.isVerified(sellerAddress) returns (bool result) {
            console.log("Seller is verified (via identity registry):", result);
        } catch {
            console.log("Error checking if seller is verified");
        }
        
        try identityRegistry.isVerified(buyerAddress) returns (bool result) {
            console.log("Buyer is verified (via identity registry):", result);
        } catch {
            console.log("Error checking if buyer is verified");
        }
        
        // Check Exchange KYC helpers
        console.log("\n--- Exchange KYC Helper Functions ---");
        bool sellerExchangeKYC = false;
        bool buyerExchangeKYC = false;
        
        try exchange.isKYCVerified(securityTokenAddress, sellerAddress) returns (bool result) {
            sellerExchangeKYC = result;
            console.log("Seller KYC for security token (via exchange):", result);
        } catch {
            console.log("Error checking seller KYC via exchange");
        }
        
        try exchange.isKYCVerified(securityTokenAddress, buyerAddress) returns (bool result) {
            buyerExchangeKYC = result;
            console.log("Buyer KYC for security token (via exchange):", result);
        } catch {
            console.log("Error checking buyer KYC via exchange");
        }
        
        // Test token transfers directly
        console.log("\n--- Direct Token Transfer Tests ---");
        
        // Test security token transfer (seller to buyer)
        vm.startPrank(sellerAddress);
        try securityToken.transfer(buyerAddress, 1) {
            console.log("Direct security token transfer succeeded");
        } catch Error(string memory reason) {
            console.log("Direct security token transfer failed with reason:", reason);
        } catch {
            console.log("Direct security token transfer failed with no reason");
        }
        vm.stopPrank();
        
        // Test cash token transfer (buyer to seller)
        vm.startPrank(buyerAddress);
        try cashToken.transfer(sellerAddress, 1) {
            console.log("Direct cash token transfer succeeded");
        } catch Error(string memory reason) {
            console.log("Direct cash token transfer failed with reason:", reason);
        } catch {
            console.log("Direct cash token transfer failed with no reason");
        }
        vm.stopPrank();
        
        // Test meta-transaction execution (simulation)
        console.log("\n--- Meta-Transaction Simulation ---");
        
        // Create order with test values
        Order.OrderInfo memory order = Order.OrderInfo({
            maker: sellerAddress,
            makerToken: securityTokenAddress,
            makerAmount: 100 * 10**securityDecimals,
            taker: buyerAddress,
            takerToken: cashTokenAddress,
            takerAmount: 1000 * 10**cashDecimals,
            makerNonce: 0,
            takerNonce: 0,
            expiry: block.timestamp + 30 days
        });
        
        // Create test signatures (will fail, just for debugging)
        bytes memory makerSig = new bytes(65);
        bytes memory takerSig = new bytes(65);
        
        // Create test permits (will fail, just for debugging)
        PermitData.TokenPermit memory makerPermit = PermitData.TokenPermit({
            token: securityTokenAddress,
            owner: sellerAddress,
            value: order.makerAmount,
            deadline: block.timestamp + 60 days,
            v: 0,
            r: bytes32(0),
            s: bytes32(0)
        });
        
        PermitData.TokenPermit memory takerPermit = PermitData.TokenPermit({
            token: cashTokenAddress,
            owner: buyerAddress,
            value: order.takerAmount,
            deadline: block.timestamp + 60 days,
            v: 0,
            r: bytes32(0),
            s: bytes32(0)
        });
        
        // Simulate the meta-transaction
        bytes memory callData = abi.encodeWithSelector(
            exchange.executeSignedOrderWithPermits.selector,
            order,
            makerSig,
            takerSig,
            makerPermit,
            takerPermit
        );
        
        (bool success, bytes memory returnData) = payable(address(exchange)).call(callData);
        
        if (success) {
            console.log("Meta-transaction simulation succeeded (unexpected with test data)");
        } else {
            console.log("Meta-transaction simulation failed (expected)");
            // We can't reliably extract error messages in Solidity, but this is expected
            // since we're using bogus signatures
        }
        
        // Print summary
        console.log("\n=== Test Summary ===");
        console.log("Token registration: Security", securityRegistered, "/ Cash", cashRegistered);
        
        console.log("Security token is security type:", isSecurityTokenType);
        console.log("Cash token is security type:", isCashTokenType);
        
        console.log("Seller KYC: Compliance", sellerSecurityKYC, "/ Identity Registry", sellerIdentityKYC);
        console.log("Buyer KYC: Compliance", buyerSecurityKYC, "/ Identity Registry", buyerIdentityKYC);
        
        // Identify likely issues
        console.log("\n=== Potential Issues ===");
        if (!securityRegistered) console.log("- Security token is not registered in Exchange");
        if (!cashRegistered) console.log("- Cash token is not registered in Exchange");
        
        if (!sellerSecurityKYC && isSecurityTokenType) console.log("- Seller lacks KYC for security token");
        if (!buyerSecurityKYC && isSecurityTokenType) console.log("- Buyer lacks KYC for security token");
        if (!sellerCashKYC && isCashTokenType) console.log("- Seller lacks KYC for cash token");
        if (!buyerCashKYC && isCashTokenType) console.log("- Buyer lacks KYC for cash token");
        
        // Note discrepancies
        if (sellerIdentityKYC != sellerSecurityKYC && isSecurityTokenType) {
            console.log("- Discrepancy: Seller has KYC in Identity Registry but not for security token");
        }
        if (buyerIdentityKYC != buyerSecurityKYC && isSecurityTokenType) {
            console.log("- Discrepancy: Buyer has KYC in Identity Registry but not for security token");
        }
    }
}