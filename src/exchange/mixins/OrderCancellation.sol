// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Nonces.sol";
import "../libraries/Order.sol";
import "../libraries/Events.sol";
import "../interfaces/IOrderCancellation.sol";
import "../interfaces/ISignatures.sol";

/**
 * @title OrderCancellation
 * @notice Implementation of order cancellation functionality using OpenZeppelin's Nonces
 */
contract OrderCancellation is Ownable, Nonces, IOrderCancellation {
    // The Signatures contract for signature verification
    ISignatures public signaturesContract;
    
    /**
     * @dev Constructor
     * @param _signaturesContract The address of the signatures contract
     */
    constructor(address initialOwner, address _signaturesContract) Ownable(initialOwner) {
        require(_signaturesContract != address(0), "Signatures contract cannot be zero address");
        signaturesContract = ISignatures(_signaturesContract);
    }
    
    /**
     * @notice Set the signatures contract address
     * @param _signaturesContract The new signatures contract address
     */
    function setSignaturesContract(address _signaturesContract) external onlyOwner {
        require(_signaturesContract != address(0), "Signatures contract cannot be zero address");
        signaturesContract = ISignatures(_signaturesContract);
    }
    
    /**
     * @notice Returns the next unused nonce for an address
     * @param owner The address to check
     * @return The current nonce for the owner
     */
    function nonces(address owner) public view override(Nonces, IOrderCancellation) returns (uint256) {
        return super.nonces(owner);
    }
    
    /**
     * @notice Verify nonce validity for a given address and nonce
     * @param owner The address to check
     * @param nonce The nonce to verify
     * @return True if the nonce is valid (not yet used), false otherwise
     */
    function verifyNonce(address owner, uint256 nonce) external view override returns (bool) {
        return nonce == nonces(owner);
    }
    
    /**
     * @notice Public method to advance the nonce (for use by SecureSwap)
     * @param owner The address whose nonce to increment
     * @return The previous nonce
     */
    function advanceNonce(address owner) external override returns (uint256) {
        // Only allow calls from authorized contracts or the owner themselves
        require(msg.sender == owner || owner == tx.origin, "Not authorized to advance nonce");
        return _useNonce(owner);
    }
    
    /**
     * @notice Cancel an order by incrementing the maker's nonce
     * @param order The order to cancel
     * @param signature The signature of the maker
     */
    function cancelOrder(Order.OrderInfo calldata order, bytes calldata signature) external override {
        // Hash the order
        bytes32 orderHash = signaturesContract.hashOrder(order);
        
        // Verify signature
        require(
            signaturesContract.isValidSignature(order, signature, order.maker),
            "Invalid maker signature"
        );
        
        // Verify the caller is the maker
        require(order.maker == msg.sender, "Only maker can cancel");
        
        // Ensure the nonce in the order matches the current nonce
        uint256 currentNonce = nonces(order.maker);
        
        if (order.makerNonce == currentNonce) {
            // Use the nonce, which will increment it
            _useNonce(order.maker);
        } else if (order.makerNonce > currentNonce) {
            // If the order nonce is in the future, we need to catch up
            // This is an edge case that should be avoided in practice
            for (uint256 i = currentNonce; i <= order.makerNonce; i++) {
                _useNonce(order.maker);
            }
        } else {
            // If the order nonce is in the past, it's already invalid
            revert("Order nonce already used");
        }
        
        // Emit event using the Events library
        emit Events.SignedOrderCancelled(orderHash, msg.sender);
    }
    
    /**
     * @notice Cancel an order by both maker and taker
     * @param order The order to cancel
     * @param makerSignature The signature of the maker
     * @param takerSignature The signature of the taker
     */
    function cancelOrderByBoth(
        Order.OrderInfo calldata order,
        bytes calldata makerSignature,
        bytes calldata takerSignature
    ) external override {
        // Hash the order
        bytes32 orderHash = signaturesContract.hashOrder(order);
        
        // Verify maker signature
        require(
            signaturesContract.isValidSignature(order, makerSignature, order.maker),
            "Invalid maker signature"
        );
        
        // Verify taker signature
        require(
            signaturesContract.isValidSignature(order, takerSignature, order.taker),
            "Invalid taker signature"
        );
        
        // Verify the caller is either the maker or taker
        require(
            msg.sender == order.maker || msg.sender == order.taker,
            "Only maker or taker can cancel"
        );
        
        // Handle maker nonce
        uint256 makerCurrentNonce = nonces(order.maker);
        if (order.makerNonce == makerCurrentNonce) {
            _useNonce(order.maker);
        } else if (order.makerNonce > makerCurrentNonce) {
            for (uint256 i = makerCurrentNonce; i <= order.makerNonce; i++) {
                _useNonce(order.maker);
            }
        } else {
            // If the order nonce is in the past, it's already invalid for the maker
            // We'll continue with the taker nonce
        }
        
        // Handle taker nonce
        uint256 takerCurrentNonce = nonces(order.taker);
        if (order.takerNonce == takerCurrentNonce) {
            _useNonce(order.taker);
        } else if (order.takerNonce > takerCurrentNonce) {
            for (uint256 i = takerCurrentNonce; i <= order.takerNonce; i++) {
                _useNonce(order.taker);
            }
        } else {
            // If the order nonce is in the past, it's already invalid for the taker
        }
        
        // Emit event
        emit Events.SignedOrderCancelled(orderHash, msg.sender);
    }
    
    /**
     * @notice Use a specific nonce for an owner (for advanced use cases)
     * @param owner The address whose nonce to use
     * @param nonce The specific nonce to use
     */
    function useCheckedNonce(address owner, uint256 nonce) external {
        // Only allow the owner to use their own nonce
        require(msg.sender == owner, "Only owner can use their nonce");
        
        // Use OpenZeppelin's checked nonce function
        _useCheckedNonce(owner, nonce);
    }
}