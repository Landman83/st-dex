// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/Exchange.sol";
import "../src/mixins/Fees.sol";
import "../src/mixins/Compliance.sol";
import "../src/mixins/OrderCancellation.sol";
import "../src/mixins/Signatures.sol";
import "../src/mixins/Registry.sol";
import "../src/libraries/Order.sol";
import "../src/libraries/ExchangeErrors.sol";
import "../src/libraries/PermitData.sol";
import "../src/libraries/PermitHelper.sol";
import "../src/interfaces/ISignatures.sol";
import "../src/interfaces/IERC20Permit.sol";

/**
 * @title ERC20PermitMock
 * @notice Mock ERC20 token with EIP-2612 permit support for testing
 * @dev Implements a basic version of permit to test meta-transactions
 */
contract ERC20PermitMock is Test {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) private _nonces;
    
    // EIP-712 domain separator
    bytes32 private _DOMAIN_SEPARATOR;
    
    // EIP-2612 typehash
    bytes32 public constant PERMIT_TYPEHASH = 
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    
    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
        
        // Calculate domain separator based on chain ID
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        
        _DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(_name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }
    
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _DOMAIN_SEPARATOR;
    }
    
    function nonces(address owner) external view returns (uint256) {
        return _nonces[owner];
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }
    
    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        
        _approve(from, msg.sender, currentAllowance - amount);
        _transfer(from, to, amount);
        
        return true;
    }
    
    /**
     * @dev Implementation of the EIP-2612 permit function
     * @param owner The owner of the tokens
     * @param spender The spender to approve
     * @param value The amount to approve
     * @param deadline The deadline after which the signature is no longer valid
     * @param v The recovery ID of the signature
     * @param r The first 32 bytes of the signature
     * @param s The second 32 bytes of the signature
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, "ERC20Permit: expired deadline");
        
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                owner,
                spender,
                value,
                _nonces[owner]++,
                deadline
            )
        );
        
        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                _DOMAIN_SEPARATOR,
                structHash
            )
        );
        
        address signer = ecrecover(hash, v, r, s);
        require(signer == owner, "ERC20Permit: invalid signature");
        
        _approve(owner, spender, value);
    }
    
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(_balances[from] >= amount, "ERC20: transfer amount exceeds balance");
        
        _balances[from] -= amount;
        _balances[to] += amount;
    }
    
    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");
        
        totalSupply += amount;
        _balances[account] += amount;
    }
    
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        
        _allowances[owner][spender] = amount;
    }
}

// Mock registry for testing
contract MockRegistry {
    mapping(address => bool) public registeredAssets;

    function isRegisteredAsset(address asset) external view returns (bool) {
        return registeredAssets[asset];
    }

    function registerAsset(address asset) external {
        registeredAssets[asset] = true;
    }
}

// Helper for creating permits for testing
contract TestPermitHelper is Test {
    // Create EIP-712 domain for a token
    function getTokenDomain(address token, string memory tokenName) internal view returns (bytes32) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(tokenName)),
                keccak256(bytes("1")),
                chainId,
                token
            )
        );
    }
    
    // Create permit signature using test private key
    function createPermitSignature(
        uint256 privateKey,
        address token,
        string memory tokenName,
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 domainSeparator = getTokenDomain(token, tokenName);
        
        bytes32 PERMIT_TYPEHASH = 
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
            
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                owner,
                spender,
                value,
                nonce,
                deadline
            )
        );
        
        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );
        
        (v, r, s) = vm.sign(privateKey, hash);
    }
}

contract MetaTransactionTest is Test, TestPermitHelper {
    // Main contracts
    Exchange public exchange;

    // Component contracts
    Fees public fees;
    OrderCancellation public orderCancellation;
    Compliance public compliance;
    Signatures public signatures;
    Registry public registry;

    // Test tokens with permit support
    ERC20PermitMock public makerToken;
    ERC20PermitMock public takerToken;
    
    // Test accounts
    uint256 public makerPrivateKey = 0x1;
    uint256 public takerPrivateKey = 0x2;
    address public owner;
    address public maker;
    address public taker;
    address public feeWallet;
    
    // Initial balances
    uint256 public constant INITIAL_BALANCE = 1000 ether;
    
    function setUp() public {
        // Setup test accounts
        owner = vm.addr(0x999);
        maker = vm.addr(makerPrivateKey);
        taker = vm.addr(takerPrivateKey);
        feeWallet = vm.addr(0x888);
        
        vm.startPrank(owner);
        
        // Deploy tokens with permit support
        makerToken = new ERC20PermitMock("Maker Token", "MKRT");
        takerToken = new ERC20PermitMock("Taker Token", "TKRT");
        
        // Mint tokens to maker and taker
        makerToken.mint(maker, INITIAL_BALANCE);
        takerToken.mint(taker, INITIAL_BALANCE);
        
        // Deploy component contracts
        signatures = new Signatures("Numena Exchange", "1.0.0");
        orderCancellation = new OrderCancellation(owner, address(signatures));
        compliance = new Compliance(owner);
        fees = new Fees(owner);
        registry = new Registry("ETH");
        
        // Register tokens in the registry
        registry.registerToken(address(makerToken), "MKRT", 18, false);
        registry.registerToken(address(takerToken), "TKRT", 18, false);
        registry.confirmTokenRegistration(address(makerToken), "MKRT", 18, false);
        registry.confirmTokenRegistration(address(takerToken), "TKRT", 18, false);
        
        // Configure fees for token pair
        fees.modifyFee(
            address(makerToken),
            address(takerToken),
            1, // 1% fee on makerToken
            2, // 2% fee on takerToken
            2, // fee base (10^2 = 100, so percentages)
            feeWallet
        );
        
        // Deploy Exchange implementation
        exchange = new Exchange();
        
        // Initialize the Exchange directly (no proxy for test simplicity)
        exchange.initialize(
            owner,                      // Owner
            address(fees),              // Fees contract
            address(orderCancellation), // Cancellation contract
            address(compliance),        // Compliance contract
            address(signatures),        // Signatures contract
            address(registry)           // Registry contract
        );
        
        // Set the Exchange contract address in the OrderCancellation contract
        orderCancellation.setExchangeContract(address(exchange));
        
        vm.stopPrank();
    }
    
    /**
     * @notice Test executing an order with standard approvals
     * @dev This helps as a baseline to compare with meta-transactions
     */
    function testStandardExecution() public {
        // Create order parameters
        uint256 makerAmount = 100 ether;
        uint256 takerAmount = 200 ether;
        uint256 expiry = block.timestamp + 1 days;
        
        // Create order
        Order.OrderInfo memory order = Order.OrderInfo({
            maker: maker,
            makerToken: address(makerToken),
            makerAmount: makerAmount,
            taker: taker,
            takerToken: address(takerToken),
            takerAmount: takerAmount,
            makerNonce: orderCancellation.nonces(maker),
            takerNonce: orderCancellation.nonces(taker),
            expiry: expiry
        });
        
        // Create order signatures
        bytes32 orderHash = signatures.hashOrder(order);
        (uint8 makerV, bytes32 makerR, bytes32 makerS) = vm.sign(makerPrivateKey, orderHash);
        bytes memory makerSignature = abi.encodePacked(makerR, makerS, makerV);
        
        (uint8 takerV, bytes32 takerR, bytes32 takerS) = vm.sign(takerPrivateKey, orderHash);
        bytes memory takerSignature = abi.encodePacked(takerR, takerS, takerV);
        
        // Approve tokens using standard approve
        vm.prank(maker);
        makerToken.approve(address(exchange), makerAmount);
        
        vm.prank(taker);
        takerToken.approve(address(exchange), takerAmount);
        
        // Execute the order through a third party (owner)
        vm.prank(owner);
        exchange.executeSignedOrder(order, makerSignature, takerSignature);
        
        // Verify balances
        uint256 makerFee = makerAmount * 1 / 100; // 1%
        uint256 takerFee = takerAmount * 2 / 100; // 2%
        
        // Maker sent tokens and received taker tokens minus fee
        assertEq(makerToken.balanceOf(maker), INITIAL_BALANCE - makerAmount);
        assertEq(takerToken.balanceOf(maker), takerAmount - takerFee);
        
        // Taker sent tokens and received maker tokens minus fee
        assertEq(takerToken.balanceOf(taker), INITIAL_BALANCE - takerAmount);
        assertEq(makerToken.balanceOf(taker), makerAmount - makerFee);
        
        // Fee wallet received fees
        assertEq(makerToken.balanceOf(feeWallet), makerFee);
        assertEq(takerToken.balanceOf(feeWallet), takerFee);
    }
    
    /**
     * @notice Test executing an order with meta-transactions (permit)
     * @dev This shows how orders can be executed without prior approvals
     */
    function testMetaTransactionExecution() public {
        // Create order parameters
        uint256 makerAmount = 100 ether;
        uint256 takerAmount = 200 ether;
        uint256 expiry = block.timestamp + 1 days;
        
        // Create order
        Order.OrderInfo memory order = Order.OrderInfo({
            maker: maker,
            makerToken: address(makerToken),
            makerAmount: makerAmount,
            taker: taker,
            takerToken: address(takerToken),
            takerAmount: takerAmount,
            makerNonce: orderCancellation.nonces(maker),
            takerNonce: orderCancellation.nonces(taker),
            expiry: expiry
        });
        
        // Create order signatures
        bytes32 orderHash = signatures.hashOrder(order);
        (uint8 makerV, bytes32 makerR, bytes32 makerS) = vm.sign(makerPrivateKey, orderHash);
        bytes memory makerSignature = abi.encodePacked(makerR, makerS, makerV);
        
        (uint8 takerV, bytes32 takerR, bytes32 takerS) = vm.sign(takerPrivateKey, orderHash);
        bytes memory takerSignature = abi.encodePacked(takerR, takerS, takerV);
        
        // Create permit deadline (30 days in the future)
        uint256 deadline = block.timestamp + 30 days;
        
        // Create permit signatures for maker token
        (uint8 makerPermitV, bytes32 makerPermitR, bytes32 makerPermitS) = createPermitSignature(
            makerPrivateKey,
            address(makerToken),
            "Maker Token",
            maker,
            address(exchange),
            makerAmount,
            0, // Current nonce
            deadline
        );
        
        // Create permit signatures for taker token
        (uint8 takerPermitV, bytes32 takerPermitR, bytes32 takerPermitS) = createPermitSignature(
            takerPrivateKey,
            address(takerToken),
            "Taker Token",
            taker,
            address(exchange),
            takerAmount,
            0, // Current nonce
            deadline
        );
        
        // Create permit structures
        PermitData.TokenPermit memory makerPermit = PermitData.TokenPermit({
            token: address(makerToken),
            owner: maker,
            value: makerAmount,
            deadline: deadline,
            v: makerPermitV,
            r: makerPermitR,
            s: makerPermitS
        });
        
        PermitData.TokenPermit memory takerPermit = PermitData.TokenPermit({
            token: address(takerToken),
            owner: taker,
            value: takerAmount,
            deadline: deadline,
            v: takerPermitV,
            r: takerPermitR,
            s: takerPermitS
        });
        
        // Execute the order with permits - without any prior approvals
        vm.prank(owner);
        exchange.executeSignedOrderWithPermits(
            order,
            makerSignature,
            takerSignature,
            makerPermit,
            takerPermit
        );
        
        // Verify balances
        uint256 makerFee = makerAmount * 1 / 100; // 1%
        uint256 takerFee = takerAmount * 2 / 100; // 2%
        
        // Maker sent tokens and received taker tokens minus fee
        assertEq(makerToken.balanceOf(maker), INITIAL_BALANCE - makerAmount);
        assertEq(takerToken.balanceOf(maker), takerAmount - takerFee);
        
        // Taker sent tokens and received maker tokens minus fee
        assertEq(takerToken.balanceOf(taker), INITIAL_BALANCE - takerAmount);
        assertEq(makerToken.balanceOf(taker), makerAmount - makerFee);
        
        // Fee wallet received fees
        assertEq(makerToken.balanceOf(feeWallet), makerFee);
        assertEq(takerToken.balanceOf(feeWallet), takerFee);
    }
    
    /**
     * @notice Test partial meta-transaction execution
     * @dev Tests using permit for one token but standard approval for the other
     */
    function testMixedMetaTransaction() public {
        // Create order parameters
        uint256 makerAmount = 100 ether;
        uint256 takerAmount = 200 ether;
        uint256 expiry = block.timestamp + 1 days;
        
        // Create order
        Order.OrderInfo memory order = Order.OrderInfo({
            maker: maker,
            makerToken: address(makerToken),
            makerAmount: makerAmount,
            taker: taker,
            takerToken: address(takerToken),
            takerAmount: takerAmount,
            makerNonce: orderCancellation.nonces(maker),
            takerNonce: orderCancellation.nonces(taker),
            expiry: expiry
        });
        
        // Create order signatures
        bytes32 orderHash = signatures.hashOrder(order);
        (uint8 makerV, bytes32 makerR, bytes32 makerS) = vm.sign(makerPrivateKey, orderHash);
        bytes memory makerSignature = abi.encodePacked(makerR, makerS, makerV);
        
        (uint8 takerV, bytes32 takerR, bytes32 takerS) = vm.sign(takerPrivateKey, orderHash);
        bytes memory takerSignature = abi.encodePacked(takerR, takerS, takerV);
        
        // Standard approve for maker token
        vm.prank(maker);
        makerToken.approve(address(exchange), makerAmount);
        
        // Create permit only for taker token
        uint256 deadline = block.timestamp + 30 days;
        (uint8 takerPermitV, bytes32 takerPermitR, bytes32 takerPermitS) = createPermitSignature(
            takerPrivateKey,
            address(takerToken),
            "Taker Token",
            taker,
            address(exchange),
            takerAmount,
            0, // Current nonce
            deadline
        );
        
        // Create empty permit for maker (will use approval)
        PermitData.TokenPermit memory makerPermit = PermitData.TokenPermit({
            token: address(0), // Zero address means no permit
            owner: address(0),
            value: 0,
            deadline: 0,
            v: 0,
            r: bytes32(0),
            s: bytes32(0)
        });
        
        // Create permit for taker
        PermitData.TokenPermit memory takerPermit = PermitData.TokenPermit({
            token: address(takerToken),
            owner: taker,
            value: takerAmount,
            deadline: deadline,
            v: takerPermitV,
            r: takerPermitR,
            s: takerPermitS
        });
        
        // Execute the order with mixed approvals
        vm.prank(owner);
        exchange.executeSignedOrderWithPermits(
            order,
            makerSignature,
            takerSignature,
            makerPermit,
            takerPermit
        );
        
        // Verify transfers occurred
        uint256 makerFee = makerAmount * 1 / 100; // 1%
        uint256 takerFee = takerAmount * 2 / 100; // 2%
        
        assertEq(makerToken.balanceOf(maker), INITIAL_BALANCE - makerAmount);
        assertEq(takerToken.balanceOf(maker), takerAmount - takerFee);
        assertEq(takerToken.balanceOf(taker), INITIAL_BALANCE - takerAmount);
        assertEq(makerToken.balanceOf(taker), makerAmount - makerFee);
    }
    
    /**
     * @notice Test that expired permit fails but order can still be executed with approvals
     */
    function testExpiredPermit() public {
        // Create order parameters
        uint256 makerAmount = 100 ether;
        uint256 takerAmount = 200 ether;
        uint256 expiry = block.timestamp + 1 days;
        
        // Create order
        Order.OrderInfo memory order = Order.OrderInfo({
            maker: maker,
            makerToken: address(makerToken),
            makerAmount: makerAmount,
            taker: taker,
            takerToken: address(takerToken),
            takerAmount: takerAmount,
            makerNonce: orderCancellation.nonces(maker),
            takerNonce: orderCancellation.nonces(taker),
            expiry: expiry
        });
        
        // Create order signatures
        bytes32 orderHash = signatures.hashOrder(order);
        (uint8 makerV, bytes32 makerR, bytes32 makerS) = vm.sign(makerPrivateKey, orderHash);
        bytes memory makerSignature = abi.encodePacked(makerR, makerS, makerV);
        
        (uint8 takerV, bytes32 takerR, bytes32 takerS) = vm.sign(takerPrivateKey, orderHash);
        bytes memory takerSignature = abi.encodePacked(takerR, takerS, takerV);
        
        // Create EXPIRED permit (timestamp in the past)
        uint256 expiredDeadline = block.timestamp - 1;
        (uint8 makerPermitV, bytes32 makerPermitR, bytes32 makerPermitS) = createPermitSignature(
            makerPrivateKey,
            address(makerToken),
            "Maker Token",
            maker,
            address(exchange),
            makerAmount,
            0, // Current nonce
            expiredDeadline
        );
        
        // Add standard approvals since permits will fail
        vm.prank(maker);
        makerToken.approve(address(exchange), makerAmount);
        
        vm.prank(taker);
        takerToken.approve(address(exchange), takerAmount);
        
        // Create permit structures with expired deadline
        PermitData.TokenPermit memory makerPermit = PermitData.TokenPermit({
            token: address(makerToken),
            owner: maker,
            value: makerAmount,
            deadline: expiredDeadline,
            v: makerPermitV,
            r: makerPermitR,
            s: makerPermitS
        });
        
        // Empty taker permit
        PermitData.TokenPermit memory takerPermit = PermitData.TokenPermit({
            token: address(0),
            owner: address(0),
            value: 0,
            deadline: 0,
            v: 0,
            r: bytes32(0),
            s: bytes32(0)
        });
        
        // Execute with expired permit but valid approvals
        vm.prank(owner);
        exchange.executeSignedOrderWithPermits(
            order,
            makerSignature,
            takerSignature,
            makerPermit,
            takerPermit
        );
        
        // Verify the order executed despite expired permit
        assertLt(makerToken.balanceOf(maker), INITIAL_BALANCE);
        assertGt(takerToken.balanceOf(maker), 0);
    }
    
    /**
     * @notice Test that permits with invalid signatures are handled gracefully
     */
    function testInvalidPermitSignature() public {
        // Create order parameters
        uint256 makerAmount = 100 ether;
        uint256 takerAmount = 200 ether;
        uint256 expiry = block.timestamp + 1 days;
        
        // Create order
        Order.OrderInfo memory order = Order.OrderInfo({
            maker: maker,
            makerToken: address(makerToken),
            makerAmount: makerAmount,
            taker: taker,
            takerToken: address(takerToken),
            takerAmount: takerAmount,
            makerNonce: orderCancellation.nonces(maker),
            takerNonce: orderCancellation.nonces(taker),
            expiry: expiry
        });
        
        // Create order signatures
        bytes32 orderHash = signatures.hashOrder(order);
        (uint8 makerV, bytes32 makerR, bytes32 makerS) = vm.sign(makerPrivateKey, orderHash);
        bytes memory makerSignature = abi.encodePacked(makerR, makerS, makerV);
        
        (uint8 takerV, bytes32 takerR, bytes32 takerS) = vm.sign(takerPrivateKey, orderHash);
        bytes memory takerSignature = abi.encodePacked(takerR, takerS, takerV);
        
        // Create VALID deadline but INVALID signature (wrong private key)
        uint256 deadline = block.timestamp + 30 days;
        (uint8 invalidV, bytes32 invalidR, bytes32 invalidS) = createPermitSignature(
            0x42, // Wrong private key
            address(makerToken),
            "Maker Token",
            maker,
            address(exchange),
            makerAmount,
            0, // Current nonce
            deadline
        );
        
        // Add standard approvals since permits will fail
        vm.prank(maker);
        makerToken.approve(address(exchange), makerAmount);
        
        vm.prank(taker);
        takerToken.approve(address(exchange), takerAmount);
        
        // Create permit with invalid signature
        PermitData.TokenPermit memory makerPermit = PermitData.TokenPermit({
            token: address(makerToken),
            owner: maker,
            value: makerAmount,
            deadline: deadline,
            v: invalidV,
            r: invalidR,
            s: invalidS
        });
        
        // Empty taker permit
        PermitData.TokenPermit memory takerPermit = PermitData.TokenPermit({
            token: address(0),
            owner: address(0),
            value: 0,
            deadline: 0,
            v: 0,
            r: bytes32(0),
            s: bytes32(0)
        });
        
        // Execute with invalid permit signature but valid approvals
        vm.prank(owner);
        exchange.executeSignedOrderWithPermits(
            order,
            makerSignature,
            takerSignature,
            makerPermit,
            takerPermit
        );
        
        // Verify the order executed despite invalid permit signature
        assertLt(makerToken.balanceOf(maker), INITIAL_BALANCE);
        assertGt(takerToken.balanceOf(maker), 0);
    }
}