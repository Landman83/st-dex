// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title AtomicSwapStorage
 * @notice Storage contract for the AtomicSwap system
 */
abstract contract AtomicSwapStorage {
    // EIP-712 Type Hashes
    bytes32 public constant ORDER_TYPEHASH = keccak256(
        "OrderInfo(address maker,address makerToken,uint256 makerAmount,address taker,address takerToken,uint256 takerAmount,uint256 makerNonce,uint256 takerNonce,uint256 expiry)"
    );
}