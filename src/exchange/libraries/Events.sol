// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title Events
 * @notice Library defining events used in the AtomicSwap system
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
}
