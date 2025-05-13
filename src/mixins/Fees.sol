// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IFees.sol";
import "../storage/FeeStorage.sol";
import "../libraries/Events.sol";

/**
 * @title Fees
 * @notice Implementation of fee-related functionality for token exchange
 * @dev Handles fee calculations and fee settings for token pairs using a simplified fee wallet structure
 */
contract Fees is Ownable, FeeStorage, IFees {
    constructor(address initialOwner) Ownable(initialOwner) {}
    
    /**
     * @notice Calculate fees for an order
     * @param _makerToken The maker token address
     * @param _takerToken The taker token address
     * @param _makerAmount The maker token amount
     * @param _takerAmount The taker token amount
     * @return makerFee The fee amount for maker
     * @return takerFee The fee amount for taker
     * @return feeWallet The wallet to receive fees
     */
    function calculateOrderFees(
        address _makerToken,
        address _takerToken,
        uint256 _makerAmount,
        uint256 _takerAmount
    ) public view override returns (
        uint256 makerFee,
        uint256 takerFee,
        address feeWallet
    ) {
        bytes32 parity = calculateParity(_makerToken, _takerToken);
        Fee memory feeDetails = fee[parity];
        
        makerFee = 0;
        takerFee = 0;
        feeWallet = feeDetails.feeWallet;
        
        if (feeDetails.token1Fee != 0 || feeDetails.token2Fee != 0) {
            // Calculate fees with safeguards
            if (feeDetails.token1Fee != 0) {
                makerFee = (_makerAmount * feeDetails.token1Fee) / (10**feeDetails.feeBase);
                // Ensure fee doesn't exceed amount (shouldn't be more than 10%)
                require(makerFee <= _makerAmount / 10, "Fee1 too high");
            }
            
            if (feeDetails.token2Fee != 0) {
                takerFee = (_takerAmount * feeDetails.token2Fee) / (10**feeDetails.feeBase);
                // Ensure fee doesn't exceed amount (shouldn't be more than 10%)
                require(takerFee <= _takerAmount / 10, "Fee2 too high");
            }
        }
    }

    /**
     * @notice Modify the fees applied to a parity of tokens
     * @param _token1 The address of the base token for the parity
     * @param _token2 The address of the counterpart token for the parity
     * @param _fee1 The fee to apply on token1
     * @param _fee2 The fee to apply on token2
     * @param _feeBase The precision of the fee setting
     * @param _feeWallet The wallet address receiving fees
     */
    function modifyFee(
        address _token1,
        address _token2,
        uint _fee1,
        uint _fee2,
        uint _feeBase,
        address _feeWallet
    ) external override {
        // Only owner can modify fees
        require(msg.sender == owner(), "Only owner can call");
        
        // Validate token addresses
        require(
            IERC20(_token1).totalSupply() != 0 &&
            IERC20(_token2).totalSupply() != 0,
            "Invalid address: address is not an ERC20"
        );
        
        // Validate fee parameters
        require(
            _fee1 <= 10**_feeBase && _fee1 >= 0 &&
            _fee2 <= 10**_feeBase && _fee2 >= 0 &&
            _feeBase <= 5 &&
            _feeBase >= 2,
            "Invalid fee settings"
        );
        
        // Validate fee wallet
        if (_fee1 > 0 || _fee2 > 0) {
            require(_feeWallet != address(0), "Fee wallet cannot be zero address");
        }
        
        // Set fee for token1 -> token2 parity
        bytes32 _parity = calculateParity(_token1, _token2);
        Fee memory parityFee;
        parityFee.token1Fee = _fee1;
        parityFee.token2Fee = _fee2;
        parityFee.feeBase = _feeBase;
        parityFee.feeWallet = _feeWallet;
        fee[_parity] = parityFee;
        
        emit FeeModified(_parity, _token1, _token2, _fee1, _fee2, _feeBase, _feeWallet);
        
        // Set fee for token2 -> token1 parity (reverse direction)
        bytes32 _reflectParity = calculateParity(_token2, _token1);
        Fee memory reflectParityFee;
        reflectParityFee.token1Fee = _fee2;
        reflectParityFee.token2Fee = _fee1;
        reflectParityFee.feeBase = _feeBase;
        reflectParityFee.feeWallet = _feeWallet;
        fee[_reflectParity] = reflectParityFee;
        
        emit FeeModified(_reflectParity, _token2, _token1, _fee2, _fee1, _feeBase, _feeWallet);
    }

    /**
     * @dev Calculates the parity byte signature for a token pair
     * @param _token1 The address of the base token
     * @param _token2 The address of the counterpart token
     * @return The byte signature of the parity
     */
    function calculateParity(address _token1, address _token2) public pure override returns (bytes32) {
        return keccak256(abi.encode(_token1, _token2));
    }
}