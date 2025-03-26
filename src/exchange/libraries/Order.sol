// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title Order
 * @notice Library defining the Order struct used in the AtomicSwap system
 */
library Order {
    /**
     * @notice Order struct representing a trade order
     * @param maker The address of the order maker
     * @param makerToken The token address the maker is offering
     * @param makerAmount The amount of tokens the maker is offering
     * @param taker The address of the order taker (can be zero address for any taker)
     * @param takerToken The token address the maker wants in return
     * @param takerAmount The amount of tokens the maker wants in return
     * @param makerNonce The maker's nonce to prevent replay attacks
     * @param takerNonce The taker's nonce to prevent replay attacks
     * @param expiry The timestamp when the order expires
     */
    struct OrderInfo {
        address maker;
        address makerToken;
        uint256 makerAmount;
        address taker;
        address takerToken;
        uint256 takerAmount;
        uint256 makerNonce;
        uint256 takerNonce;
        uint256 expiry;
    }
    
    /**
     * @dev EIP-712 Type Hash for OrderInfo struct
     */
    bytes32 public constant ORDER_TYPEHASH = keccak256(
        "OrderInfo(address maker,address makerToken,uint256 makerAmount,address taker,address takerToken,uint256 takerAmount,uint256 makerNonce,uint256 takerNonce,uint256 expiry)"
    );
}