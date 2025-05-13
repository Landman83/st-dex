// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../storage/Storage.sol";
import "../libraries/ExchangeErrors.sol";
import "../libraries/Events.sol";

/**
 * @title Initializer
 * @notice Handles initialization logic for the Exchange contract
 * @dev Separates initialization logic from the main Exchange contract
 */
contract Initializer is Storage {
    /**
     * @notice Initialize the contract - can only be called once by the proxy
     * @param _owner The address of the contract owner
     * @param _feesContract Address of the fees contract
     * @param _cancellationContract Address of the order cancellation contract 
     * @param _complianceContract Address of the compliance contract
     * @param _signaturesContract Address of the signatures contract
     * @param _registryContract Address of the registry contract
     */
    function initialize(
        address _owner,
        address _feesContract,
        address _cancellationContract,
        address _complianceContract,
        address _signaturesContract,
        address _registryContract
    ) external {
        // Ensure contract is not already initialized
        require(!_initialized, ExchangeErrors.ALREADY_INITIALIZED);
        _initialized = true;
        
        // Set contract owner
        _contractOwner = _owner;
        
        // Set contract references
        require(_feesContract != address(0), ExchangeErrors.ZERO_ADDRESS);
        require(_cancellationContract != address(0), ExchangeErrors.ZERO_ADDRESS);
        require(_complianceContract != address(0), ExchangeErrors.ZERO_ADDRESS);
        require(_signaturesContract != address(0), ExchangeErrors.ZERO_ADDRESS);
        require(_registryContract != address(0), ExchangeErrors.ZERO_ADDRESS);
        
        feesContract = _feesContract;
        cancellationContract = _cancellationContract;
        complianceContract = _complianceContract;
        signaturesContract = _signaturesContract;
        registryContract = _registryContract;
        
        // Emit initialization event
        emit Events.ExchangeInitialized(
            _owner,
            _feesContract,
            _cancellationContract,
            _complianceContract,
            _signaturesContract,
            _registryContract
        );
    }
    
    /**
     * @notice Check if the contract is initialized
     * @return True if the contract is initialized
     */
    function isInitialized() external view returns (bool) {
        return _initialized;
    }
}
