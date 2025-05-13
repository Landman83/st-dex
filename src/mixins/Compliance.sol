// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/ICompliance.sol";
import "@ar-security-token/src/interfaces/IToken.sol";
// IAttributeRegistry is imported via IToken.sol
import "@ar-security-token/lib/st-identity-registry/src/libraries/Attributes.sol";

/**
 * @title Compliance
 * @notice Implementation of token compliance checks using attribute registry
 */
contract Compliance is Ownable, ICompliance {
    // Event for transfer attempts (for monitoring and analytics)
    event TransferAttempt(
        address indexed token,
        address indexed from,
        address indexed to,
        uint256 amount,
        bool isSecurityToken
    );
    
    constructor(address initialOwner) Ownable(initialOwner) {}
    
    /**
     * @notice Check if a token is a security token with attribute registry
     * @param token The address of the token to check
     * @return True if the token is a security token, false otherwise
     */
    function isSecurityToken(address token) public view override returns (bool) {
        try IToken(token).attributeRegistry() returns (IAttributeRegistry _ar) {
            return address(_ar) != address(0);
        }
        catch {
            return false;
        }
    }
    
    /**
     * @notice Check if a user has a specific attribute for a token
     * @param token The address of the token to check
     * @param user The address of the user to check
     * @param attribute The attribute to check for
     * @return True if the user has the attribute, false otherwise
     */
    function hasAttribute(address token, address user, bytes32 attribute) public view override returns (bool) {
        if (!isSecurityToken(token)) return false;
        
        try IToken(token).attributeRegistry() returns (IAttributeRegistry attributeRegistry) {
            try attributeRegistry.hasAttribute(user, attribute) returns (bool hasAttr) {
                return hasAttr;
            } catch {
                return false;
            }
        } catch {
            return false;
        }
    }
    
    /**
     * @notice Log transfer attempts but don't enforce compliance at exchange level
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
    ) external override returns (bool) {
        bool isSecurity = isSecurityToken(token);
        
        // Emit event for monitoring
        emit TransferAttempt(token, from, to, amount, isSecurity);
        
        return true; // Always return true, as compliance is enforced at token level
    }
}