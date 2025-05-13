// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title Storage
 * @notice Base storage contract for the exchange
 * @dev Defines the storage layout for the upgradeable exchange contract
 */
contract Storage {
    // Initialization flag
    bool internal _initialized;
    
    // Owner of the contract
    address internal _contractOwner;
    
    // Contract references
    address internal feesContract;
    address internal cancellationContract;
    address internal complianceContract;
    address internal signaturesContract;
    address internal registryContract;
    
    // Reserve storage slots for future upgrades
    uint256[50] private __gap;
}