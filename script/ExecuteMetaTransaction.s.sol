// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/Exchange.sol";
import "../src/interfaces/IERC20Permit.sol";
import "../src/libraries/Order.sol";
import "../src/libraries/PermitData.sol";

/**
 * @title ExecuteMetaTransaction
 * @notice Foundry script to generate, sign, and execute a meta-transaction trade
 * @dev This is a Solidity alternative to execute_mt.js
 */
contract ExecuteMetaTransaction is Script {
    // Order EIP-712 typehash (must match Exchange contract)
    bytes32 constant ORDER_TYPEHASH = keccak256(
        "OrderInfo(address maker,address makerToken,uint256 makerAmount,address taker,address takerToken,uint256 takerAmount,uint256 makerNonce,uint256 takerNonce,uint256 expiry)"
    );
    
    // Permit EIP-712 typehash (must match ERC20Permit implementation)
    bytes32 constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );
    
    // Exchange domain info
    string constant EXCHANGE_NAME = "Numena Exchange";
    string constant EXCHANGE_VERSION = "1.0.0";
    
    // Token info
    uint8 constant SECURITY_TOKEN_DECIMALS = 18;
    uint8 constant CASH_TOKEN_DECIMALS = 18;
    string constant SECURITY_TOKEN_NAME = "Security Token";
    string constant CASH_TOKEN_NAME = "Cash Token";
    
    // Contract addresses
    address exchangeAddress;
    address securityTokenAddress;
    address cashTokenAddress;
    
    // Wallets
    address sellerAddress;
    address buyerAddress;
    uint256 sellerPrivateKey;
    uint256 buyerPrivateKey;
    
    // Test amounts
    uint256 makerAmount = 100 * 10**18; // 100 tokens
    uint256 takerAmount = 1000 * 10**18; // 1000 tokens
    
    // Interfaces
    Exchange exchange;
    IERC20 securityToken;
    IERC20 cashToken;
    
    function setUp() public {
        // Load addresses from environment variables
        exchangeAddress = vm.envAddress("EXCHANGE_ADDRESS");
        securityTokenAddress = vm.envAddress("SECURITY_TOKEN_ADDRESS");
        cashTokenAddress = vm.envAddress("CASH_TOKEN_ADDRESS");
        
        // Load private keys from environment variables
        sellerPrivateKey = vm.envUint("PRIVATE_KEY"); // Seller's private key
        buyerPrivateKey = vm.envUint("BUYER_PRIVATE_KEY"); // Buyer's private key
        
        // Derive addresses from private keys
        sellerAddress = vm.addr(sellerPrivateKey);
        buyerAddress = vm.addr(buyerPrivateKey);
        
        // Connect to contracts
        exchange = Exchange(payable(exchangeAddress));
        securityToken = IERC20(securityTokenAddress);
        cashToken = IERC20(cashTokenAddress);
        
        // Log setup information
        console.log("=== Meta-Transaction Execution Setup ===");
        console.log("Exchange:", exchangeAddress);
        console.log("Security Token:", securityTokenAddress);
        console.log("Cash Token:", cashTokenAddress);
        console.log("Seller (Maker):", sellerAddress);
        console.log("Buyer (Taker):", buyerAddress);
    }
    
    function run() public {
        setUp();
        
        // Check balances first
        checkBalances();
        
        // Create and sign the order
        (Order.OrderInfo memory order, bytes memory makerSig, bytes memory takerSig) = createAndSignOrder();
        
        // Create and sign permits
        (PermitData.TokenPermit memory makerPermit, PermitData.TokenPermit memory takerPermit) = createAndSignPermits(order);
        
        // Execute the meta-transaction
        executeMetaTransaction(order, makerSig, takerSig, makerPermit, takerPermit);
    }
    
    /**
     * @notice Check token balances of maker and taker
     */
    function checkBalances() internal view {
        uint256 makerBalance = securityToken.balanceOf(sellerAddress);
        uint256 takerBalance = cashToken.balanceOf(buyerAddress);
        
        console.log("\n=== Token Balances ===");
        console.log("Maker security token balance:", makerBalance / 10**SECURITY_TOKEN_DECIMALS);
        console.log("Taker cash token balance:", takerBalance / 10**CASH_TOKEN_DECIMALS);
        
        // Check if balances are sufficient
        if (makerBalance < makerAmount) {
            console.log("WARNING: Maker has insufficient balance!");
        } else {
            console.log("Maker has sufficient balance (OK)");
        }
        
        if (takerBalance < takerAmount) {
            console.log("WARNING: Taker has insufficient balance!");
        } else {
            console.log("Taker has sufficient balance (OK)");
        }
        
        // Check allowances
        uint256 makerAllowance = securityToken.allowance(sellerAddress, exchangeAddress);
        uint256 takerAllowance = cashToken.allowance(buyerAddress, exchangeAddress);
        
        console.log("\n=== Token Allowances ===");
        console.log("Maker allowance:", makerAllowance / 10**SECURITY_TOKEN_DECIMALS);
        console.log("Taker allowance:", takerAllowance / 10**CASH_TOKEN_DECIMALS);
        
        if (makerAllowance < makerAmount) {
            console.log("NOTE: Maker allowance is insufficient but will use permit");
        }
        
        if (takerAllowance < takerAmount) {
            console.log("NOTE: Taker allowance is insufficient but will use permit");
        }
    }
    
    /**
     * @notice Create and sign an order using EIP-712
     * @dev Uses vm.sign to create signatures for both maker and taker
     */
    function createAndSignOrder() internal returns (
        Order.OrderInfo memory order,
        bytes memory makerSignature,
        bytes memory takerSignature
    ) {
        console.log("\n=== Creating Order ===");
        
        // Set expiry to 30 days from now
        uint256 expiry = block.timestamp + 30 days;
        console.log("Order expiry:", expiry);
        
        // Create the order
        order = Order.OrderInfo({
            maker: sellerAddress,
            makerToken: securityTokenAddress,
            makerAmount: makerAmount,
            taker: buyerAddress,
            takerToken: cashTokenAddress,
            takerAmount: takerAmount,
            makerNonce: 0,
            takerNonce: 0,
            expiry: expiry
        });
        
        // Log order details
        console.log("Maker:", order.maker);
        console.log("Maker token:", order.makerToken);
        console.log("Maker amount:", order.makerAmount / 10**SECURITY_TOKEN_DECIMALS);
        console.log("Taker:", order.taker);
        console.log("Taker token:", order.takerToken);
        console.log("Taker amount:", order.takerAmount / 10**CASH_TOKEN_DECIMALS);
        
        // Get the exchange domain separator through Signatures contract
        bytes32 domainSeparator;
        try exchange.getSignaturesContract() returns (address signaturesContract) {
            if (signaturesContract != address(0)) {
                try ISignaturesMixin(signaturesContract).getDomainSeparator() returns (bytes32 ds) {
                    domainSeparator = ds;
                    console.log("Got domain separator from Signatures contract");
                } catch {
                    // Fall back to manual calculation
                    domainSeparator = calculateDomainSeparator();
                    console.log("Calculated domain separator manually (1)");
                }
            } else {
                // Fall back to manual calculation
                domainSeparator = calculateDomainSeparator();
                console.log("Calculated domain separator manually (2)");
            }
        } catch {
            // If the exchange doesn't have this function, build the domain separator manually
            domainSeparator = calculateDomainSeparator();
            console.log("Calculated domain separator manually (3)");
        }
        
        // Hash the order
        bytes32 orderHash = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator,
            keccak256(abi.encode(
                ORDER_TYPEHASH,
                order.maker,
                order.makerToken,
                order.makerAmount,
                order.taker,
                order.takerToken,
                order.takerAmount,
                order.makerNonce,
                order.takerNonce,
                order.expiry
            ))
        ));
        
        console.log("\n=== Signing Order ===");
        console.log("Order hash:", vm.toString(orderHash));
        
        // Sign the order with maker's private key
        (uint8 makerV, bytes32 makerR, bytes32 makerS) = vm.sign(sellerPrivateKey, orderHash);
        makerSignature = abi.encodePacked(makerR, makerS, makerV);
        
        // Sign the order with taker's private key
        (uint8 takerV, bytes32 takerR, bytes32 takerS) = vm.sign(buyerPrivateKey, orderHash);
        takerSignature = abi.encodePacked(takerR, takerS, takerV);
        
        console.log("Order signed by maker and taker (OK)");
        
        return (order, makerSignature, takerSignature);
    }
    
    /**
     * @notice Create and sign permits for ERC20 tokens using EIP-712
     * @dev Uses vm.sign to create permit signatures for both tokens
     */
    function createAndSignPermits(Order.OrderInfo memory order) internal returns (
        PermitData.TokenPermit memory makerPermit,
        PermitData.TokenPermit memory takerPermit
    ) {
        console.log("\n=== Creating Permits ===");
        
        // Set permit deadline to 60 days from now (longer than order expiry)
        uint256 permitDeadline = block.timestamp + 60 days;
        console.log("Permit deadline:", permitDeadline);
        
        // Try to get nonces from tokens
        uint256 makerNonce = 0;
        uint256 takerNonce = 0;
        
        // For maker token
        try IERC20Permit(securityTokenAddress).nonces(sellerAddress) returns (uint256 nonce) {
            makerNonce = nonce;
            console.log("Maker token nonce:", makerNonce);
        } catch {
            console.log("Could not get maker token nonce, using 0");
        }
        
        // For taker token
        try IERC20Permit(cashTokenAddress).nonces(buyerAddress) returns (uint256 nonce) {
            takerNonce = nonce;
            console.log("Taker token nonce:", takerNonce);
        } catch {
            console.log("Could not get taker token nonce, using 0");
        }
        
        // Create security token (maker) permit domain separator
        bytes32 makerTokenDomainSeparator;
        try IERC20Permit(securityTokenAddress).DOMAIN_SEPARATOR() returns (bytes32 ds) {
            makerTokenDomainSeparator = ds;
            console.log("Got maker token domain separator from token");
        } catch {
            // Build domain separator manually
            makerTokenDomainSeparator = calculateTokenDomainSeparator(SECURITY_TOKEN_NAME, securityTokenAddress);
            console.log("Calculated maker token domain separator manually");
        }
        
        // Create cash token (taker) permit domain separator
        bytes32 takerTokenDomainSeparator;
        try IERC20Permit(cashTokenAddress).DOMAIN_SEPARATOR() returns (bytes32 ds) {
            takerTokenDomainSeparator = ds;
            console.log("Got taker token domain separator from token");
        } catch {
            // Build domain separator manually
            takerTokenDomainSeparator = calculateTokenDomainSeparator(CASH_TOKEN_NAME, cashTokenAddress);
            console.log("Calculated taker token domain separator manually");
        }
        
        // Create security token permit hash
        bytes32 makerPermitHash = keccak256(abi.encodePacked(
            "\x19\x01",
            makerTokenDomainSeparator,
            keccak256(abi.encode(
                PERMIT_TYPEHASH,
                sellerAddress,
                exchangeAddress,
                order.makerAmount,
                makerNonce,
                permitDeadline
            ))
        ));
        
        // Create cash token permit hash
        bytes32 takerPermitHash = keccak256(abi.encodePacked(
            "\x19\x01",
            takerTokenDomainSeparator,
            keccak256(abi.encode(
                PERMIT_TYPEHASH,
                buyerAddress,
                exchangeAddress,
                order.takerAmount,
                takerNonce,
                permitDeadline
            ))
        ));
        
        console.log("\n=== Signing Permits ===");
        
        // Sign security token permit with maker's private key
        (uint8 makerPermitV, bytes32 makerPermitR, bytes32 makerPermitS) = vm.sign(sellerPrivateKey, makerPermitHash);
        
        // Sign cash token permit with taker's private key
        (uint8 takerPermitV, bytes32 takerPermitR, bytes32 takerPermitS) = vm.sign(buyerPrivateKey, takerPermitHash);
        
        // Create TokenPermit structs
        makerPermit = PermitData.TokenPermit({
            token: securityTokenAddress,
            owner: sellerAddress,
            value: order.makerAmount,
            deadline: permitDeadline,
            v: makerPermitV,
            r: makerPermitR,
            s: makerPermitS
        });
        
        takerPermit = PermitData.TokenPermit({
            token: cashTokenAddress,
            owner: buyerAddress,
            value: order.takerAmount,
            deadline: permitDeadline,
            v: takerPermitV,
            r: takerPermitR,
            s: takerPermitS
        });
        
        console.log("Permits signed for both tokens (OK)");
        
        return (makerPermit, takerPermit);
    }
    
    /**
     * @notice Execute the meta-transaction with the Exchange contract
     */
    function executeMetaTransaction(
        Order.OrderInfo memory order,
        bytes memory makerSignature,
        bytes memory takerSignature,
        PermitData.TokenPermit memory makerPermit,
        PermitData.TokenPermit memory takerPermit
    ) internal {
        console.log("\n=== Executing Meta-Transaction ===");
        
        // Start a broadcast with the deployer's private key
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        
        try exchange.executeSignedOrderWithPermits(
            order,
            makerSignature,
            takerSignature,
            makerPermit,
            takerPermit
        ) {
            console.log("META-TRANSACTION EXECUTED SUCCESSFULLY!");
            
            // Check final balances
            uint256 newMakerBalance = securityToken.balanceOf(sellerAddress);
            uint256 newTakerBalance = cashToken.balanceOf(buyerAddress);
            uint256 buyerSecurityBalance = securityToken.balanceOf(buyerAddress);
            uint256 sellerCashBalance = cashToken.balanceOf(sellerAddress);
            
            console.log("\n=== Final Balances ===");
            console.log("Maker's security tokens:", newMakerBalance / 10**SECURITY_TOKEN_DECIMALS);
            console.log("Taker's cash tokens:", newTakerBalance / 10**CASH_TOKEN_DECIMALS);
            console.log("Taker's security tokens:", buyerSecurityBalance / 10**SECURITY_TOKEN_DECIMALS);
            console.log("Maker's cash tokens:", sellerCashBalance / 10**CASH_TOKEN_DECIMALS);
        } catch Error(string memory reason) {
            console.log("META-TRANSACTION FAILED");
            console.log("Reason:", reason);
            
            // Try to analyze the failure
            analyzeFailure(order, makerPermit, takerPermit);
        } catch {
            console.log("META-TRANSACTION FAILED WITH NO REASON");
            
            // Try to analyze the failure
            analyzeFailure(order, makerPermit, takerPermit);
        }
        
        vm.stopBroadcast();
    }
    
    /**
     * @notice Helper function to calculate domain separator for Exchange
     */
    function calculateDomainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(EXCHANGE_NAME)),
            keccak256(bytes(EXCHANGE_VERSION)),
            block.chainid,
            exchangeAddress
        ));
    }
    
    /**
     * @notice Helper function to calculate domain separator for tokens
     */
    function calculateTokenDomainSeparator(string memory tokenName, address tokenAddress) internal view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(tokenName)),
            keccak256(bytes("1")),
            block.chainid,
            tokenAddress
        ));
    }
    
    /**
     * @notice Try to analyze why the meta-transaction failed
     */
    function analyzeFailure(
        Order.OrderInfo memory order,
        PermitData.TokenPermit memory makerPermit,
        PermitData.TokenPermit memory takerPermit
    ) internal view {
        console.log("\n=== Analyzing Failure ===");
        
        // Check basic parameters
        if (block.timestamp > order.expiry) {
            console.log("ERROR: Order has expired!");
        }
        
        if (block.timestamp > makerPermit.deadline) {
            console.log("ERROR: Maker permit has expired!");
        }
        
        if (block.timestamp > takerPermit.deadline) {
            console.log("ERROR: Taker permit has expired!");
        }
        
        // Check balances
        if (securityToken.balanceOf(sellerAddress) < order.makerAmount) {
            console.log("ERROR: Maker has insufficient security token balance!");
        }
        
        if (cashToken.balanceOf(buyerAddress) < order.takerAmount) {
            console.log("ERROR: Taker has insufficient cash token balance!");
        }
        
        // Check allowances (if permits might have failed)
        if (securityToken.allowance(sellerAddress, exchangeAddress) < order.makerAmount) {
            console.log("ERROR: Maker has insufficient allowance and permit might have failed!");
        }
        
        if (cashToken.allowance(buyerAddress, exchangeAddress) < order.takerAmount) {
            console.log("ERROR: Taker has insufficient allowance and permit might have failed!");
        }
        
        // Try to check if tokens are registered
        try exchange.getRegistryContract() returns (address registryAddress) {
            console.log("Registry address:", registryAddress);
            
            if (registryAddress != address(0)) {
                // Try to check registration status
                try IRegistry(registryAddress).isRegisteredAsset(securityTokenAddress) returns (bool isRegistered) {
                    if (!isRegistered) {
                        console.log("ERROR: Security token is not registered!");
                    }
                } catch {
                    console.log("Could not check security token registration");
                }
                
                try IRegistry(registryAddress).isRegisteredAsset(cashTokenAddress) returns (bool isRegistered) {
                    if (!isRegistered) {
                        console.log("ERROR: Cash token is not registered!");
                    }
                } catch {
                    console.log("Could not check cash token registration");
                }
            }
        } catch {
            console.log("Could not get registry address from exchange");
        }
        
        // Check KYC status if possible
        try exchange.getComplianceContract() returns (address complianceAddress) {
            console.log("Compliance address:", complianceAddress);
            
            if (complianceAddress != address(0)) {
                bytes32 KYC_VERIFIED = keccak256("KYC_VERIFIED");
                
                try IComplianceChecker(complianceAddress).hasAttribute(
                    securityTokenAddress, sellerAddress, KYC_VERIFIED
                ) returns (bool hasKYC) {
                    if (!hasKYC) {
                        console.log("ERROR: Maker does not have KYC for security token!");
                    }
                } catch {
                    console.log("Could not check maker KYC status");
                }
                
                try IComplianceChecker(complianceAddress).hasAttribute(
                    securityTokenAddress, buyerAddress, KYC_VERIFIED
                ) returns (bool hasKYC) {
                    if (!hasKYC) {
                        console.log("ERROR: Taker does not have KYC for security token!");
                    }
                } catch {
                    console.log("Could not check taker KYC status");
                }
            }
        } catch {
            console.log("Could not get compliance address from exchange");
        }
        
        console.log("\nPotential solutions:");
        console.log("1. Check KYC verification for both parties");
        console.log("2. Ensure tokens are properly registered");
        console.log("3. Verify token balances are sufficient");
        console.log("4. Make sure order parameters are correct");
        console.log("5. Verify proper permissions and roles are set");
    }
}

interface IComplianceChecker {
    function hasAttribute(address token, address user, bytes32 attribute) external view returns (bool);
}

interface IRegistry {
    function isRegisteredAsset(address asset) external view returns (bool);
}

// Local interfaces for contracts we need to call but with different names to avoid conflicts
interface ISignaturesMixin {
    function getDomainSeparator() external view returns (bytes32);
    function hashOrder(Order.OrderInfo calldata order) external view returns (bytes32);
    function getOrderTypeHash() external view returns (bytes32);
}