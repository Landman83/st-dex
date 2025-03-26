// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./interfaces/IExchange.sol";
import "./mixins/AtomicSwap.sol";
import "./mixins/Compliance.sol";
import "./mixins/Fees.sol";
import "./mixins/OrderCancellation.sol";
import "./mixins/Signatures.sol";
import "./mixins/Registry.sol";
import "./mixins/Initializer.sol";
import "./libraries/Order.sol";
import "./libraries/Events.sol";
import "./libraries/ExchangeErrors.sol";

/**
 * @title Exchange
 * @notice Main exchange contract that integrates all features for token trading
 * @dev This contract is designed to be used with a proxy for upgradeability
 */
contract Exchange is IExchange, Initializer, ReentrancyGuard {
    // Version information
    string public constant VERSION = "1.0.0";
    
    // Constructor only initializes values, actual initialization happens via initialize()
    constructor() {
        // Prevent implementation contract from being initialized
        _initialized = true;
    }
    
    /**
     * @notice Execute a swap with signed orders from both maker and taker
     * @param _order The order details
     * @param _makerSignature The signature of the maker
     * @param _takerSignature The signature of the taker
     */
    function executeSignedOrder(
        Order.OrderInfo calldata _order,
        bytes calldata _makerSignature,
        bytes calldata _takerSignature
    ) external override nonReentrant {
        // Verify order hasn't expired
        require(block.timestamp <= _order.expiry, ExchangeErrors.ORDER_EXPIRED);

        // Forward to the order cancellation contract to verify nonces
        require(
            IOrderCancellation(cancellationContract).verifyNonce(_order.maker, _order.makerNonce),
            ExchangeErrors.MAKER_NONCE_INVALID
        );
        require(
            IOrderCancellation(cancellationContract).verifyNonce(_order.taker, _order.takerNonce),
            ExchangeErrors.TAKER_NONCE_INVALID
        );

        // Verify with signature contract
        bytes32 orderHash = ISignatures(signaturesContract).hashOrder(_order);
        
        require(
            ISignatures(signaturesContract).isValidSignature(_order, _makerSignature, _order.maker),
            ExchangeErrors.INVALID_MAKER_SIGNATURE
        );
        require(
            ISignatures(signaturesContract).isValidSignature(_order, _takerSignature, _order.taker),
            ExchangeErrors.INVALID_TAKER_SIGNATURE
        );

        // Verify tokens via registry
        require(
            Registry(registryContract).isRegisteredAsset(_order.makerToken),
            ExchangeErrors.TOKEN_NOT_REGISTERED
        );
        require(
            Registry(registryContract).isRegisteredAsset(_order.takerToken),
            ExchangeErrors.TOKEN_NOT_REGISTERED
        );

        // Check token balances and allowances
        IERC20 makerToken = IERC20(_order.makerToken);
        IERC20 takerToken = IERC20(_order.takerToken);
        
        // Verify maker has enough tokens and has approved this contract
        require(
            makerToken.balanceOf(_order.maker) >= _order.makerAmount,
            ExchangeErrors.INSUFFICIENT_MAKER_BALANCE
        );
        require(
            makerToken.allowance(_order.maker, address(this)) >= _order.makerAmount,
            ExchangeErrors.INSUFFICIENT_MAKER_ALLOWANCE
        );
        
        // Verify taker has enough tokens and has approved this contract
        require(
            takerToken.balanceOf(_order.taker) >= _order.takerAmount,
            ExchangeErrors.INSUFFICIENT_TAKER_BALANCE
        );
        require(
            takerToken.allowance(_order.taker, address(this)) >= _order.takerAmount,
            ExchangeErrors.INSUFFICIENT_TAKER_ALLOWANCE
        );

        // Calculate fees
        (uint256 makerFee, uint256 takerFee, address fee1Wallet, address fee2Wallet) = 
            IFees(feesContract).calculateOrderFees(
                _order.makerToken, 
                _order.takerToken, 
                _order.makerAmount, 
                _order.takerAmount
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
            fee1Wallet,
            fee2Wallet
        );
        
        // Mark nonces as used
        IOrderCancellation(cancellationContract).advanceNonce(_order.maker);
        IOrderCancellation(cancellationContract).advanceNonce(_order.taker);

        // Emit event
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
     * @notice Internal function to execute the token swap
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
        address fee1Wallet,
        address fee2Wallet
    ) internal {
        // Handle maker tokens
        if (makerFee > 0 && fee1Wallet != address(0)) {
            // Safety check to avoid overflow
            require(makerFee <= makerAmount, ExchangeErrors.FEE_EXCEEDS_AMOUNT);
            
            // Send tokens to taker (minus fee)
            require(
                makerToken.transferFrom(maker, taker, makerAmount - makerFee),
                ExchangeErrors.MAKER_TRANSFER_FAILED
            );
            
            // Send fee to fee wallet
            require(
                makerToken.transferFrom(maker, fee1Wallet, makerFee),
                ExchangeErrors.MAKER_FEE_TRANSFER_FAILED
            );
        } else {
            // No fee, send full amount
            require(
                makerToken.transferFrom(maker, taker, makerAmount),
                ExchangeErrors.MAKER_TRANSFER_FAILED
            );
        }

        // Handle taker tokens
        if (takerFee > 0 && fee2Wallet != address(0)) {
            // Safety check to avoid overflow
            require(takerFee <= takerAmount, ExchangeErrors.FEE_EXCEEDS_AMOUNT);
            
            // Send tokens to maker (minus fee)
            require(
                takerToken.transferFrom(taker, maker, takerAmount - takerFee),
                ExchangeErrors.TAKER_TRANSFER_FAILED
            );
            
            // Send fee to fee wallet
            require(
                takerToken.transferFrom(taker, fee2Wallet, takerFee),
                ExchangeErrors.TAKER_FEE_TRANSFER_FAILED
            );
        } else {
            // No fee, send full amount
            require(
                takerToken.transferFrom(taker, maker, takerAmount),
                ExchangeErrors.TAKER_TRANSFER_FAILED
            );
        }
    }
    
    /**
     * @notice Cancel an order
     * @param _order The order to cancel
     * @param _signature The signature of the maker
     */
    function cancelOrder(Order.OrderInfo calldata _order, bytes calldata _signature) 
        external 
        override 
        nonReentrant 
    {
        IOrderCancellation(cancellationContract).cancelOrder(_order, _signature);
    }
    
    /**
     * @notice Cancel an order by both maker and taker
     * @param _order The order to cancel
     * @param _makerSignature The signature of the maker
     * @param _takerSignature The signature of the taker
     */
    function cancelOrderByBoth(
        Order.OrderInfo calldata _order,
        bytes calldata _makerSignature,
        bytes calldata _takerSignature
    ) external override nonReentrant {
        IOrderCancellation(cancellationContract).cancelOrderByBoth(
            _order, 
            _makerSignature, 
            _takerSignature
        );
    }

    /**
     * @notice Update the fees contract address
     * @param _feesContract The new fees contract address
     */
    function setFeesContract(address _feesContract) external override {
        require(msg.sender == _contractOwner, ExchangeErrors.ONLY_OWNER);
        require(_feesContract != address(0), ExchangeErrors.ZERO_ADDRESS);
        feesContract = _feesContract;
        emit Events.FeesContractUpdated(_feesContract);
    }
    
    /**
     * @notice Update the cancellation contract address
     * @param _cancellationContract The new cancellation contract address
     */
    function setCancellationContract(address _cancellationContract) external override {
        require(msg.sender == _contractOwner, ExchangeErrors.ONLY_OWNER);
        require(_cancellationContract != address(0), ExchangeErrors.ZERO_ADDRESS);
        cancellationContract = _cancellationContract;
        emit Events.CancellationContractUpdated(_cancellationContract);
    }
    
    /**
     * @notice Update the compliance contract address
     * @param _complianceContract The new compliance contract address
     */
    function setComplianceContract(address _complianceContract) external override {
        require(msg.sender == _contractOwner, ExchangeErrors.ONLY_OWNER);
        require(_complianceContract != address(0), ExchangeErrors.ZERO_ADDRESS);
        complianceContract = _complianceContract;
        emit Events.ComplianceContractUpdated(_complianceContract);
    }
    
    /**
     * @notice Update the signatures contract address
     * @param _signaturesContract The new signatures contract address
     */
    function setSignaturesContract(address _signaturesContract) external override {
        require(msg.sender == _contractOwner, ExchangeErrors.ONLY_OWNER);
        require(_signaturesContract != address(0), ExchangeErrors.ZERO_ADDRESS);
        signaturesContract = _signaturesContract;
        emit Events.SignaturesContractUpdated(_signaturesContract);
    }
    
    /**
     * @notice Update the registry contract address
     * @param _registryContract The new registry contract address
     */
    function setRegistryContract(address _registryContract) external override {
        require(msg.sender == _contractOwner, ExchangeErrors.ONLY_OWNER);
        require(_registryContract != address(0), ExchangeErrors.ZERO_ADDRESS);
        registryContract = _registryContract;
        emit Events.RegistryContractUpdated(_registryContract);
    }
    
    /**
     * @notice Transfer ownership of the contract
     * @param _newOwner The address of the new owner
     */
    function transferOwnership(address _newOwner) external override {
        require(msg.sender == _contractOwner, ExchangeErrors.ONLY_OWNER);
        require(_newOwner != address(0), ExchangeErrors.ZERO_ADDRESS);
        
        address previousOwner = _contractOwner;
        _contractOwner = _newOwner;
        
        emit Events.OwnershipTransferred(previousOwner, _newOwner);
    }
    
    /**
     * @notice Get the current contract owner
     * @return The address of the contract owner
     */
    function owner() external view override returns (address) {
        return _contractOwner;
    }
    
    /**
     * @notice Get the feesContract address
     * @return The address of the fees contract
     */
    function getFeesContract() external view override returns (address) {
        return feesContract;
    }
    
    /**
     * @notice Get the cancellationContract address
     * @return The address of the cancellation contract
     */
    function getCancellationContract() external view override returns (address) {
        return cancellationContract;
    }
    
    /**
     * @notice Get the complianceContract address
     * @return The address of the compliance contract
     */
    function getComplianceContract() external view override returns (address) {
        return complianceContract;
    }
    
    /**
     * @notice Get the signaturesContract address
     * @return The address of the signatures contract
     */
    function getSignaturesContract() external view override returns (address) {
        return signaturesContract;
    }
    
    /**
     * @notice Get the registryContract address
     * @return The address of the registry contract
     */
    function getRegistryContract() external view override returns (address) {
        return registryContract;
    }
    
    /**
     * @notice Receive function to allow receiving ETH
     */
    receive() external payable {
        emit Events.EthReceived(msg.sender, msg.value);
    }
}