// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../libraries/Order.sol";

/**
 * @title IExchange
 * @notice Interface for the main exchange contract
 * @dev Defines core functionality for the DEX exchange
 */
interface IExchange {
    /**
     * @notice Execute a swap with signed orders from both maker and taker
     * @param _order The order details
     * @param _makerSignature The signature of the maker
     * @param _takerSignature The signature of the taker
     */
    function executeSignedOrder(
        Order.OrderInfo calldata _order,
        bytes calldata _makerSignature,
        bytes calldata _takerSignature
    ) external;
    
    /**
     * @notice Cancel an order
     * @param _order The order to cancel
     * @param _signature The signature of the maker
     */
    function cancelOrder(Order.OrderInfo calldata _order, bytes calldata _signature) external;
    
    /**
     * @notice Cancel an order by both maker and taker
     * @param _order The order to cancel
     * @param _makerSignature The signature of the maker
     * @param _takerSignature The signature of the taker
     */
    function cancelOrderByBoth(
        Order.OrderInfo calldata _order,
        bytes calldata _makerSignature,
        bytes calldata _takerSignature
    ) external;

    /**
     * @notice Update the fees contract address
     * @param _feesContract The new fees contract address
     */
    function setFeesContract(address _feesContract) external;
    
    /**
     * @notice Update the cancellation contract address
     * @param _cancellationContract The new cancellation contract address
     */
    function setCancellationContract(address _cancellationContract) external;
    
    /**
     * @notice Update the compliance contract address
     * @param _complianceContract The new compliance contract address
     */
    function setComplianceContract(address _complianceContract) external;
    
    /**
     * @notice Update the signatures contract address
     * @param _signaturesContract The new signatures contract address
     */
    function setSignaturesContract(address _signaturesContract) external;
    
    /**
     * @notice Update the registry contract address
     * @param _registryContract The new registry contract address
     */
    function setRegistryContract(address _registryContract) external;
    
    /**
     * @notice Transfer ownership of the contract
     * @param _newOwner The address of the new owner
     */
    function transferOwnership(address _newOwner) external;
    
    /**
     * @notice Get the current contract owner
     * @return The address of the contract owner
     */
    function owner() external view returns (address);
    
    /**
     * @notice Get the feesContract address
     * @return The address of the fees contract
     */
    function getFeesContract() external view returns (address);
    
    /**
     * @notice Get the cancellationContract address
     * @return The address of the cancellation contract
     */
    function getCancellationContract() external view returns (address);
    
    /**
     * @notice Get the complianceContract address
     * @return The address of the compliance contract
     */
    function getComplianceContract() external view returns (address);
    
    /**
     * @notice Get the signaturesContract address
     * @return The address of the signatures contract
     */
    function getSignaturesContract() external view returns (address);
    
    /**
     * @notice Get the registryContract address
     * @return The address of the registry contract
     */
    function getRegistryContract() external view returns (address);
}