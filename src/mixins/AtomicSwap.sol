pragma solidity ^0.8.17;

import "@ar-security-token/src/interfaces/IToken.sol";
import "../mixins/Fees.sol";
import "../libraries/Order.sol";
import "../libraries/Events.sol";
import "../interfaces/IOrderCancellation.sol";
import "../interfaces/ICompliance.sol";
import "../interfaces/ISignatures.sol";
import "../interfaces/IAtomicSwap.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@ar-security-token/lib/st-identity-registry/src/libraries/Attributes.sol";

contract AtomicSwap is Ownable {
    /// variables
    // Fees contract reference
    IFees public feesContract;
    
    // Order cancellation contract reference
    IOrderCancellation public cancellationContract;
    
    // Compliance contract reference
    ICompliance public complianceContract;
    
    // Signatures contract reference
    ISignatures public signaturesContract;

    /// functions

    // initializes contracts
    constructor(
        address initialOwner,
        address _feesContract,
        address _cancellationContract,
        address _complianceContract,
        address _signaturesContract
    ) Ownable(initialOwner) {
        require(_feesContract != address(0), "Fees contract cannot be zero address");
        require(_cancellationContract != address(0), "Cancellation contract cannot be zero address");
        require(_complianceContract != address(0), "Compliance contract cannot be zero address");
        require(_signaturesContract != address(0), "Signatures contract cannot be zero address");
        
        feesContract = IFees(_feesContract);
        cancellationContract = IOrderCancellation(_cancellationContract);
        complianceContract = ICompliance(_complianceContract);
        signaturesContract = ISignatures(_signaturesContract);
    }

    /**
     * @dev Set the fees contract address
     * @param _feesContract The new fees contract address
     */
    function setFeesContract(address _feesContract) external onlyOwner {
        require(_feesContract != address(0), "Fees contract cannot be zero address");
        feesContract = IFees(_feesContract);
    }
    
    /**
     * @dev Set the cancellation contract address
     * @param _cancellationContract The new cancellation contract address
     */
    function setCancellationContract(address _cancellationContract) external onlyOwner {
        require(_cancellationContract != address(0), "Cancellation contract cannot be zero address");
        cancellationContract = IOrderCancellation(_cancellationContract);
    }
    
    /**
     * @dev Set the compliance contract address
     * @param _complianceContract The new compliance contract address
     */
    function setComplianceContract(address _complianceContract) external onlyOwner {
        require(_complianceContract != address(0), "Compliance contract cannot be zero address");
        complianceContract = ICompliance(_complianceContract);
    }
    
    /**
     * @dev Set the signatures contract address
     * @param _signaturesContract The new signatures contract address
     */
    function setSignaturesContract(address _signaturesContract) external onlyOwner {
        require(_signaturesContract != address(0), "Signatures contract cannot be zero address");
        signaturesContract = ISignatures(_signaturesContract);
    }

    /**
     * @dev Execute a swap with signed orders from both maker and taker
     * @param _order The order details
     * @param _makerSignature The signature of the maker
     * @param _takerSignature The signature of the taker
     */
    function executeSignedOrder(
        Order.OrderInfo calldata _order,
        bytes calldata _makerSignature,
        bytes calldata _takerSignature
    ) external {
        // Verify order hasn't expired
        require(block.timestamp <= _order.expiry, "Order expired");

        // Verify nonces match the current nonces
        require(
            cancellationContract.verifyNonce(_order.maker, _order.makerNonce),
            "Maker nonce invalid"
        );
        require(
            cancellationContract.verifyNonce(_order.taker, _order.takerNonce),
            "Taker nonce invalid"
        );

        // Get order hash for signature verification
        bytes32 orderHash = signaturesContract.hashOrder(_order);

        // Verify signatures
        require(
            signaturesContract.isValidSignature(_order, _makerSignature, _order.maker),
            "Invalid maker signature"
        );
        require(
            signaturesContract.isValidSignature(_order, _takerSignature, _order.taker),
            "Invalid taker signature"
        );

        // Check token balances and allowances
        IERC20 makerToken = IERC20(_order.makerToken);
        IERC20 takerToken = IERC20(_order.takerToken);
        
        // Verify maker has enough tokens and has approved this contract
        require(
            makerToken.balanceOf(_order.maker) >= _order.makerAmount,
            "Maker has insufficient balance"
        );
        require(
            makerToken.allowance(_order.maker, address(this)) >= _order.makerAmount,
            "Maker has not approved transfer"
        );
        
        // Verify taker has enough tokens and has approved this contract
        require(
            takerToken.balanceOf(_order.taker) >= _order.takerAmount,
            "Taker has insufficient balance"
        );
        require(
            takerToken.allowance(_order.taker, address(this)) >= _order.takerAmount,
            "Taker has not approved transfer"
        );

        // Calculate fees using the fees contract - now with single fee wallet
        (uint256 makerFee, uint256 takerFee, address feeWallet) = 
            feesContract.calculateOrderFees(
                _order.makerToken, 
                _order.takerToken, 
                _order.makerAmount, 
                _order.takerAmount
            );
        
        // Log transfer attempts for monitoring
        complianceContract.logTransferAttempt(
            _order.makerToken,
            _order.maker,
            _order.taker,
            _order.makerAmount - makerFee
        );
        
        complianceContract.logTransferAttempt(
            _order.takerToken,
            _order.taker,
            _order.maker,
            _order.takerAmount - takerFee
        );

        // Execute the swap with fees
        _executeSwap(
            makerToken,
            takerToken,
            _order.maker,
            _order.taker,
            _order.makerAmount,
            _order.takerAmount,
            makerFee,
            takerFee,
            feeWallet
        );
        
        // Mark nonces as used by advancing them AFTER successful execution
        cancellationContract.advanceNonce(_order.maker);
        cancellationContract.advanceNonce(_order.taker);

        emit Events.SignedOrderExecuted(
            orderHash,
            _order.maker,
            _order.makerToken,
            _order.makerAmount,
            _order.taker,
            _order.takerToken,
            _order.takerAmount,
            makerFee,
            takerFee
        );
    }

    /**
     * @dev Internal function to execute the swap with a single fee wallet
     */
    function _executeSwap(
        IERC20 makerToken,
        IERC20 takerToken,
        address maker,
        address taker,
        uint256 makerAmount,
        uint256 takerAmount,
        uint256 makerFee,
        uint256 takerFee,
        address feeWallet
    ) internal {
        // Handle maker tokens
        if (makerFee > 0 && feeWallet != address(0)) {
            // Safety check to avoid overflow
            require(makerFee <= makerAmount, "Fee exceeds amount");
            
            // Send tokens to taker (minus fee)
            makerToken.transferFrom(maker, taker, makerAmount - makerFee);
            
            // Send fee to fee wallet
            makerToken.transferFrom(maker, feeWallet, makerFee);
        } else {
            // No fee, send full amount
            makerToken.transferFrom(maker, taker, makerAmount);
        }

        // Handle taker tokens
        if (takerFee > 0 && feeWallet != address(0)) {
            // Safety check to avoid overflow
            require(takerFee <= takerAmount, "Fee exceeds amount");
            
            // Send tokens to maker (minus fee)
            takerToken.transferFrom(taker, maker, takerAmount - takerFee);
            
            // Send fee to fee wallet
            takerToken.transferFrom(taker, feeWallet, takerFee);
        } else {
            // No fee, send full amount
            takerToken.transferFrom(taker, maker, takerAmount);
        }
    }

    /**
     * @dev Wrapper function to cancel an order through the cancellation contract
     * @param _order The order to cancel
     * @param _signature The signature of the maker
     */
    function cancelOrder(Order.OrderInfo calldata _order, bytes calldata _signature) external {
        cancellationContract.cancelOrder(_order, _signature);
    }

    /**
     * @dev Wrapper function to cancel an order by both maker and taker
     * @param _order The order to cancel
     * @param _makerSignature The signature of the maker
     * @param _takerSignature The signature of the taker
     */
    function cancelOrderByBoth(
        Order.OrderInfo calldata _order,
        bytes calldata _makerSignature,
        bytes calldata _takerSignature
    ) external {
        cancellationContract.cancelOrderByBoth(_order, _makerSignature, _takerSignature);
    }

    /**
     * @dev Check if a token is a security token with attribute registry
     * @param _token The token address to check
     * @return True if the token is a security token, false otherwise
     */
    function isSecurityToken(address _token) public view returns (bool) {
        return complianceContract.isSecurityToken(_token);
    }

    /**
     * @dev Check if a user has KYC verification for a token
     * @param _token The token address to check
     * @param _user The user address to check
     * @return True if the user has KYC verification, false otherwise
     */
    function isKYCVerified(address _token, address _user) public view returns (bool) {
        return complianceContract.hasAttribute(_token, _user, Attributes.KYC_VERIFIED);
    }

    /**
     * @dev Check if a user is an accredited investor for a token
     * @param _token The token address to check
     * @param _user The user address to check
     * @return True if the user is an accredited investor, false otherwise
     */
    function isAccreditedInvestor(address _token, address _user) public view returns (bool) {
        return complianceContract.hasAttribute(_token, _user, Attributes.ACCREDITED_INVESTOR);
    }
}