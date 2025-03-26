// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../libraries/Order.sol";

/**
 * @title IOrderCancellation
 * @notice Interface for order cancellation functionality
 */
interface IOrderCancellation {
    /**
     * @notice Returns the next unused nonce for an address
     * @param owner The address to check
     * @return The current nonce for the owner
     */
    function nonces(address owner) external view returns (uint256);
    
    /**
     * @notice Verify nonce validity for a given address and nonce
     * @param owner The address to check
     * @param nonce The nonce to verify
     * @return True if the nonce is valid (not yet used), false otherwise
     */
    function verifyNonce(address owner, uint256 nonce) external view returns (bool);
    
    /**
     * @notice Public method to advance the nonce
     * @param owner The address whose nonce to increment
     * @return The previous nonce
     */
    function advanceNonce(address owner) external returns (uint256);
    
    /**
     * @notice Cancel an order by incrementing the maker's nonce
     * @param order The order to cancel
     * @param signature The signature of the maker
     */
    function cancelOrder(Order.OrderInfo calldata order, bytes calldata signature) external;
    
    /**
     * @notice Cancel an order by both maker and taker
     * @param order The order to cancel
     * @param makerSignature The signature of the maker
     * @param takerSignature The signature of the taker
     */
    function cancelOrderByBoth(
        Order.OrderInfo calldata order,
        bytes calldata makerSignature,
        bytes calldata takerSignature
    ) external;
    
    /**
     * @notice Use a specific nonce for an owner (for advanced use cases)
     * @param owner The address whose nonce to use
     * @param nonce The specific nonce to use
     */
    function useCheckedNonce(address owner, uint256 nonce) external;
}