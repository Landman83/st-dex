// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IRegistry
 * @notice Interface for the Registry contract that manages ERC20 and Rule506c token assets
 */
interface IRegistry {
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
    ) external;
    
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
    ) external;
    
    /**
     * @notice Add an alternative symbol for an existing token
     * @param tokenAddress Address of the token contract
     * @param symbol Alternative symbol for the token
     */
    function addTokenSymbol(
        address tokenAddress,
        string calldata symbol
    ) external;
    
    /**
     * @notice Get asset information by address
     * @param assetAddress Address of the asset
     * @return Asset struct with token information
     */
    function getAssetByAddress(address assetAddress) external view returns (Asset memory);
    
    /**
     * @notice Get asset information by symbol
     * @param symbol Symbol of the asset
     * @return Asset struct with token information
     */
    function getAssetBySymbol(string memory symbol) external view returns (Asset memory);
    
    /**
     * @notice Get asset information by symbol at a specific timestamp
     * @param symbol Symbol of the asset
     * @param timestamp Timestamp to check
     * @return Asset struct with token information
     */
    function getAssetBySymbolAtTimestamp(string memory symbol, uint64 timestamp) 
        external view returns (Asset memory);
    
    /**
     * @notice Check if an address is a registered and confirmed asset
     * @param assetAddress Address to check
     * @return True if the address is a confirmed asset
     */
    function isRegisteredAsset(address assetAddress) external view returns (bool);
    
    /**
     * @notice Check if an address is a registered and confirmed security token
     * @param assetAddress Address to check
     * @return True if the address is a confirmed security token
     */
    function isSecurityToken(address assetAddress) external view returns (bool);
    
    /**
     * @notice Get the native asset representation (e.g., ETH)
     * @return Asset struct for the native asset
     */
    function getNativeAsset() external view returns (Asset memory);
    
    /**
     * @notice Get the native asset symbol
     * @return The symbol of the native asset
     */
    function nativeAssetSymbol() external view returns (string memory);
    
    // Events
    event AssetRegistered(address indexed assetAddress, string symbol, uint8 decimals, bool isSecurityToken);
    event AssetConfirmed(address indexed assetAddress, string symbol, uint8 decimals, bool isSecurityToken);
    event SymbolAdded(address indexed assetAddress, string symbol);
}
