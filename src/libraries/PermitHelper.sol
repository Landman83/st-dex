// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../interfaces/IERC20Permit.sol";

/**
 * @title PermitHelper
 * @notice Library for handling EIP-2612 permit operations
 * @dev Contains utility functions for safely executing permits
 */
library PermitHelper {
    /**
     * @notice Safely attempts to execute a permit function on a token
     * @dev Returns true if the permit was successfully executed, false otherwise
     * @param token Address of the token contract
     * @param owner Address of the token owner
     * @param spender Address of the spender
     * @param value Amount to approve
     * @param deadline Timestamp after which the permit is no longer valid
     * @param v Part of the ECDSA signature
     * @param r Part of the ECDSA signature
     * @param s Part of the ECDSA signature
     * @return success Whether the permit was successfully executed
     */
    function tryPermit(
        address token,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal returns (bool success) {
        // Safety check
        if (token == address(0)) return false;
        
        // Check if token supports permit
        if (!_supportsPermit(token)) {
            return false;
        }
        
        // Skip if deadline has passed
        if (block.timestamp > deadline) {
            return false;
        }
        
        // Try to execute the permit
        try IERC20Permit(token).permit(owner, spender, value, deadline, v, r, s) {
            return true;
        } catch {
            // If permit fails for any reason, return false but don't revert
            return false;
        }
    }
    
    /**
     * @notice Check if a token supports the EIP-2612 permit interface
     * @param token Address of the token contract
     * @return Whether the token supports permit
     */
    function _supportsPermit(address token) private view returns (bool) {
        // Simple check for permit support by trying to call DOMAIN_SEPARATOR
        (bool success, ) = token.staticcall(
            abi.encodeWithSignature("DOMAIN_SEPARATOR()")
        );
        return success;
    }
}