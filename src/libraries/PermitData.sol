// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title PermitData
 * @notice Library for permit-related data structures
 * @dev Contains structures for EIP-2612 permit data
 */
library PermitData {
    /**
     * @notice Structure for EIP-2612 permit data
     * @param token Address of the token contract supporting EIP-2612
     * @param owner Address of the token owner
     * @param value Amount to approve
     * @param deadline Timestamp after which the permit is no longer valid
     * @param v Part of the ECDSA signature
     * @param r Part of the ECDSA signature
     * @param s Part of the ECDSA signature
     */
    struct TokenPermit {
        address token;
        address owner;
        uint256 value;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }
}