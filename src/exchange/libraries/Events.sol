// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title Events
 * @notice Library defining events used in the Exchange system
 */
library Events {
    /**
     * @notice Emitted when a signed order is executed
     * @param orderHash The hash of the executed order
     * @param maker The address of the order maker
     * @param makerToken The token address the maker offered
     * @param makerAmount The amount of tokens the maker offered
     * @param taker The address of the order taker
     * @param takerToken The token address the taker offered
     * @param takerAmount The amount of tokens the taker offered
     * @param makerFee The fee amount paid by the maker
     * @param takerFee The fee amount paid by the taker
     */
    event SignedOrderExecuted(
        bytes32 indexed orderHash,
        address maker,
        address indexed makerToken,
        uint256 makerAmount,
        address taker,
        address indexed takerToken,
        uint256 takerAmount,
        uint256 makerFee,
        uint256 takerFee
    );

    /**
     * @notice Emitted when a signed order is cancelled
     * @param orderHash The hash of the cancelled order
     * @param canceller The address that cancelled the order
     */
    event SignedOrderCancelled(
        bytes32 indexed orderHash,
        address canceller
    );
    
    /**
     * @notice Emitted when fees are modified for a token pair
     * @param parity The hash representing the token pair
     * @param token1 The first token in the pair
     * @param token2 The second token in the pair
     * @param fee1 The fee for the first token
     * @param fee2 The fee for the second token
     * @param feeBase The base for fee calculation
     * @param fee1Wallet The wallet to receive fees from the first token
     * @param fee2Wallet The wallet to receive fees from the second token
     */
    event FeeModified(
        bytes32 indexed parity,
        address indexed token1,
        address indexed token2,
        uint fee1,
        uint fee2,
        uint feeBase,
        address fee1Wallet,
        address fee2Wallet
    );
    
    /**
     * @notice Emitted when the exchange is initialized
     * @param owner Address of the contract owner
     * @param feesContract Address of the fees contract
     * @param cancellationContract Address of the order cancellation contract
     * @param complianceContract Address of the compliance contract
     * @param signaturesContract Address of the signatures contract
     * @param registryContract Address of the registry contract
     */
    event ExchangeInitialized(
        address owner,
        address feesContract,
        address cancellationContract,
        address complianceContract,
        address signaturesContract,
        address registryContract
    );
    
    /**
     * @notice Emitted when ownership is transferred
     * @param previousOwner The previous owner of the contract
     * @param newOwner The new owner of the contract
     */
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    
    /**
     * @notice Emitted when the fees contract is updated
     * @param feesContract The new fees contract address
     */
    event FeesContractUpdated(
        address indexed feesContract
    );
    
    /**
     * @notice Emitted when the cancellation contract is updated
     * @param cancellationContract The new cancellation contract address
     */
    event CancellationContractUpdated(
        address indexed cancellationContract
    );
    
    /**
     * @notice Emitted when the compliance contract is updated
     * @param complianceContract The new compliance contract address
     */
    event ComplianceContractUpdated(
        address indexed complianceContract
    );
    
    /**
     * @notice Emitted when the signatures contract is updated
     * @param signaturesContract The new signatures contract address
     */
    event SignaturesContractUpdated(
        address indexed signaturesContract
    );
    
    /**
     * @notice Emitted when the registry contract is updated
     * @param registryContract The new registry contract address
     */
    event RegistryContractUpdated(
        address indexed registryContract
    );
    
    /**
     * @notice Emitted when ETH is received by the contract
     * @param sender The address that sent ETH
     * @param amount The amount of ETH received
     */
    event EthReceived(
        address indexed sender,
        uint256 amount
    );
    
    /**
     * @notice Emitted when the proxy implementation is updated
     * @param previousImplementation The previous implementation address
     * @param newImplementation The new implementation address
     */
    event ProxyImplementationUpdated(
        address indexed previousImplementation,
        address indexed newImplementation
    );
    
    /**
     * @notice Emitted when the proxy admin is updated
     * @param previousAdmin The previous admin address
     * @param newAdmin The new admin address
     */
    event ProxyAdminUpdated(
        address indexed previousAdmin,
        address indexed newAdmin
    );
}
