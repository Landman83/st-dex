// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IProxy
 * @notice Interface for the proxy contract
 */
interface IProxy {
    /**
     * @notice Upgrades the implementation address
     * @param _newImplementation Address of the new implementation
     */
    function upgradeTo(address _newImplementation) external;
    
    /**
     * @notice Changes the admin of the proxy
     * @param _newAdmin Address of the new admin
     */
    function changeAdmin(address _newAdmin) external;
    
    /**
     * @notice Returns the current implementation address
     * @return The address of the implementation
     */
    function implementation() external view returns (address);
    
    /**
     * @notice Returns the current admin address
     * @return The address of the admin
     */
    function admin() external view returns (address);
    
    /**
     * @notice Execute a function call on the implementation contract
     * @param data The calldata to execute
     * @return result The result of the function call
     */
    function execute(bytes calldata data) external payable returns (bytes memory result);
}