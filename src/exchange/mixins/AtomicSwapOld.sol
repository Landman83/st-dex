/* To-Do List (Progress)
- ✅ Eliminate DVD functionality. I only want the signed order and execute swap functionality.
- ✅ Only EIP712 signatures should be supported. No ECDSA signatures should be supported.
- ✅ Greatly expand modularity of the contract. 
    - ✅ Order struct should be provided by ../libraries/Order.sol.
    - ✅ All fee logic should be handled by Fees.sol. 
    - ✅ All hashing logic should be handled by Hashing.sol. 
    - ✅ All order cancellation logic should be handled by OrderCancellation.sol.
    - ✅ Events should be added and handled by ../libraries/Events.sol.
    - ✅ All signature verification should be handled by Signatures.sol.
- ✅ Use OpenZeppelin's Nonces contract for nonce handling
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/Order.sol";
import "../libraries/Events.sol";
import "../interfaces/IAtomicSwap.sol";
import "../interfaces/IFees.sol";
import "../interfaces/IHashing.sol";
import "../interfaces/IOrderCancellation.sol";
import "../storage/AtomicSwapStorage.sol";

/**
 * @title AtomicSwap
 * @notice Implementation of atomic swap functionality for token exchange
 * @dev Handles execution of signed orders using modular components
 */
contract AtomicSwapOld is Ownable, AtomicSwapStorage, IAtomicSwap {
    // Contract dependencies
    IFees public feesContract;
    IHashing public hashingContract;
    IOrderCancellation public orderCancellationContract;

    /**
     * @dev Constructor for AtomicSwap
     * @param _feesContract The address of the Fees contract
     * @param _hashingContract The address of the Hashing contract
     * @param _orderCancellationContract The address of the OrderCancellation contract
     */
    constructor(
        address _feesContract,
        address _hashingContract,
        address _orderCancellationContract
    ) {
        require(_feesContract != address(0), "Fees contract cannot be zero address");
        require(_hashingContract != address(0), "Hashing contract cannot be zero address");
        require(_orderCancellationContract != address(0), "OrderCancellation contract cannot be zero address");
        
        feesContract = IFees(_feesContract);
        hashingContract = IHashing(_hashingContract);
        orderCancellationContract = IOrderCancellation(_orderCancellationContract);
    }

    /**
     * @notice Execute a swap with a signed order
     * @param order The order details
     * @param signature The EIP-712 signature of the maker
     */
    function executeOrder(
        Order.OrderInfo calldata order,
        bytes calldata signature
    ) external override {
        // Verify order hasn't expired
        require(block.timestamp <= order.expiry, "Order expired");

        // Verify the nonce is valid and equals current nonce (hasn't been used)
        uint256 currentNonce = orderCancellationContract.nonces(order.maker);
        require(order.makerNonce == currentNonce, "Invalid or used nonce");

        // Get order hash and verify signature using the Hashing contract
        bytes32 orderHash = hashingContract.hashOrder(order);
        require(
            hashingContract.isValidSignature(order, signature, order.maker),
            "Invalid maker signature"
        );

        // Check if order is for a specific taker
        if (order.taker != address(0)) {
            require(msg.sender == order.taker, "Not authorized taker");
        }

        // Check token balances and allowances
        IERC20 makerToken = IERC20(order.makerToken);
        IERC20 takerToken = IERC20(order.takerToken);

        require(makerToken.balanceOf(order.maker) >= order.makerAmount, "Maker: insufficient balance");
        require(
            makerToken.allowance(order.maker, address(this)) >= order.makerAmount,
            "Maker: insufficient allowance"
        );

        require(takerToken.balanceOf(msg.sender) >= order.takerAmount, "Taker: insufficient balance");
        require(
            takerToken.allowance(msg.sender, address(this)) >= order.takerAmount,
            "Taker: insufficient allowance"
        );

        // Calculate fees using the Fees contract
        (uint256 makerFee, uint256 takerFee, address fee1Wallet, address fee2Wallet) = 
            feesContract.calculateOrderFees(
                order.makerToken,
                order.takerToken,
                order.makerAmount,
                order.takerAmount
            );

        // Execute the swap with fees
        _executeSwapWithFees(
            makerToken,
            takerToken,
            order.maker,
            msg.sender,
            order.makerAmount,
            order.takerAmount,
            makerFee,
            takerFee,
            fee1Wallet,
            fee2Wallet
        );
        
        // Increment the nonce for the maker using the OrderCancellation contract
        try orderCancellationContract.advanceNonce(order.maker) returns (uint256) {
            // Success, nonce advanced
        } catch {
            // Fallback to cancelling the order to increment nonce
            orderCancellationContract.cancelOrder(order, signature);
        }

        // Emit event using the Events library
        emit Events.SignedOrderExecuted(
            orderHash,
            order.maker,
            order.makerToken,
            order.makerAmount,
            msg.sender,
            order.takerToken,
            order.takerAmount,
            makerFee,
            takerFee
        );
    }

    /**
     * @notice Cancel a signed order by marking the nonce as used
     * @param order The order to cancel
     * @param signature The EIP-712 signature of the maker
     */
    function cancelOrder(
        Order.OrderInfo calldata order,
        bytes calldata signature
    ) external override {
        // Delegate to the OrderCancellation contract
        orderCancellationContract.cancelOrder(order, signature);
    }

    /**
     * @notice Verify if an order is valid and can be executed
     * @param order The order to check
     * @return isValid True if the order is valid, false otherwise
     */
    function isValidOrder(Order.OrderInfo calldata order) external view override returns (bool isValid) {
        // Order is invalid if expired
        if (block.timestamp > order.expiry) {
            return false;
        }
        
        // Order is invalid if nonce doesn't match current nonce
        if (orderCancellationContract.nonces(order.maker) != order.makerNonce) {
            return false;
        }
        
        // Order is invalid if maker doesn't have sufficient balance or allowance
        IERC20 makerToken = IERC20(order.makerToken);
        if (makerToken.balanceOf(order.maker) < order.makerAmount) {
            return false;
        }
        
        if (makerToken.allowance(order.maker, address(this)) < order.makerAmount) {
            return false;
        }
        
        return true;
    }

    /**
     * @notice Set the fees contract address
     * @param _feesContract The new fees contract address
     */
    function setFeesContract(address _feesContract) external onlyOwner {
        require(_feesContract != address(0), "Fees contract cannot be zero address");
        feesContract = IFees(_feesContract);
    }

    /**
     * @notice Set the hashing contract address
     * @param _hashingContract The new hashing contract address
     */
    function setHashingContract(address _hashingContract) external onlyOwner {
        require(_hashingContract != address(0), "Hashing contract cannot be zero address");
        hashingContract = IHashing(_hashingContract);
    }

    /**
     * @notice Set the order cancellation contract address
     * @param _orderCancellationContract The new order cancellation contract address
     */
    function setOrderCancellationContract(address _orderCancellationContract) external onlyOwner {
        require(_orderCancellationContract != address(0), "OrderCancellation contract cannot be zero address");
        orderCancellationContract = IOrderCancellation(_orderCancellationContract);
    }

    /**
     * @dev Internal function to execute the swap with fees
     */
    function _executeSwapWithFees(
        IERC20 makerToken,
        IERC20 takerToken,
        address maker,
        address taker,
        uint256 makerAmount,
        uint256 takerAmount,
        uint256 makerFee,
        uint256 takerFee,
        address fee1Wallet,
        address fee2Wallet
    ) internal {
        // Handle maker tokens
        if (makerFee > 0 && fee1Wallet != address(0)) {
            // Safety check to avoid overflow
            require(makerFee <= makerAmount, "Fee exceeds amount");
            
            // Send tokens to taker (minus fee)
            require(
                makerToken.transferFrom(maker, taker, makerAmount - makerFee),
                "Maker transfer to taker failed"
            );
            
            // Send fee to fee wallet
            require(
                makerToken.transferFrom(maker, fee1Wallet, makerFee),
                "Maker fee transfer failed"
            );
        } else {
            // No fee, send full amount
            require(
                makerToken.transferFrom(maker, taker, makerAmount),
                "Maker transfer failed"
            );
        }

        // Handle taker tokens
        if (takerFee > 0 && fee2Wallet != address(0)) {
            // Safety check to avoid overflow
            require(takerFee <= takerAmount, "Fee exceeds amount");
            
            // Send tokens to maker (minus fee)
            require(
                takerToken.transferFrom(taker, maker, takerAmount - takerFee),
                "Taker transfer to maker failed"
            );
            
            // Send fee to fee wallet
            require(
                takerToken.transferFrom(taker, fee2Wallet, takerFee),
                "Taker fee transfer failed"
            );
        } else {
            // No fee, send full amount
            require(
                takerToken.transferFrom(taker, maker, takerAmount),
                "Taker transfer failed"
            );
        }
    }
}