// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/exchange/Exchange.sol";
import "../src/exchange/ExchangeProxy.sol";
import "../src/exchange/mixins/Fees.sol";
import "../src/exchange/mixins/Compliance.sol";
import "../src/exchange/mixins/OrderCancellation.sol";
import "../src/exchange/mixins/Signatures.sol";
import "../src/exchange/mixins/Registry.sol";
import "../src/exchange/libraries/Order.sol";
import "../src/exchange/libraries/ExchangeErrors.sol";
import "../src/exchange/interfaces/ISignatures.sol";

// Create a mock ERC20 token for testing
contract MockERC20 is Test {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    constructor(string memory _name, string memory _symbol, uint256 initialSupply) {
        name = _name;
        symbol = _symbol;
        _mint(msg.sender, initialSupply);
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

// Mock Signatures for testing - just return success for any signature
contract MockSignatures is ISignatures {
    function isValidSignature(
        Order.OrderInfo calldata order,
        bytes calldata signature,
        address signer
    ) external pure override returns (bool) {
        // For testing, we'll consider any non-empty signature as valid
        return signature.length > 0;
    }

    function hashOrder(Order.OrderInfo calldata order) external pure override returns (bytes32) {
        return keccak256(abi.encode(order));
    }

    function getDomainSeparator() external pure override returns (bytes32) {
        return bytes32(0);
    }

    function getOrderTypeHash() external pure override returns (bytes32) {
        return bytes32(0);
    }

    function recoverSigner(bytes32 hash, bytes calldata signature) external pure override returns (address) {
        if (signature.length >= 20) {
            bytes20 signer;
            assembly {
                signer := calldataload(signature.offset)
            }
            return address(signer);
        }
        return address(0);
    }
}

contract ExchangeTest is Test {
    // Main contracts
    Exchange public exchangeImplementation;
    ExchangeProxy public exchangeProxy;
    Exchange public exchange; // proxy-wrapped implementation

    // Component contracts
    Fees public fees;
    OrderCancellation public orderCancellation;
    Compliance public compliance;
    MockSignatures public mockSignatures;
    MockRegistry public registry;

    // Test tokens
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    
    // Test accounts
    address public owner = address(0x1);
    address public maker = address(0x2);
    address public taker = address(0x3);
    address public feeWallet = address(0x4);
    address public newOwner = address(0x5);
    
    // Initial balances
    uint256 public constant INITIAL_BALANCE = 1000 ether;
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy tokens
        tokenA = new MockERC20("Token A", "TKNA", INITIAL_BALANCE);
        tokenB = new MockERC20("Token B", "TKNB", INITIAL_BALANCE);
        
        // Transfer tokens to maker and taker
        tokenA.transfer(maker, 500 ether);
        tokenB.transfer(taker, 500 ether);
        
        // Deploy component contracts with mocked signatures
        mockSignatures = new MockSignatures();
        orderCancellation = new OrderCancellation(owner, address(mockSignatures));
        compliance = new Compliance(owner);
        fees = new Fees(owner);
        registry = new MockRegistry();
        
        // Register tokens in the registry
        registry.registerAsset(address(tokenA));
        registry.registerAsset(address(tokenB));
        
        // Configure fees for token pair
        fees.modifyFee(
            address(tokenA),
            address(tokenB),
            1, // 1% fee on tokenA
            2, // 2% fee on tokenB
            2, // fee base (10^2 = 100, so percentages)
            feeWallet,
            feeWallet
        );
        
        // Deploy Exchange implementation
        exchangeImplementation = new Exchange();
        
        // Deploy Exchange Proxy
        exchangeProxy = new ExchangeProxy(address(exchangeImplementation), owner);
        
        // Initialize the proxy
        bytes memory initializeCalldata = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address)",
            owner,                      // Owner
            address(fees),              // Fees contract
            address(orderCancellation), // Cancellation contract
            address(compliance),        // Compliance contract
            address(mockSignatures),    // Signatures contract
            address(registry)           // Registry contract
        );
        
        (bool success, ) = address(exchangeProxy).call(initializeCalldata);
        require(success, "Initialization failed");
        
        // Create the proxy-wrapped instance for ease of calling
        exchange = Exchange(payable(address(exchangeProxy)));
        
        // Set the Exchange contract address in the OrderCancellation contract
        orderCancellation.setExchangeContract(address(exchangeProxy));
        
        vm.stopPrank();
    }
    
    // Test initialization
    function test_Initialization() public {
        assertEq(exchange.owner(), owner, "Owner should be set correctly");
        assertEq(exchange.getFeesContract(), address(fees), "Fees contract should be set correctly");
        assertEq(exchange.getCancellationContract(), address(orderCancellation), "Cancellation contract should be set correctly");
        assertEq(exchange.getComplianceContract(), address(compliance), "Compliance contract should be set correctly");
        assertEq(exchange.getSignaturesContract(), address(mockSignatures), "Signatures contract should be set correctly");
        assertEq(exchange.getRegistryContract(), address(registry), "Registry contract should be set correctly");
    }
    
    // Test executeSignedOrder
    function test_ExecuteSignedOrder() public {
        // Create order parameters
        uint256 makerAmount = 100 ether;
        uint256 takerAmount = 200 ether;
        uint256 expiry = block.timestamp + 1 days;
        
        // Approve exchange to transfer tokens
        vm.startPrank(maker);
        tokenA.approve(address(exchange), makerAmount);
        vm.stopPrank();
        
        vm.startPrank(taker);
        tokenB.approve(address(exchange), takerAmount);
        vm.stopPrank();
        
        // Create order
        Order.OrderInfo memory order = Order.OrderInfo({
            maker: maker,
            makerToken: address(tokenA),
            makerAmount: makerAmount,
            taker: taker,
            takerToken: address(tokenB),
            takerAmount: takerAmount,
            makerNonce: orderCancellation.nonces(maker),
            takerNonce: orderCancellation.nonces(taker),
            expiry: expiry
        });
        
        // Simple signatures that our mock accepts
        bytes memory makerSignature = abi.encodePacked(bytes1(0x01));
        bytes memory takerSignature = abi.encodePacked(bytes1(0x02));
        
        // Execute the order
        vm.prank(taker);
        exchange.executeSignedOrder(order, makerSignature, takerSignature);
        
        // Calculate expected amounts after fees
        // 1% fee on maker token (tokenA)
        uint256 expectedTakerReceive = makerAmount * 99 / 100; // 99 ether
        // 2% fee on taker token (tokenB)
        uint256 expectedMakerReceive = takerAmount * 98 / 100; // 196 ether
        
        // Verify token transfers with fees taken into account
        assertEq(tokenA.balanceOf(taker), expectedTakerReceive, "Taker should receive maker tokens minus fees");
        assertEq(tokenB.balanceOf(maker), expectedMakerReceive, "Maker should receive taker tokens minus fees");
        
        // Verify fee transfers
        assertEq(tokenA.balanceOf(feeWallet), makerAmount * 1 / 100, "Fee wallet should receive maker token fees");
        assertEq(tokenB.balanceOf(feeWallet), takerAmount * 2 / 100, "Fee wallet should receive taker token fees");
        
        // Verify nonces are advanced
        assertEq(orderCancellation.nonces(maker), 1, "Maker nonce should be advanced");
        assertEq(orderCancellation.nonces(taker), 1, "Taker nonce should be advanced");
    }
    
    // Test cancelOrder
    function test_CancelOrder() public {
        // Create order parameters
        uint256 makerAmount = 100 ether;
        uint256 takerAmount = 200 ether;
        uint256 expiry = block.timestamp + 1 days;
        
        // Create order
        Order.OrderInfo memory order = Order.OrderInfo({
            maker: maker,
            makerToken: address(tokenA),
            makerAmount: makerAmount,
            taker: taker,
            takerToken: address(tokenB),
            takerAmount: takerAmount,
            makerNonce: orderCancellation.nonces(maker),
            takerNonce: orderCancellation.nonces(taker),
            expiry: expiry
        });
        
        // Simple signature that our mock accepts
        bytes memory makerSignature = abi.encodePacked(bytes1(0x01));
        
        // Cancel the order as the maker
        vm.prank(maker);
        exchange.cancelOrder(order, makerSignature);
        
        // Verify maker nonce is advanced
        assertEq(orderCancellation.nonces(maker), 1, "Maker nonce should be advanced");
    }
    
    // Test cancelOrderByBoth
    function test_CancelOrderByBoth() public {
        // Create order parameters
        uint256 makerAmount = 100 ether;
        uint256 takerAmount = 200 ether;
        uint256 expiry = block.timestamp + 1 days;
        
        // Create order
        Order.OrderInfo memory order = Order.OrderInfo({
            maker: maker,
            makerToken: address(tokenA),
            makerAmount: makerAmount,
            taker: taker,
            takerToken: address(tokenB),
            takerAmount: takerAmount,
            makerNonce: orderCancellation.nonces(maker),
            takerNonce: orderCancellation.nonces(taker),
            expiry: expiry
        });
        
        // Simple signatures that our mock accepts
        bytes memory makerSignature = abi.encodePacked(bytes1(0x01));
        bytes memory takerSignature = abi.encodePacked(bytes1(0x02));
        
        // Cancel the order as the maker
        vm.prank(maker);
        exchange.cancelOrderByBoth(order, makerSignature, takerSignature);
        
        // Verify both nonces are advanced
        assertEq(orderCancellation.nonces(maker), 1, "Maker nonce should be advanced");
        assertEq(orderCancellation.nonces(taker), 1, "Taker nonce should be advanced");
    }
    
    // Test setFeesContract
    function test_SetFeesContract() public {
        // Deploy a new Fees contract
        vm.startPrank(owner);
        Fees newFees = new Fees(owner);
        
        // Update the fees contract
        exchange.setFeesContract(address(newFees));
        vm.stopPrank();
        
        // Verify the new fees contract is set
        assertEq(exchange.getFeesContract(), address(newFees), "Fees contract should be updated");
    }
    
    // Test unauthorized setFeesContract
    function test_UnauthorizedSetFeesContract() public {
        Fees newFees = new Fees(owner);
        
        // Try to call from unauthorized account
        vm.prank(taker);
        vm.expectRevert(bytes(ExchangeErrors.ONLY_OWNER));
        exchange.setFeesContract(address(newFees));
    }
    
    // Test setCancellationContract
    function test_SetCancellationContract() public {
        // Deploy a new OrderCancellation contract
        vm.startPrank(owner);
        OrderCancellation newCancellation = new OrderCancellation(owner, address(mockSignatures));
        
        // Update the cancellation contract
        exchange.setCancellationContract(address(newCancellation));
        vm.stopPrank();
        
        // Verify the new cancellation contract is set
        assertEq(exchange.getCancellationContract(), address(newCancellation), "Cancellation contract should be updated");
    }
    
    // Test setComplianceContract
    function test_SetComplianceContract() public {
        // Deploy a new Compliance contract
        vm.startPrank(owner);
        Compliance newCompliance = new Compliance(owner);
        
        // Update the compliance contract
        exchange.setComplianceContract(address(newCompliance));
        vm.stopPrank();
        
        // Verify the new compliance contract is set
        assertEq(exchange.getComplianceContract(), address(newCompliance), "Compliance contract should be updated");
    }
    
    // Test setSignaturesContract
    function test_SetSignaturesContract() public {
        // Deploy a new Signatures contract
        vm.startPrank(owner);
        MockSignatures newSignatures = new MockSignatures();
        
        // Update the signatures contract
        exchange.setSignaturesContract(address(newSignatures));
        vm.stopPrank();
        
        // Verify the new signatures contract is set
        assertEq(exchange.getSignaturesContract(), address(newSignatures), "Signatures contract should be updated");
    }
    
    // Test setRegistryContract
    function test_SetRegistryContract() public {
        // Deploy a new Registry
        vm.startPrank(owner);
        MockRegistry newRegistry = new MockRegistry();
        
        // Update the registry contract
        exchange.setRegistryContract(address(newRegistry));
        vm.stopPrank();
        
        // Verify the new registry contract is set
        assertEq(exchange.getRegistryContract(), address(newRegistry), "Registry contract should be updated");
    }
    
    // Test transferOwnership
    function test_TransferOwnership() public {
        // Transfer ownership
        vm.prank(owner);
        exchange.transferOwnership(newOwner);
        
        // Verify the new owner
        assertEq(exchange.owner(), newOwner, "Ownership should be transferred");
    }
    
    // Test receive function
    function test_ReceiveEther() public {
        // Send ETH to the exchange
        uint256 amount = 1 ether;
        vm.deal(owner, amount);
        
        // Send ETH
        vm.prank(owner);
        (bool success, ) = address(exchange).call{value: amount}("");
        assertTrue(success, "Should accept ETH");
        
        // Verify contract balance
        assertEq(address(exchange).balance, amount, "Contract should have received ETH");
    }
    
    // Test proxy upgrade
    function test_ProxyUpgrade() public {
        // Deploy a new implementation
        Exchange newImplementation = new Exchange();
        
        // Upgrade the proxy
        vm.prank(owner);
        exchangeProxy.upgradeTo(address(newImplementation));
        
        // Verify the implementation is updated
        assertEq(exchangeProxy.implementation(), address(newImplementation), "Implementation should be updated");
    }
    
    // Test proxy admin change
    function test_ProxyAdminChange() public {
        // Change the admin
        vm.prank(owner);
        exchangeProxy.changeAdmin(newOwner);
        
        // Verify the admin is updated
        assertEq(exchangeProxy.admin(), newOwner, "Admin should be updated");
    }
    
    // Test unauthorized proxy upgrade
    function test_UnauthorizedProxyUpgrade() public {
        // Deploy a new implementation
        Exchange newImplementation = new Exchange();
        
        // Try to upgrade from unauthorized account
        vm.prank(taker);
        vm.expectRevert(bytes(ExchangeErrors.ONLY_ADMIN));
        exchangeProxy.upgradeTo(address(newImplementation));
    }
    
    // Test double initialization prevention
    function test_PreventDoubleInitialization() public {
        // Try to initialize again
        bytes memory initializeCalldata = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address)",
            owner,
            address(fees),
            address(orderCancellation),
            address(compliance),
            address(mockSignatures),
            address(registry)
        );
        
        // Just use expectRevert without checking the success flag
        vm.expectRevert(bytes(ExchangeErrors.ALREADY_INITIALIZED));
        (bool success, ) = address(exchangeProxy).call(initializeCalldata);
        
        // No need for assertFalse here since expectRevert already checks for the revert
    }
}
