// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title ICompliance
 * @notice Interface for token compliance checks using attribute registry
 */
interface ICompliance {
    /**
     * @notice Check if a token is a security token with attribute registry
     * @param token The address of the token to check
     * @return True if the token is a security token, false otherwise
     */
    function isSecurityToken(address token) external view returns (bool);
    
    /**
     * @notice Check if a user has a specific attribute for a token
     * @param token The address of the token to check
     * @param user The address of the user to check
     * @param attribute The attribute to check for
     * @return True if the user has the attribute, false otherwise
     */
    function hasAttribute(address token, address user, bytes32 attribute) external view returns (bool);
    
    /**
     * @notice Log transfer attempts for monitoring purposes
     * @param token The address of the token being transferred
     * @param from The address sending the tokens
     * @param to The address receiving the tokens
     * @param amount The amount of tokens being transferred
     * @return Always returns true as compliance is enforced at token level
     */
    function logTransferAttempt(
        address token, 
        address from, 
        address to, 
        uint256 amount
    ) external returns (bool);
}