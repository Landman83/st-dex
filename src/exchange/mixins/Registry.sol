// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@Rule506c/token/IToken.sol";

/**
 * @title Registry
 * @notice Registry for ERC20 and Rule506c token assets in the DEX
 * @dev Maintains mapping of tokens by address and symbol with verification support for security tokens
 */
contract Registry is Ownable {
    // Asset struct to store token information
    struct Asset {
        bool exists;                // Whether the asset exists in the registry
        address assetAddress;       // Contract address of the token
        string symbol;              // Token symbol
        uint8 decimals;             // Token decimals
        bool isConfirmed;           // Whether token registration is confirmed
        uint64 confirmedTimestamp;  // Timestamp when the token was confirmed
        bool isSecurityToken;       // Whether it's a Rule506c security token
    }
    
    // Storage for assets
    mapping(address => Asset) public assetsByAddress;
    mapping(string => Asset[]) public assetsBySymbol;
    
    // Native chain asset symbol (e.g., "ETH" for Ethereum)
    string public nativeAssetSymbol;
    
    // Events
    event AssetRegistered(address indexed assetAddress, string symbol, uint8 decimals, bool isSecurityToken);
    event AssetConfirmed(address indexed assetAddress, string symbol, uint8 decimals, bool isSecurityToken);
    event SymbolAdded(address indexed assetAddress, string symbol);
    
    /**
     * @dev Constructor
     * @param _nativeAssetSymbol Symbol for the native asset (e.g., "ETH")
     */
    constructor(string memory _nativeAssetSymbol) Ownable(msg.sender) {
        nativeAssetSymbol = _nativeAssetSymbol;
    }
    
    /**
     * @notice Register a token in the registry
     * @param tokenAddress Address of the token contract
     * @param symbol Symbol of the token
     * @param decimals Number of decimals for the token
     * @param isSecurityToken Whether the token is a security token (Rule506c)
     */
    function registerToken(
        address tokenAddress,
        string calldata symbol,
        uint8 decimals,
        bool isSecurityToken
    ) external onlyOwner {
        require(decimals <= 32, "Token cannot have more than 32 decimals");
        require(
            tokenAddress != address(0) && _isContract(tokenAddress),
            "Invalid token address"
        );
        require(bytes(symbol).length > 0, "Invalid token symbol");
        require(
            !assetsByAddress[tokenAddress].isConfirmed,
            "Token already finalized"
        );
        
        // Verify based on token type
        if (isSecurityToken) {
            // Verify it's a Rule506c token by checking for identity registry
            try IToken(tokenAddress).identityRegistry() returns (IIdentityRegistry) {
                // If this doesn't revert, it's a valid Rule506c token
            } catch {
                revert("Not a valid Rule506c token");
            }
        } else {
            // For regular ERC20, verify basic interface
            try IERC20(tokenAddress).totalSupply() returns (uint256) {
                // If this doesn't revert, it's a valid ERC20 token
            } catch {
                revert("Not a valid ERC20 token");
            }
        }
        
        assetsByAddress[tokenAddress] = Asset({
            exists: true,
            assetAddress: tokenAddress,
            symbol: symbol,
            decimals: decimals,
            isConfirmed: false,
            confirmedTimestamp: 0,
            isSecurityToken: isSecurityToken
        });
        
        emit AssetRegistered(tokenAddress, symbol, decimals, isSecurityToken);
    }
    
    /**
     * @dev Internal function to check if an address is a contract
     * @param account Address to check
     * @return True if the address has code, false otherwise
     */
    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
    
    /**
     * @notice Confirm a previously registered token
     * @param tokenAddress Address of the token contract
     * @param symbol Symbol of the token
     * @param decimals Number of decimals for the token
     * @param isSecurityToken Whether the token is a security token (Rule506c)
     */
    function confirmTokenRegistration(
        address tokenAddress,
        string calldata symbol,
        uint8 decimals,
        bool isSecurityToken
    ) external onlyOwner {
        Asset storage asset = assetsByAddress[tokenAddress];
        require(asset.exists, "Unknown token");
        require(!asset.isConfirmed, "Token already finalized");
        require(isStringEqual(asset.symbol, symbol), "Symbols do not match");
        require(asset.decimals == decimals, "Decimals do not match");
        require(asset.isSecurityToken == isSecurityToken, "Security token status does not match");
        
        asset.isConfirmed = true;
        asset.confirmedTimestamp = uint64(block.timestamp);
        assetsBySymbol[symbol].push(asset);
        
        emit AssetConfirmed(tokenAddress, symbol, decimals, isSecurityToken);
    }
    
    /**
     * @notice Add an alternative symbol for an existing token
     * @param tokenAddress Address of the token contract
     * @param symbol Alternative symbol for the token
     */
    function addTokenSymbol(
        address tokenAddress,
        string calldata symbol
    ) external onlyOwner {
        Asset storage asset = assetsByAddress[tokenAddress];
        require(
            asset.exists && asset.isConfirmed,
            "Registration of token not finalized"
        );
        require(
            !isStringEqual(symbol, nativeAssetSymbol),
            "Symbol reserved for native asset"
        );
        
        // Update confirmation timestamp to mark this as a newer version
        asset.confirmedTimestamp = uint64(block.timestamp);
        
        assetsBySymbol[symbol].push(asset);
        
        emit SymbolAdded(tokenAddress, symbol);
    }
    
    /**
     * @notice Get asset information by address
     * @param assetAddress Address of the asset
     * @return Asset struct with token information
     */
    function getAssetByAddress(address assetAddress)
        external
        view
        returns (Asset memory)
    {
        if (assetAddress == address(0)) {
            return getNativeAsset();
        }
        
        Asset memory asset = assetsByAddress[assetAddress];
        require(
            asset.exists && asset.isConfirmed,
            "No confirmed asset found for address"
        );
        
        return asset;
    }
    
    /**
     * @notice Get asset information by symbol
     * @param symbol Symbol of the asset
     * @return Asset struct with token information
     */
    function getAssetBySymbol(string memory symbol)
        external
        view
        returns (Asset memory)
    {
        if (isStringEqual(nativeAssetSymbol, symbol)) {
            return getNativeAsset();
        }
        
        require(assetsBySymbol[symbol].length > 0, "No asset found for symbol");
        
        // Return the most recently confirmed asset with this symbol
        Asset memory mostRecent;
        uint64 mostRecentTimestamp = 0;
        
        for (uint i = 0; i < assetsBySymbol[symbol].length; i++) {
            Asset memory current = assetsBySymbol[symbol][i];
            if (current.confirmedTimestamp > mostRecentTimestamp) {
                mostRecent = current;
                mostRecentTimestamp = current.confirmedTimestamp;
            }
        }
        
        require(
            mostRecent.exists && mostRecent.isConfirmed,
            "No confirmed asset found for symbol"
        );
        
        return mostRecent;
    }
    
    /**
     * @notice Get asset information by symbol at a specific timestamp
     * @param symbol Symbol of the asset
     * @param timestamp Timestamp to check
     * @return Asset struct with token information
     */
    function getAssetBySymbolAtTimestamp(string memory symbol, uint64 timestamp)
        external
        view
        returns (Asset memory)
    {
        if (isStringEqual(nativeAssetSymbol, symbol)) {
            return getNativeAsset();
        }
        
        Asset memory asset;
        if (assetsBySymbol[symbol].length > 0) {
            // Find the most recent asset confirmed before the timestamp
            uint64 mostRecentTimestamp = 0;
            
            for (uint i = 0; i < assetsBySymbol[symbol].length; i++) {
                Asset memory current = assetsBySymbol[symbol][i];
                if (current.confirmedTimestamp <= timestamp && 
                    current.confirmedTimestamp > mostRecentTimestamp) {
                    asset = current;
                    mostRecentTimestamp = current.confirmedTimestamp;
                }
            }
        }
        
        require(
            asset.exists && asset.isConfirmed,
            "No confirmed asset found for symbol at that timestamp"
        );
        
        return asset;
    }
    
    /**
     * @notice Check if an address is a registered and confirmed asset
     * @param assetAddress Address to check
     * @return True if the address is a confirmed asset
     */
    function isRegisteredAsset(address assetAddress) external view returns (bool) {
        Asset memory asset = assetsByAddress[assetAddress];
        return asset.exists && asset.isConfirmed;
    }
    
    /**
     * @notice Check if an address is a registered and confirmed security token
     * @param assetAddress Address to check
     * @return True if the address is a confirmed security token
     */
    function isSecurityToken(address assetAddress) external view returns (bool) {
        Asset memory asset = assetsByAddress[assetAddress];
        return asset.exists && asset.isConfirmed && asset.isSecurityToken;
    }
    
    /**
     * @notice Get the native asset representation (e.g., ETH)
     * @return Asset struct for the native asset
     */
    function getNativeAsset() public view returns (Asset memory) {
        return Asset({
            exists: true,
            assetAddress: address(0),
            symbol: nativeAssetSymbol,
            decimals: 18,
            isConfirmed: true,
            confirmedTimestamp: 0,
            isSecurityToken: false
        });
    }
    
    /**
     * @notice Compare two strings for equality
     * @param a First string
     * @param b Second string
     * @return True if strings are equal
     */
    function isStringEqual(string memory a, string memory b)
        internal
        pure
        returns (bool)
    {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
}
