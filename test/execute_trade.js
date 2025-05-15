// Script to execute a signed trade using the Exchange contract with enhanced debugging
// Includes detailed diagnostics for meta-transaction validation and error analysis
const fs = require('fs');
const ethers = require('ethers');
require('dotenv').config();

// Load Exchange ABI from Foundry's output directory
const exchangeABI = require('../out/Exchange.sol/Exchange.json').abi;

// Extended ERC20 ABI with permit support
const erc20ABI = [
  "function balanceOf(address owner) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function name() view returns (string)",
  "function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external"
];

// Helper to format ethers errors and extract revert reasons
function formatError(error) {
  let result = {
    message: error.message || "Unknown error",
    reason: null,
    code: error.code,
    data: error.data
  };

  // Try to extract revert reason
  if (error.data) {
    try {
      // Common error format starts with '0x08c379a0'
      if (error.data.startsWith('0x08c379a0')) {
        // Skip function selector (0x08c379a0) and position params
        const abiCoder = new ethers.utils.AbiCoder();
        const reason = abiCoder.decode(['string'], '0x' + error.data.substring(10));
        result.reason = reason[0];
      }
    } catch (e) {
      console.warn('Could not decode error data:', e.message);
    }
  }

  // Try to extract reason from error message
  if (!result.reason) {
    const revertMatch = error.message.match(/reverted with reason string '([^']+)'/);
    if (revertMatch) {
      result.reason = revertMatch[1];
    }
  }

  return result;
}

async function executeMetaTransactionTrade() {
  try {
    console.log("🔍 ENHANCED TRADE EXECUTION WITH META-TRANSACTION SUPPORT\n");
    
    // Load the signed trade from JSON
    const filePath = process.env.TRADE_FILE || './test/signed_trade.json';
    console.log(`Loading trade data from: ${filePath}`);
    const tradeData = JSON.parse(fs.readFileSync(filePath, 'utf8'));

    // Setup provider and network
    const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
    const network = await provider.getNetwork();
    const chainId = network.chainId;

    console.log(`\n🌐 NETWORK INFORMATION:`);
    console.log(`Connected to network: ${network.name} (Chain ID: ${chainId})`);
    
    // Check if the network matches the signed trade's chain ID
    if (tradeData.domain && tradeData.domain.chainId && tradeData.domain.chainId !== chainId) {
      console.error(`⚠️ CHAIN ID MISMATCH: Trade is signed for chain ${tradeData.domain.chainId}, but connected to ${chainId}`);
      console.error("This will likely cause signature validation failures!");
    }

    // Setup deployer wallet
    const deployerWallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    console.log(`\n👤 ACCOUNT INFORMATION:`);
    console.log(`Deployer: ${deployerWallet.address}`);
    console.log(`Seller (Maker): ${tradeData.order.maker}`);
    console.log(`Buyer (Taker): ${tradeData.order.taker}`);

    // Verify that deployer has enough ETH for gas
    const deployerEthBalance = await provider.getBalance(deployerWallet.address);
    console.log(`Deployer ETH balance: ${ethers.utils.formatEther(deployerEthBalance)} ETH`);

    if (deployerEthBalance.lt(ethers.utils.parseEther("0.01"))) {
      console.warn("⚠️ WARNING: Deployer has less than 0.01 ETH for gas. Transactions might fail.");
    }

    // Connect to the Exchange contract
    const exchangeAddress = process.env.EXCHANGE_ADDRESS || 
                          (tradeData.domain && tradeData.domain.verifyingContract) || 
                          '0x4C05d6D5b72ec37BEA51b47a8b8c79a5499F5023';
                          
    const exchange = new ethers.Contract(exchangeAddress, exchangeABI, deployerWallet);
    console.log(`\n📄 CONTRACT INFORMATION:`);
    console.log(`Exchange contract: ${exchangeAddress}`);
    
    // Get core contract references for diagnostics
    try {
      const [
        ownerAddress,
        feesContract,
        cancellationContract,
        complianceContract,
        signaturesContract,
        registryContract
      ] = await Promise.all([
        exchange.owner().catch(() => "Error fetching"),
        exchange.getFeesContract().catch(() => "Error fetching"),
        exchange.getCancellationContract().catch(() => "Error fetching"),
        exchange.getComplianceContract().catch(() => "Error fetching"),
        exchange.getSignaturesContract().catch(() => "Error fetching"),
        exchange.getRegistryContract().catch(() => "Error fetching")
      ]);
      
      console.log(`Exchange Owner: ${ownerAddress}`);
      console.log(`Fees Contract: ${feesContract}`);
      console.log(`Cancellation Contract: ${cancellationContract}`);
      console.log(`Compliance Contract: ${complianceContract}`);
      console.log(`Signatures Contract: ${signaturesContract}`);
      console.log(`Registry Contract: ${registryContract}`);
    } catch (error) {
      console.error("Error fetching contract references:", error.message);
    }

    // Connect to token contracts
    const makerToken = new ethers.Contract(tradeData.order.makerToken, erc20ABI, provider);
    const takerToken = new ethers.Contract(tradeData.order.takerToken, erc20ABI, provider);

    // Get token information
    let makerTokenSymbol = "Unknown";
    let takerTokenSymbol = "Unknown";
    let makerTokenDecimals = 18;
    let takerTokenDecimals = 18;
    
    try {
      makerTokenSymbol = await makerToken.symbol();
      makerTokenDecimals = await makerToken.decimals();
    } catch (error) {
      console.warn(`⚠️ Could not fetch maker token details: ${error.message}`);
    }
    
    try {
      takerTokenSymbol = await takerToken.symbol();
      takerTokenDecimals = await takerToken.decimals();
    } catch (error) {
      console.warn(`⚠️ Could not fetch taker token details: ${error.message}`);
    }

    console.log(`\n💰 TOKEN INFORMATION:`);
    console.log(`Maker Token: ${tradeData.order.makerToken} (${makerTokenSymbol}, ${makerTokenDecimals} decimals)`);
    console.log(`Taker Token: ${tradeData.order.takerToken} (${takerTokenSymbol}, ${takerTokenDecimals} decimals)`);
    console.log(`Maker Amount: ${ethers.utils.formatUnits(tradeData.order.makerAmount, makerTokenDecimals)} ${makerTokenSymbol}`);
    console.log(`Taker Amount: ${ethers.utils.formatUnits(tradeData.order.takerAmount, takerTokenDecimals)} ${takerTokenSymbol}`);

    // Check token balances
    const makerBalance = await makerToken.balanceOf(tradeData.order.maker);
    const takerBalance = await takerToken.balanceOf(tradeData.order.taker);

    console.log(`\n💼 BALANCES:`);
    console.log(`Maker's token balance: ${ethers.utils.formatUnits(makerBalance, makerTokenDecimals)} ${makerTokenSymbol}`);
    console.log(`Taker's token balance: ${ethers.utils.formatUnits(takerBalance, takerTokenDecimals)} ${takerTokenSymbol}`);

    // Check if balances are sufficient
    const makerHasSufficientBalance = makerBalance.gte(tradeData.order.makerAmount);
    const takerHasSufficientBalance = takerBalance.gte(tradeData.order.takerAmount);
    
    console.log(`Maker has sufficient balance: ${makerHasSufficientBalance ? "✅ YES" : "❌ NO"}`);
    console.log(`Taker has sufficient balance: ${takerHasSufficientBalance ? "✅ YES" : "❌ NO"}`);
    
    if (!makerHasSufficientBalance || !takerHasSufficientBalance) {
      console.error("⚠️ WARNING: Insufficient balances will cause the transaction to fail!");
    }

    // Check token allowances
    const makerAllowance = await makerToken.allowance(tradeData.order.maker, exchangeAddress);
    const takerAllowance = await takerToken.allowance(tradeData.order.taker, exchangeAddress);

    console.log(`\n🔓 ALLOWANCES:`);
    console.log(`Maker's allowance to Exchange: ${ethers.utils.formatUnits(makerAllowance, makerTokenDecimals)} ${makerTokenSymbol}`);
    console.log(`Taker's allowance to Exchange: ${ethers.utils.formatUnits(takerAllowance, takerTokenDecimals)} ${takerTokenSymbol}`);

    // Check if allowances are sufficient
    const makerHasSufficientAllowance = makerAllowance.gte(tradeData.order.makerAmount);
    const takerHasSufficientAllowance = takerAllowance.gte(tradeData.order.takerAmount);
    
    console.log(`Maker has sufficient allowance: ${makerHasSufficientAllowance ? "✅ YES" : "❌ NO"}`);
    console.log(`Taker has sufficient allowance: ${takerHasSufficientAllowance ? "✅ YES" : "❌ NO"}`);
    
    // Check if we're using permit
    const usingMakerPermit = !!(tradeData.makerPermit && tradeData.makerPermit.owner);
    const usingTakerPermit = !!(tradeData.takerPermit && tradeData.takerPermit.owner);
    
    console.log(`\n🔑 PERMIT DATA:`);
    console.log(`Using maker permit: ${usingMakerPermit ? "✅ YES" : "❌ NO"}`);
    console.log(`Using taker permit: ${usingTakerPermit ? "✅ YES" : "❌ NO"}`);
    
    if ((usingMakerPermit && !makerHasSufficientAllowance) || 
        (usingTakerPermit && !takerHasSufficientAllowance)) {
      console.log("ℹ️ Low allowances will be handled by permit data in the transaction");
    } else if (!makerHasSufficientAllowance || !takerHasSufficientAllowance) {
      console.error("⚠️ WARNING: Insufficient allowances and not using permit - transaction will fail!");
    }
    
    // Check order expiry
    const currentTimestamp = Math.floor(Date.now() / 1000);
    const orderExpiry = parseInt(tradeData.order.expiry);
    const timeUntilExpiry = orderExpiry - currentTimestamp;
    
    console.log(`\n⏰ ORDER TIMING:`);
    console.log(`Current timestamp: ${currentTimestamp} (${new Date(currentTimestamp * 1000).toLocaleString()})`);
    console.log(`Order expiry: ${orderExpiry} (${new Date(orderExpiry * 1000).toLocaleString()})`);
    console.log(`Time until expiry: ${timeUntilExpiry} seconds (${Math.floor(timeUntilExpiry / 3600)} hours)`);
    
    if (timeUntilExpiry <= 0) {
      console.error("❌ CRITICAL ERROR: Order has expired! Transaction will fail.");
    } else if (timeUntilExpiry < 3600) {
      console.warn("⚠️ WARNING: Order expires in less than 1 hour!");
    }
    
    // Check KYC and accreditation if possible
    try {
      const [makerKYC, takerKYC] = await Promise.all([
        exchange.isKYCVerified(tradeData.order.makerToken, tradeData.order.maker).catch(() => null),
        exchange.isKYCVerified(tradeData.order.takerToken, tradeData.order.taker).catch(() => null)
      ]);
      
      if (makerKYC !== null && takerKYC !== null) {
        console.log(`\n🏛️ COMPLIANCE CHECK:`);
        console.log(`Maker is KYC verified: ${makerKYC ? "✅ YES" : "❌ NO"}`);
        console.log(`Taker is KYC verified: ${takerKYC ? "✅ YES" : "❌ NO"}`);
        
        if (!makerKYC || !takerKYC) {
          console.warn("⚠️ WARNING: Missing KYC verification may cause compliance issues!");
        }
      }
    } catch (error) {
      // Silently ignore - compliance checks are optional diagnostics
    }
    
    // Check if tokens are registered (if the function exists)
    try {
      if (exchange.getRegistryContract) {
        const registryContract = await exchange.getRegistryContract();
        const registry = new ethers.Contract(
          registryContract,
          ["function isRegisteredAsset(address asset) external view returns (bool)"],
          provider
        );
        
        const [makerTokenRegistered, takerTokenRegistered] = await Promise.all([
          registry.isRegisteredAsset(tradeData.order.makerToken).catch(() => null),
          registry.isRegisteredAsset(tradeData.order.takerToken).catch(() => null)
        ]);
        
        if (makerTokenRegistered !== null && takerTokenRegistered !== null) {
          console.log(`\n📝 TOKEN REGISTRATION:`);
          console.log(`Maker token is registered: ${makerTokenRegistered ? "✅ YES" : "❌ NO"}`);
          console.log(`Taker token is registered: ${takerTokenRegistered ? "✅ YES" : "❌ NO"}`);
          
          if (!makerTokenRegistered || !takerTokenRegistered) {
            console.error("❌ CRITICAL ERROR: Unregistered tokens will cause the transaction to fail!");
          }
        }
      }
    } catch (error) {
      // Silently ignore - registry checks are optional diagnostics
    }
    
    // Perform transaction simulation first
    console.log("\n🧪 SIMULATING TRANSACTION...");
    
    // Prepare the transaction parameters
    const order = {
      maker: tradeData.order.maker,
      makerToken: tradeData.order.makerToken,
      makerAmount: tradeData.order.makerAmount,
      taker: tradeData.order.taker,
      takerToken: tradeData.order.takerToken,
      takerAmount: tradeData.order.takerAmount,
      makerNonce: tradeData.order.makerNonce || 0,
      takerNonce: tradeData.order.takerNonce || 0,
      expiry: tradeData.order.expiry
    };
    
    const makerSignature = tradeData.signatures?.maker || tradeData.makerSignature || "0x";
    const takerSignature = tradeData.signatures?.taker || tradeData.takerSignature || "0x";
    
    // Prepare permit data if available
    const makerPermit = tradeData.makerPermit ? {
      token: tradeData.makerPermit.token || tradeData.order.makerToken,
      owner: tradeData.makerPermit.owner || tradeData.order.maker,
      value: tradeData.makerPermit.value || tradeData.order.makerAmount,
      deadline: tradeData.makerPermit.deadline || tradeData.order.expiry,
      v: tradeData.makerPermit.v || 0,
      r: tradeData.makerPermit.r || ethers.constants.HashZero,
      s: tradeData.makerPermit.s || ethers.constants.HashZero
    } : {
      token: ethers.constants.AddressZero,
      owner: ethers.constants.AddressZero,
      value: 0,
      deadline: 0,
      v: 0,
      r: ethers.constants.HashZero,
      s: ethers.constants.HashZero
    };
    
    const takerPermit = tradeData.takerPermit ? {
      token: tradeData.takerPermit.token || tradeData.order.takerToken,
      owner: tradeData.takerPermit.owner || tradeData.order.taker,
      value: tradeData.takerPermit.value || tradeData.order.takerAmount,
      deadline: tradeData.takerPermit.deadline || tradeData.order.expiry,
      v: tradeData.takerPermit.v || 0,
      r: tradeData.takerPermit.r || ethers.constants.HashZero,
      s: tradeData.takerPermit.s || ethers.constants.HashZero
    } : {
      token: ethers.constants.AddressZero,
      owner: ethers.constants.AddressZero,
      value: 0,
      deadline: 0,
      v: 0,
      r: ethers.constants.HashZero,
      s: ethers.constants.HashZero
    };
    
    // Check which method to call based on whether permits are used
    const usePermitMethod = usingMakerPermit || usingTakerPermit || process.env.FORCE_PERMIT === "true";
    
    try {
      if (usePermitMethod) {
        // Simulate the transaction using executeSignedOrderWithPermits
        const simulationTx = await exchange.callStatic.executeSignedOrderWithPermits(
          order,
          makerSignature,
          takerSignature,
          makerPermit,
          takerPermit,
          { gasLimit: 2000000 }
        );
        
        console.log("✅ Simulation succeeded with executeSignedOrderWithPermits!");
      } else {
        // Simulate the transaction using executeSignedOrder
        const simulationTx = await exchange.callStatic.executeSignedOrder(
          order,
          makerSignature,
          takerSignature,
          { gasLimit: 2000000 }
        );
        
        console.log("✅ Simulation succeeded with executeSignedOrder!");
      }
    } catch (error) {
      console.error("❌ Simulation failed!");
      
      const errorDetails = formatError(error);
      if (errorDetails.reason) {
        console.error(`Revert reason: ${errorDetails.reason}`);
      } else {
        console.error(`Error: ${errorDetails.message}`);
      }
      
      console.log("\n🔍 ERROR ANALYSIS:");
      
      // Analyze potential error causes
      if (timeUntilExpiry <= 0) {
        console.error("- Order has expired. The expiry timestamp is in the past.");
      }
      
      if (!makerHasSufficientBalance) {
        console.error("- Maker has insufficient token balance.");
      }
      
      if (!takerHasSufficientBalance) {
        console.error("- Taker has insufficient token balance.");
      }
      
      if (!makerHasSufficientAllowance && !usingMakerPermit) {
        console.error("- Maker has insufficient allowance and no permit is provided.");
      }
      
      if (!takerHasSufficientAllowance && !usingTakerPermit) {
        console.error("- Taker has insufficient allowance and no permit is provided.");
      }
      
      const errorMsg = error.message.toLowerCase();
      if (errorMsg.includes("signature") || errorMsg.includes("signer")) {
        console.error("- There may be issues with the signatures. Check if they were generated correctly.");
        console.error("  • Ensure the signatures were created on the correct chain ID");
        console.error("  • Verify the order parameters match what was signed");
        console.error("  • Check that the signature format (v, r, s components) is correct");
      }
      
      if (errorMsg.includes("nonce")) {
        console.error("- Nonce issues detected. The nonces may have already been used or are invalid.");
      }
      
      if (errorMsg.includes("gas")) {
        console.error("- Gas estimation failed. The transaction may be reverting for other reasons.");
      }
      
      console.log("\nAborting execution due to simulation failure. Fix the issues before retrying.");
      return;
    }
    
    // Execute the transaction
    console.log("\n🚀 EXECUTING TRANSACTION...");
    console.log(`Using method: ${usePermitMethod ? 'executeSignedOrderWithPermits' : 'executeSignedOrder'}`);
    
    let tx;
    const gasOptions = {
      gasLimit: 2000000,
      maxFeePerGas: ethers.utils.parseUnits("50", "gwei"),
      maxPriorityFeePerGas: ethers.utils.parseUnits("2", "gwei")
    };
    
    if (usePermitMethod) {
      tx = await exchange.executeSignedOrderWithPermits(
        order,
        makerSignature,
        takerSignature,
        makerPermit,
        takerPermit,
        gasOptions
      );
    } else {
      tx = await exchange.executeSignedOrder(
        order,
        makerSignature,
        takerSignature,
        gasOptions
      );
    }
    
    console.log(`Transaction submitted: ${tx.hash}`);
    console.log(`View on Explorer: ${network.name === 'matic' ? `https://polygonscan.com/tx/${tx.hash}` : 
                (network.name === 'maticmum' ? `https://mumbai.polygonscan.com/tx/${tx.hash}` : 
                `https://etherscan.io/tx/${tx.hash}`)}`);
    
    console.log("Waiting for confirmation...");
    const receipt = await tx.wait();
    
    if (receipt.status === 1) {
      console.log(`\n✅ TRANSACTION SUCCESSFUL! Block: ${receipt.blockNumber}, Gas used: ${receipt.gasUsed.toString()}`);
      
      // Check final token balances
      const finalMakerBalance = await makerToken.balanceOf(tradeData.order.maker);
      const finalTakerBalance = await takerToken.balanceOf(tradeData.order.taker);
      const finalMakerTakerTokenBalance = await takerToken.balanceOf(tradeData.order.maker);
      const finalTakerMakerTokenBalance = await makerToken.balanceOf(tradeData.order.taker);
      
      console.log(`\n💼 FINAL BALANCES:`);
      console.log(`Maker's ${makerTokenSymbol}: ${ethers.utils.formatUnits(finalMakerBalance, makerTokenDecimals)} (${ethers.utils.formatUnits(makerBalance.sub(finalMakerBalance), makerTokenDecimals)} transferred)`);
      console.log(`Taker's ${takerTokenSymbol}: ${ethers.utils.formatUnits(finalTakerBalance, takerTokenDecimals)} (${ethers.utils.formatUnits(takerBalance.sub(finalTakerBalance), takerTokenDecimals)} transferred)`);
      console.log(`Maker's ${takerTokenSymbol}: ${ethers.utils.formatUnits(finalMakerTakerTokenBalance, takerTokenDecimals)} (${ethers.utils.formatUnits(finalMakerTakerTokenBalance.sub(await takerToken.balanceOf(tradeData.order.maker)), takerTokenDecimals)} received)`);
      console.log(`Taker's ${makerTokenSymbol}: ${ethers.utils.formatUnits(finalTakerMakerTokenBalance, makerTokenDecimals)} (${ethers.utils.formatUnits(finalTakerMakerTokenBalance.sub(await makerToken.balanceOf(tradeData.order.taker)), makerTokenDecimals)} received)`);
    } else {
      console.error("❌ TRANSACTION FAILED!");
    }
    
  } catch (error) {
    console.error("Error executing meta-transaction trade:", error);
    
    const errorDetails = formatError(error);
    if (errorDetails.reason) {
      console.error(`Revert reason: ${errorDetails.reason}`);
    }
    
    if (error.transaction) {
      console.log(`\nTransaction hash: ${error.transaction.hash}`);
      console.log(`Explorer link: ${network.name === 'matic' ? `https://polygonscan.com/tx/${error.transaction.hash}` : 
                  (network.name === 'maticmum' ? `https://mumbai.polygonscan.com/tx/${error.transaction.hash}` : 
                  `https://etherscan.io/tx/${error.transaction.hash}`)}`);
    }
  }
}

// Create an additional function for the legacy method of executing a trade without permits
async function executeTrade() {
  console.log("⚠️ WARNING: Using legacy executeTrade without meta-transaction support");
  console.log("For full debugging with permit support, use executeMetaTransactionTrade instead");
  
  // Call the enhanced version with a flag to force the standard method
  process.env.FORCE_PERMIT = "false";
  await executeMetaTransactionTrade();
}

// Default to meta-transaction version
const method = process.env.USE_LEGACY === "true" ? executeTrade : executeMetaTransactionTrade;

// Run the script
method().catch((error) => {
  console.error("Uncaught error:", error);
  process.exit(1);
});