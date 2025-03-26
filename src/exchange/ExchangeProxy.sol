// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IProxy.sol";
import "./libraries/Events.sol";
import "./libraries/ExchangeErrors.sol";

/**
 * @title ExchangeProxy
 * @notice Proxy contract for the Exchange implementation
 * @dev Uses delegatecall to forward calls to the implementation contract
 */
contract ExchangeProxy is IProxy {
    // Storage slot with the address of the current implementation
    // This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    
    // Storage slot with the admin of the contract
    // This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1
    bytes32 private constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @notice Constructor sets the initial implementation and admin
     * @param _implementation Address of the initial implementation
     * @param _admin Address of the proxy admin
     */
    constructor(address _implementation, address _admin) {
        require(_implementation != address(0), ExchangeErrors.ZERO_ADDRESS);
        require(_admin != address(0), ExchangeErrors.ZERO_ADDRESS);
        
        _setImplementation(_implementation);
        _setAdmin(_admin);
        
        emit Events.ProxyImplementationUpdated(address(0), _implementation);
        emit Events.ProxyAdminUpdated(address(0), _admin);
    }
    
    /**
     * @notice Execute a function call on the implementation contract
     * @param data The calldata to execute
     * @return result The result of the function call
     */
    function execute(bytes calldata data) external payable override returns (bytes memory result) {
        address implementation = _getImplementation();
        
        // Execute the call on the implementation
        (bool success, bytes memory returnData) = implementation.delegatecall(data);
        
        // Check if the call was successful
        if (!success) {
            // If the call failed, bubble up the revert reason
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }
        
        return returnData;
    }
    
    /**
     * @notice Upgrades the implementation address
     * @param _newImplementation Address of the new implementation
     */
    function upgradeTo(address _newImplementation) external override {
        require(msg.sender == _getAdmin(), ExchangeErrors.ONLY_ADMIN);
        require(_newImplementation != address(0), ExchangeErrors.ZERO_ADDRESS);
        require(_newImplementation != _getImplementation(), ExchangeErrors.SAME_IMPLEMENTATION);
        
        address oldImplementation = _getImplementation();
        _setImplementation(_newImplementation);
        
        emit Events.ProxyImplementationUpdated(oldImplementation, _newImplementation);
    }
    
    /**
     * @notice Changes the admin of the proxy
     * @param _newAdmin Address of the new admin
     */
    function changeAdmin(address _newAdmin) external override {
        require(msg.sender == _getAdmin(), ExchangeErrors.ONLY_ADMIN);
        require(_newAdmin != address(0), ExchangeErrors.ZERO_ADDRESS);
        
        address oldAdmin = _getAdmin();
        _setAdmin(_newAdmin);
        
        emit Events.ProxyAdminUpdated(oldAdmin, _newAdmin);
    }
    
    /**
     * @notice Returns the current implementation address
     * @return The address of the implementation
     */
    function implementation() external view override returns (address) {
        return _getImplementation();
    }
    
    /**
     * @notice Returns the current admin address
     * @return The address of the admin
     */
    function admin() external view override returns (address) {
        return _getAdmin();
    }
    
    /**
     * @dev Fallback function that delegates calls to the implementation
     */
    fallback() external payable {
        _delegate(_getImplementation());
    }
    
    /**
     * @dev Receive function to accept ETH
     */
    receive() external payable {
        _delegate(_getImplementation());
    }
    
    /**
     * @dev Internal function to delegate the current call to the implementation
     * @param _implementation Address of the implementation to delegate to
     */
    function _delegate(address _implementation) internal {
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())
            
            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), _implementation, 0, calldatasize(), 0, 0)
            
            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())
            
            switch result
            // delegatecall returns 0 on error.
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
    
    /**
     * @dev Internal function to retrieve the implementation address
     * @return impl Address of the implementation
     */
    function _getImplementation() internal view returns (address impl) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            impl := sload(slot)
        }
    }
    
    /**
     * @dev Internal function to set the implementation address
     * @param _implementation Address of the implementation
     */
    function _setImplementation(address _implementation) internal {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            sstore(slot, _implementation)
        }
    }
    
    /**
     * @dev Internal function to retrieve the admin address
     * @return adm Address of the admin
     */
    function _getAdmin() internal view returns (address adm) {
        bytes32 slot = ADMIN_SLOT;
        assembly {
            adm := sload(slot)
        }
    }
    
    /**
     * @dev Internal function to set the admin address
     * @param _admin Address of the admin
     */
    function _setAdmin(address _admin) internal {
        bytes32 slot = ADMIN_SLOT;
        assembly {
            sstore(slot, _admin)
        }
    }
} 