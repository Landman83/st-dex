// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title ExchangeErrors
 * @notice Library containing error messages for the exchange
 */
library ExchangeErrors {
    // General errors
    string public constant ZERO_ADDRESS = "Zero address not allowed";
    string public constant ONLY_OWNER = "Only owner can call this function";
    string public constant ONLY_ADMIN = "Only admin can call this function";
    string public constant ALREADY_INITIALIZED = "Contract already initialized";
    string public constant SAME_IMPLEMENTATION = "Cannot upgrade to same implementation";
    
    // Order errors
    string public constant ORDER_EXPIRED = "Order has expired";
    string public constant MAKER_NONCE_INVALID = "Maker nonce is invalid";
    string public constant TAKER_NONCE_INVALID = "Taker nonce is invalid";
    string public constant INVALID_MAKER_SIGNATURE = "Invalid maker signature";
    string public constant INVALID_TAKER_SIGNATURE = "Invalid taker signature";
    string public constant TOKEN_NOT_REGISTERED = "Token not registered";
    string public constant SWAP_NOT_COMPLIANT = "Swap does not comply with token restrictions";
    string public constant INSUFFICIENT_MAKER_BALANCE = "Maker has insufficient balance";
    string public constant INSUFFICIENT_MAKER_ALLOWANCE = "Maker has insufficient allowance";
    string public constant INSUFFICIENT_TAKER_BALANCE = "Taker has insufficient balance";
    string public constant INSUFFICIENT_TAKER_ALLOWANCE = "Taker has insufficient allowance";
    string public constant FEE_EXCEEDS_AMOUNT = "Fee exceeds transfer amount";
    string public constant MAKER_TRANSFER_FAILED = "Maker token transfer failed";
    string public constant MAKER_FEE_TRANSFER_FAILED = "Maker fee transfer failed";
    string public constant TAKER_TRANSFER_FAILED = "Taker token transfer failed";
    string public constant TAKER_FEE_TRANSFER_FAILED = "Taker fee transfer failed";
} 