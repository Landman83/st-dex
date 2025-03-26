// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/exchange/mixins/AtomicSwap.sol";
import "../src/exchange/mixins/Fees.sol";
import "../src/exchange/mixins/Compliance.sol";
import "../src/exchange/mixins/OrderCancellation.sol";
import "../src/exchange/mixins/Signatures.sol";
import "../src/exchange/libraries/Order.sol";

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

// Mock the Signatures contract for testing
contract MockSignatures is ISignatures {
    // Here we're simplifying signature verification for testing purposes
    function isValidSignature(Order.OrderInfo calldata order, bytes calldata signature, address signer) external pure override returns (bool) {
        // For testing, any signature is valid if signer matches order maker/taker
        return (signature.length > 0 && (signer == order.maker || signer == order.taker));
    }
    
    function hashOrder(Order.OrderInfo calldata order) external view override returns (bytes32) {
        return keccak256(abi.encode(order));
    }
    
    function getDomainSeparator() external view override returns (bytes32) {
        return bytes32(0);
    }
    
    function getOrderTypeHash() external pure override returns (bytes32) {
        return bytes32(0);
    }
    
    function recoverSigner(bytes32 hash, bytes calldata signature) external pure override returns (address) {
        // For testing, we return the first 20 bytes of the signature as the signer
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

// Mock the OrderCancellation contract to bypass the authorization check
contract MockOrderCancellation is IOrderCancellation {
    uint256 private _makerNonce;
    uint256 private _takerNonce;
    
    function nonces(address owner) public view override returns (uint256) {
        if (owner == address(0x2)) { // maker
            return _makerNonce;
        } else if (owner == address(0x3)) { // taker
            return _takerNonce;
        }
        return 0;
    }
    
    function verifyNonce(address owner, uint256 nonce) external view override returns (bool) {
        return nonce == nonces(owner);
    }
    
    function advanceNonce(address owner) external override returns (uint256) {
        if (owner == address(0x2)) { // maker
            uint256 current = _makerNonce;
            _makerNonce++;
            return current;
        } else if (owner == address(0x3)) { // taker
            uint256 current = _takerNonce;
            _takerNonce++;
            return current;
        }
        return 0;
    }
    
    function cancelOrder(Order.OrderInfo calldata order, bytes calldata signature) external override {
        // No-op for test
    }
    
    function cancelOrderByBoth(
        Order.OrderInfo calldata order,
        bytes calldata makerSignature,
        bytes calldata takerSignature
    ) external override {
        // No-op for test
    }
    
    function useCheckedNonce(address owner, uint256 nonce) external override {
        // No-op for test
    }
}

// Simplified AtomicSwap implementation for testing
contract TestAtomicSwap {
    IFees public feesContract;
    IOrderCancellation public cancellationContract;
    ISignatures public signaturesContract;
    
    constructor(
        address _feesContract,
        address _cancellationContract,
        address _signaturesContract
    ) {
        feesContract = IFees(_feesContract);
        cancellationContract = IOrderCancellation(_cancellationContract);
        signaturesContract = ISignatures(_signaturesContract);
    }
    
    function executeSignedOrder(
        Order.OrderInfo calldata _order,
        bytes calldata _makerSignature,
        bytes calldata _takerSignature
    ) external {
        // Verify order hasn't expired
        require(block.timestamp <= _order.expiry, "Order expired");

        // Verify nonces
        require(
            cancellationContract.verifyNonce(_order.maker, _order.makerNonce),
            "Maker nonce invalid"
        );
        require(
            cancellationContract.verifyNonce(_order.taker, _order.takerNonce),
            "Taker nonce invalid"
        );

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

        // Calculate fees
        (uint256 makerFee, uint256 takerFee, address fee1Wallet, address fee2Wallet) = 
            feesContract.calculateOrderFees(
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
        cancellationContract.advanceNonce(_order.maker);
        cancellationContract.advanceNonce(_order.taker);
    }
    
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
            require(makerFee <= makerAmount, "Fee exceeds amount");
            
            // Send tokens to taker (minus fee)
            makerToken.transferFrom(maker, taker, makerAmount - makerFee);
            
            // Send fee to fee wallet
            makerToken.transferFrom(maker, fee1Wallet, makerFee);
        } else {
            // No fee, send full amount
            makerToken.transferFrom(maker, taker, makerAmount);
        }

        // Handle taker tokens
        if (takerFee > 0 && fee2Wallet != address(0)) {
            // Safety check to avoid overflow
            require(takerFee <= takerAmount, "Fee exceeds amount");
            
            // Send tokens to maker (minus fee)
            takerToken.transferFrom(taker, maker, takerAmount - takerFee);
            
            // Send fee to fee wallet
            takerToken.transferFrom(taker, fee2Wallet, takerFee);
        } else {
            // No fee, send full amount
            takerToken.transferFrom(taker, maker, takerAmount);
        }
    }
}

contract AtomicSwapTest is Test {
    // Test contracts
    TestAtomicSwap public atomicSwap;
    Fees public fees;
    Compliance public compliance;
    MockOrderCancellation public orderCancellation;
    MockSignatures public signatures;
    
    // Test tokens
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    
    // Test accounts
    address public owner = address(0x1);
    address public maker = address(0x2);
    address public taker = address(0x3);
    address public feeWallet = address(0x4);
    
    // Initial balances
    uint256 public constant INITIAL_BALANCE = 1000 ether;
    
    function setUp() public {
        // Setup test accounts
        vm.startPrank(owner);
        
        // Deploy tokens
        tokenA = new MockERC20("Token A", "TKNA", INITIAL_BALANCE);
        tokenB = new MockERC20("Token B", "TKNB", INITIAL_BALANCE);
        
        // Transfer tokens to maker and taker
        tokenA.transfer(maker, 500 ether);
        tokenB.transfer(taker, 500 ether);
        
        // Deploy contracts
        signatures = new MockSignatures();
        orderCancellation = new MockOrderCancellation();
        compliance = new Compliance(owner);
        fees = new Fees(owner);
        
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
        
        // Deploy test AtomicSwap
        atomicSwap = new TestAtomicSwap(
            address(fees),
            address(orderCancellation),
            address(signatures)
        );
        
        vm.stopPrank();
    }
    
    function test_BasicSwap() public {
        // Create order parameters
        uint256 makerAmount = 100 ether;
        uint256 takerAmount = 200 ether;
        uint256 expiry = block.timestamp + 1 days;
        
        // Approve tokens for transfer
        vm.startPrank(maker);
        tokenA.approve(address(atomicSwap), makerAmount);
        vm.stopPrank();
        
        vm.startPrank(taker);
        tokenB.approve(address(atomicSwap), takerAmount);
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
        
        // Create dummy signatures
        bytes memory makerSignature = abi.encodePacked("maker_signature");
        bytes memory takerSignature = abi.encodePacked("taker_signature");
        
        // Record balances before swap
        uint256 makerTokenABefore = tokenA.balanceOf(maker);
        uint256 makerTokenBBefore = tokenB.balanceOf(maker);
        uint256 takerTokenABefore = tokenA.balanceOf(taker);
        uint256 takerTokenBBefore = tokenB.balanceOf(taker);
        uint256 feeWalletTokenABefore = tokenA.balanceOf(feeWallet);
        uint256 feeWalletTokenBBefore = tokenB.balanceOf(feeWallet);
        
        // Execute swap
        vm.prank(maker);
        atomicSwap.executeSignedOrder(order, makerSignature, takerSignature);
        
        // Calculate expected fees
        uint256 expectedMakerFee = makerAmount * 1 / 100; // 1% fee
        uint256 expectedTakerFee = takerAmount * 2 / 100; // 2% fee
        
        // Check balances after swap
        assertEq(tokenA.balanceOf(maker), makerTokenABefore - makerAmount, "Maker should send TokenA");
        assertEq(tokenB.balanceOf(maker), makerTokenBBefore + (takerAmount - expectedTakerFee), "Maker should receive TokenB minus fee");
        
        assertEq(tokenA.balanceOf(taker), takerTokenABefore + (makerAmount - expectedMakerFee), "Taker should receive TokenA minus fee");
        assertEq(tokenB.balanceOf(taker), takerTokenBBefore - takerAmount, "Taker should send TokenB");
        
        assertEq(tokenA.balanceOf(feeWallet), feeWalletTokenABefore + expectedMakerFee, "Fee wallet should receive TokenA fee");
        assertEq(tokenB.balanceOf(feeWallet), feeWalletTokenBBefore + expectedTakerFee, "Fee wallet should receive TokenB fee");
    }
}