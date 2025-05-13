// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title FeeStorage
 * @notice Storage contract for fee-related data in the exchange system with simplified fee wallet structure
 */
abstract contract FeeStorage {
    /**
     * @notice Fee structure for a token pair with a single fee wallet
     * @param token1Fee Fee percentage for the first token
     * @param token2Fee Fee percentage for the second token
     * @param feeBase The precision of the fee (e.g., 2 means percentage, 4 means basis points)
     * @param feeWallet Wallet address to receive fees
     */
    struct Fee {
        uint token1Fee;
        uint token2Fee;
        uint feeBase;
        address feeWallet;
    }

    /**
     * @notice Structure for fees to be applied to a specific transaction
     * @param txFee1 The fee amount for the first token
     * @param txFee2 The fee amount for the second token
     * @param feeWallet The wallet to receive fees
     */
    struct TxFees {
        uint txFee1;
        uint txFee2;
        address feeWallet;
    }

    // fee details linked to a parity of tokens (token pair)
    mapping(bytes32 => Fee) public fee;

    // Event for fee modifications
    event FeeModified(
        bytes32 indexed parity,
        address token1,
        address token2,
        uint fee1,
        uint fee2,
        uint feeBase,
        address feeWallet
    );
}