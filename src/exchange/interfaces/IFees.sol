// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../storage/FeeStorage.sol";

/**
 * @title IFees
 * @notice Interface for fee-related functionality
 */
interface IFees {
    /**
     * @notice Calculate fees for an order
     * @param makerToken The maker token address
     * @param takerToken The taker token address
     * @param makerAmount The maker token amount
     * @param takerAmount The taker token amount
     * @return makerFee The fee amount for maker
     * @return takerFee The fee amount for taker
     * @return fee1Wallet The wallet to receive maker fees
     * @return fee2Wallet The wallet to receive taker fees
     */
    function calculateOrderFees(
        address makerToken,
        address takerToken,
        uint256 makerAmount,
        uint256 takerAmount
    ) external view returns (
        uint256 makerFee,
        uint256 takerFee,
        address fee1Wallet,
        address fee2Wallet
    );

    /**
     * @notice Modify the fees applied to a parity of tokens
     * @param token1 The address of the base token for the parity
     * @param token2 The address of the counterpart token for the parity
     * @param fee1 The fee to apply on token1
     * @param fee2 The fee to apply on token2
     * @param feeBase The precision of the fee setting
     * @param fee1Wallet The wallet address receiving fees applied on token1
     * @param fee2Wallet The wallet address receiving fees applied on token2
     */
    function modifyFee(
        address token1,
        address token2,
        uint fee1,
        uint fee2,
        uint feeBase,
        address fee1Wallet,
        address fee2Wallet
    ) external;
    
    /**
     * @dev Calculates the parity byte signature for a token pair
     * @param token1 The address of the base token
     * @param token2 The address of the counterpart token
     * @return The byte signature of the parity
     */
    function calculateParity(address token1, address token2) external pure returns (bytes32);
    
    // Event FeeModified is defined in FeeStorage.sol
}