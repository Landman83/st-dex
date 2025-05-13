// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../libraries/Order.sol";
import "../libraries/PermitData.sol";

/**
 * @title IAtomicSwap
 * @notice Interface for the AtomicSwap functionality
 */
interface IAtomicSwap {
    /**
     * @notice Execute a swap with signed orders from both maker and taker
     * @param order The order details
     * @param makerSignature The signature of the maker
     * @param takerSignature The signature of the taker
     */
    function executeSignedOrder(
        Order.OrderInfo calldata order,
        bytes calldata makerSignature,
        bytes calldata takerSignature
    ) external;

    /**
     * @notice Cancel an order through the cancellation contract
     * @param order The order to cancel
     * @param signature The signature of the maker
     */
    function cancelOrder(
        Order.OrderInfo calldata order,
        bytes calldata signature
    ) external;

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
     * @notice Set the fees contract address
     * @param feesContract The new fees contract address
     */
    function setFeesContract(address feesContract) external;
    
    /**
     * @notice Set the cancellation contract address
     * @param cancellationContract The new cancellation contract address
     */
    function setCancellationContract(address cancellationContract) external;
    
    /**
     * @notice Set the compliance contract address
     * @param complianceContract The new compliance contract address
     */
    function setComplianceContract(address complianceContract) external;
    
    /**
     * @notice Set the signatures contract address
     * @param signaturesContract The new signatures contract address
     */
    function setSignaturesContract(address signaturesContract) external;

    /**
     * @notice Check if a token is a security token
     * @param token The token address to check
     * @return True if the token is a security token, false otherwise
     */
    function isSecurityToken(address token) external view returns (bool);
    
    /**
     * @notice Check if a user has KYC verification for a token
     * @param token The token address to check
     * @param user The user address to check
     * @return True if the user has KYC verification, false otherwise
     */
    function isKYCVerified(address token, address user) external view returns (bool);
    
    /**
     * @notice Check if a user is an accredited investor for a token
     * @param token The token address to check
     * @param user The user address to check
     * @return True if the user is an accredited investor, false otherwise
     */
    function isAccreditedInvestor(address token, address user) external view returns (bool);

    /**
     * @notice Execute a swap with signed orders and permit signatures for token approvals
     * @param order The order details
     * @param makerSignature The signature of the maker for the order
     * @param takerSignature The signature of the taker for the order
     * @param makerPermit The permit data for the maker's token
     * @param takerPermit The permit data for the taker's token
     */
    function executeSignedOrderWithPermits(
        Order.OrderInfo calldata order,
        bytes calldata makerSignature,
        bytes calldata takerSignature,
        PermitData.TokenPermit calldata makerPermit,
        PermitData.TokenPermit calldata takerPermit
    ) external;
}