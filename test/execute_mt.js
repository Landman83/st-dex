// Script to execute a meta-transaction signed trade using the Exchange contract
// Enhanced with detailed diagnostics for troubleshooting
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
  "function nonces(address owner) view returns (uint256)",
  "function DOMAIN_SEPARATOR() view returns (bytes32)",
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

async function executeMetaTransaction() {
  try {
    console.log("🔍 META-TRANSACTION EXECUTION WITH ENHANCED DEBUGGING\n");
    
    // Load the signed trade from JSON
    const filePath = process.env.TRADE_FILE || './test/signed_meta_trade.json';
    console.log(`Loading trade data from: ${filePath}`);
    let tradeData;
    
    try {
      tradeData = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    } catch (error) {
      console.error(`❌ ERROR: Could not load trade data from ${filePath}`);
      console.error("Make sure the file exists and contains valid JSON");
      console.error("You can specify a different file with the TRADE_FILE environment variable");
      process.exit(1);
    }

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
                          tradeData.exchangeAddress;
                          
    console.log(`\n📄 CONTRACT INFORMATION:`);
    console.log(`Exchange contract: ${exchangeAddress}`);
    
    const exchange = new ethers.Contract(exchangeAddress, exchangeABI, deployerWallet);
    
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
    const initialBuyerMakerTokenBalance = await makerToken.balanceOf(tradeData.order.taker);
    const initialSellerTakerTokenBalance = await takerToken.balanceOf(tradeData.order.maker);

    console.log(`\n💼 BALANCES:`);
    console.log(`Maker's token balance: ${ethers.utils.formatUnits(makerBalance, makerTokenDecimals)} ${makerTokenSymbol}`);
    console.log(`Taker's token balance: ${ethers.utils.formatUnits(takerBalance, takerTokenDecimals)} ${takerTokenSymbol}`);
    console.log(`Buyer's ${makerTokenSymbol} balance: ${ethers.utils.formatUnits(initialBuyerMakerTokenBalance, makerTokenDecimals)}`);
    console.log(`Seller's ${takerTokenSymbol} balance: ${ethers.utils.formatUnits(initialSellerTakerTokenBalance, takerTokenDecimals)}`);

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
    
    // Check for permit data
    const hasMakerPermit = !!(tradeData.permits && tradeData.permits.maker);
    const hasTakerPermit = !!(tradeData.permits && tradeData.permits.taker);
    
    console.log(`\n🔑 PERMIT DATA:`);
    console.log(`Using maker permit: ${hasMakerPermit ? "✅ YES" : "❌ NO"}`);
    console.log(`Using taker permit: ${hasTakerPermit ? "✅ YES" : "❌ NO"}`);
    
    if ((hasMakerPermit && !makerHasSufficientAllowance) || 
        (hasTakerPermit && !takerHasSufficientAllowance)) {
      console.log("ℹ️ Low allowances will be handled by permit data in the transaction");
    } else if (!makerHasSufficientAllowance || !takerHasSufficientAllowance) {
      console.error("⚠️ WARNING: Insufficient allowances and no permit data - transaction will fail!");
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
        if (registryContract !== "Error fetching" && registryContract !== ethers.constants.AddressZero) {
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
      }
    } catch (error) {
      console.warn(`Registry check error: ${error.message}`);
    }
    
    // Prepare permits for the meta-transaction
    let makerPermit, takerPermit;
    
    if (hasMakerPermit) {
      makerPermit = {
        token: tradeData.permits.maker.token || tradeData.order.makerToken,
        owner: tradeData.permits.maker.owner || tradeData.order.maker,
        value: tradeData.permits.maker.value || tradeData.order.makerAmount,
        deadline: tradeData.permits.maker.deadline || tradeData.order.expiry,
        v: tradeData.permits.maker.v,
        r: tradeData.permits.maker.r,
        s: tradeData.permits.maker.s
      };
      
      console.log("\n📄 MAKER PERMIT DETAILS:");
      console.log(`Token: ${makerPermit.token}`);
      console.log(`Owner: ${makerPermit.owner}`);
      console.log(`Value: ${ethers.utils.formatUnits(makerPermit.value, makerTokenDecimals)}`);
      console.log(`Deadline: ${makerPermit.deadline} (${new Date(makerPermit.deadline * 1000).toLocaleString()})`);
      console.log(`v: ${makerPermit.v}`);
      console.log(`r: ${makerPermit.r}`);
      console.log(`s: ${makerPermit.s}`);
      
      // Check permit deadline
      const permitTimeUntilExpiry = makerPermit.deadline - currentTimestamp;
      if (permitTimeUntilExpiry <= 0) {
        console.error("❌ CRITICAL ERROR: Maker permit has expired! Transaction will fail.");
      }
    } else {
      makerPermit = {
        token: ethers.constants.AddressZero,
        owner: ethers.constants.AddressZero,
        value: 0,
        deadline: 0,
        v: 0,
        r: ethers.constants.HashZero,
        s: ethers.constants.HashZero
      };
    }
    
    if (hasTakerPermit) {
      takerPermit = {
        token: tradeData.permits.taker.token || tradeData.order.takerToken,
        owner: tradeData.permits.taker.owner || tradeData.order.taker,
        value: tradeData.permits.taker.value || tradeData.order.takerAmount,
        deadline: tradeData.permits.taker.deadline || tradeData.order.expiry,
        v: tradeData.permits.taker.v,
        r: tradeData.permits.taker.r,
        s: tradeData.permits.taker.s
      };
      
      console.log("\n📄 TAKER PERMIT DETAILS:");
      console.log(`Token: ${takerPermit.token}`);
      console.log(`Owner: ${takerPermit.owner}`);
      console.log(`Value: ${ethers.utils.formatUnits(takerPermit.value, takerTokenDecimals)}`);
      console.log(`Deadline: ${takerPermit.deadline} (${new Date(takerPermit.deadline * 1000).toLocaleString()})`);
      console.log(`v: ${takerPermit.v}`);
      console.log(`r: ${takerPermit.r}`);
      console.log(`s: ${takerPermit.s}`);
      
      // Check permit deadline
      const permitTimeUntilExpiry = takerPermit.deadline - currentTimestamp;
      if (permitTimeUntilExpiry <= 0) {
        console.error("❌ CRITICAL ERROR: Taker permit has expired! Transaction will fail.");
      }
    } else {
      takerPermit = {
        token: ethers.constants.AddressZero,
        owner: ethers.constants.AddressZero,
        value: 0,
        deadline: 0,
        v: 0,
        r: ethers.constants.HashZero,
        s: ethers.constants.HashZero
      };
    }
    
    // Perform transaction simulation
    console.log("\n🧪 SIMULATING TRANSACTION...");
    
    try {
      // Encode the function call manually for better error handling
      const exchangeInterface = new ethers.utils.Interface(exchangeABI);
      const callData = exchangeInterface.encodeFunctionData('executeSignedOrderWithPermits', [
        tradeData.order,
        tradeData.signatures.maker,
        tradeData.signatures.taker,
        makerPermit,
        takerPermit
      ]);
      
      // Try a static call first to see if it would succeed
      await provider.call({
        to: exchangeAddress,
        from: deployerWallet.address,
        data: callData,
        gasLimit: 2000000
      });
      
      console.log("✅ Simulation successful! Proceeding with transaction...");
    } catch (error) {
      console.error("❌ Simulation failed!");
      
      // Try to extract a revert reason
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
      
      if (!makerHasSufficientAllowance && !hasMakerPermit) {
        console.error("- Maker has insufficient allowance and no permit is provided.");
      }
      
      if (!takerHasSufficientAllowance && !hasTakerPermit) {
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
      
      // Ask to confirm if user wants to proceed despite simulation failure
      if (process.env.FORCE_EXECUTION !== "true") {
        console.log("\nSimulation failed. To execute anyway, set FORCE_EXECUTION=true. Aborting now.");
        return;
      } else {
        console.warn("\n⚠️ FORCE_EXECUTION=true is set. Proceeding despite simulation failure!");
      }
    }
    
    // Execute the transaction
    console.log("\n🚀 EXECUTING META-TRANSACTION...");
    
    try {
      // Use higher gas limit and price for meta-transactions
      const tx = await exchange.executeSignedOrderWithPermits(
        tradeData.order,
        tradeData.signatures.maker,
        tradeData.signatures.taker,
        makerPermit,
        takerPermit,
        {
          gasLimit: 2000000,
          maxFeePerGas: ethers.utils.parseUnits("100", "gwei"),
          maxPriorityFeePerGas: ethers.utils.parseUnits("2", "gwei")
        }
      );
      
      console.log(`Transaction submitted: ${tx.hash}`);
      console.log(`Explorer link: ${network.name === 'matic' ? `https://polygonscan.com/tx/${tx.hash}` : 
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
        console.log(`Maker's ${makerTokenSymbol}: ${ethers.utils.formatUnits(finalMakerBalance, makerTokenDecimals)}`);
        console.log(`Taker's ${takerTokenSymbol}: ${ethers.utils.formatUnits(finalTakerBalance, takerTokenDecimals)}`);
        console.log(`Maker's ${takerTokenSymbol}: ${ethers.utils.formatUnits(finalMakerTakerTokenBalance, takerTokenDecimals)}`);
        console.log(`Taker's ${makerTokenSymbol}: ${ethers.utils.formatUnits(finalTakerMakerTokenBalance, makerTokenDecimals)}`);
        
        // Calculate token transfers
        const securityTokensTransferredToTaker = finalTakerMakerTokenBalance.sub(initialBuyerMakerTokenBalance);
        const cashTokensTransferredToMaker = finalMakerTakerTokenBalance.sub(initialSellerTakerTokenBalance);
        
        console.log(`\n💱 TOKEN TRANSFERS:`);
        console.log(`${makerTokenSymbol} transferred to taker: ${ethers.utils.formatUnits(securityTokensTransferredToTaker, makerTokenDecimals)}`);
        console.log(`${takerTokenSymbol} transferred to maker: ${ethers.utils.formatUnits(cashTokensTransferredToMaker, takerTokenDecimals)}`);
        
        // Calculate token deductions
        const securityTokensFromSeller = makerBalance.sub(finalMakerBalance);
        const cashTokensFromBuyer = takerBalance.sub(finalTakerBalance);
        
        console.log(`\n💸 TOKEN DEDUCTIONS:`);
        console.log(`${makerTokenSymbol} taken from maker: ${ethers.utils.formatUnits(securityTokensFromSeller, makerTokenDecimals)}`);
        console.log(`${takerTokenSymbol} taken from taker: ${ethers.utils.formatUnits(cashTokensFromBuyer, takerTokenDecimals)}`);
        
        // Check for fees
        const securityTokenFee = securityTokensFromSeller.sub(securityTokensTransferredToTaker);
        const cashTokenFee = cashTokensFromBuyer.sub(cashTokensTransferredToMaker);
        
        if (securityTokenFee.isZero() && cashTokenFee.isZero()) {
          console.log("\n✅ META-TRANSACTION TRADE EXECUTED WITH NO FEES");
        } else {
          console.log(`\n⚠️ FEES DETECTED IN TRANSACTION:`);
          if (!securityTokenFee.isZero()) {
            console.log(`${makerTokenSymbol} fee: ${ethers.utils.formatUnits(securityTokenFee, makerTokenDecimals)}`);
          }
          if (!cashTokenFee.isZero()) {
            console.log(`${takerTokenSymbol} fee: ${ethers.utils.formatUnits(cashTokenFee, takerTokenDecimals)}`);
          }
        }
        
        // Check final allowances to see if permits worked
        const finalMakerAllowance = await makerToken.allowance(tradeData.order.maker, exchangeAddress);
        const finalTakerAllowance = await takerToken.allowance(tradeData.order.taker, exchangeAddress);
        
        console.log("\n🔓 FINAL ALLOWANCES:");
        console.log(`Maker's allowance: ${ethers.utils.formatUnits(finalMakerAllowance, makerTokenDecimals)} ${makerTokenSymbol}`);
        console.log(`Taker's allowance: ${ethers.utils.formatUnits(finalTakerAllowance, takerTokenDecimals)} ${takerTokenSymbol}`);
        
        if (hasMakerPermit) {
          console.log(`Maker permit applied: ${!makerAllowance.eq(finalMakerAllowance) ? "✅ YES" : "❌ NO"}`);
        }
        
        if (hasTakerPermit) {
          console.log(`Taker permit applied: ${!takerAllowance.eq(finalTakerAllowance) ? "✅ YES" : "❌ NO"}`);
        }
        
        if ((hasMakerPermit || hasTakerPermit) && 
            (!makerAllowance.eq(finalMakerAllowance) || !takerAllowance.eq(finalTakerAllowance))) {
          console.log("\n✅ PERMITS SUCCESSFULLY APPLIED IN TRANSACTION");
        }
      } else {
        console.error("❌ TRANSACTION FAILED!");
      }
    } catch (error) {
      console.error("Error executing meta-transaction:", error);
      
      const errorDetails = formatError(error);
      if (errorDetails.reason) {
        console.error(`Revert reason: ${errorDetails.reason}`);
      }
      
      if (error.transaction) {
        console.log(`Transaction hash: ${error.transaction.hash}`);
        console.log(`Explorer link: ${network.name === 'matic' ? `https://polygonscan.com/tx/${error.transaction.hash}` : 
                    (network.name === 'maticmum' ? `https://mumbai.polygonscan.com/tx/${error.transaction.hash}` : 
                    `https://etherscan.io/tx/${error.transaction.hash}`)}`);
      }
      
      // Provide detailed error analysis
      console.log("\n🔍 ERROR ANALYSIS:");
      
      if (timeUntilExpiry <= 0) {
        console.error("- The order has expired (expiry timestamp is in the past)");
        console.error(`  Current time: ${currentTimestamp}, Order expiry: ${orderExpiry}`);
        console.error("  FIX: Update the order's expiry timestamp to a future time");
      }
      
      const errorMsg = error.message.toLowerCase();
      if (errorMsg.includes("insufficient") || errorMsg.includes("balance")) {
        console.error("- Insufficient token balance or allowance issues:");
        if (!makerHasSufficientBalance) {
          console.error(`  Maker balance: ${ethers.utils.formatUnits(makerBalance, makerTokenDecimals)} ${makerTokenSymbol}, Required: ${ethers.utils.formatUnits(tradeData.order.makerAmount, makerTokenDecimals)}`);
        }
        if (!takerHasSufficientBalance) {
          console.error(`  Taker balance: ${ethers.utils.formatUnits(takerBalance, takerTokenDecimals)} ${takerTokenSymbol}, Required: ${ethers.utils.formatUnits(tradeData.order.takerAmount, takerTokenDecimals)}`);
        }
        if (!makerHasSufficientAllowance && !hasMakerPermit) {
          console.error(`  Maker allowance: ${ethers.utils.formatUnits(makerAllowance, makerTokenDecimals)} ${makerTokenSymbol}, Required: ${ethers.utils.formatUnits(tradeData.order.makerAmount, makerTokenDecimals)}`);
        }
        if (!takerHasSufficientAllowance && !hasTakerPermit) {
          console.error(`  Taker allowance: ${ethers.utils.formatUnits(takerAllowance, takerTokenDecimals)} ${takerTokenSymbol}, Required: ${ethers.utils.formatUnits(tradeData.order.takerAmount, takerTokenDecimals)}`);
        }
      }
      
      if (errorMsg.includes("signature") || errorMsg.includes("signer")) {
        console.error("- Signature validation failed:");
        console.error("  • Ensure the signatures were created on the correct chain ID");
        console.error(`  • Current chain ID: ${chainId}, Domain chain ID: ${tradeData.domain?.chainId || "Not specified"}`);
        console.error("  • Verify the order parameters match what was signed");
        console.error("  • Check that the signature format is correct");
      }
      
      if (errorMsg.includes("nonce")) {
        console.error("- Nonce issues detected:");
        console.error(`  Maker nonce: ${tradeData.order.makerNonce || 0}`);
        console.error(`  Taker nonce: ${tradeData.order.takerNonce || 0}`);
        console.error("  FIX: Check if these nonces have already been used");
      }
      
      if (errorMsg.includes("permit") || errorMsg.includes("deadline")) {
        console.error("- Permit-related issues:");
        console.error("  • Check if the tokens support EIP-2612 permit");
        console.error("  • Verify permit deadline is valid");
        console.error("  • Ensure permit signatures are correct");
        
        if (hasMakerPermit && makerPermit.deadline <= currentTimestamp) {
          console.error(`  Maker permit deadline expired: ${makerPermit.deadline} (${new Date(makerPermit.deadline * 1000).toLocaleString()})`);
        }
        
        if (hasTakerPermit && takerPermit.deadline <= currentTimestamp) {
          console.error(`  Taker permit deadline expired: ${takerPermit.deadline} (${new Date(takerPermit.deadline * 1000).toLocaleString()})`);
        }
      }
    }
  } catch (error) {
    console.error("Fatal error:", error);
  }
}

// Run the script
executeMetaTransaction().catch((error) => {
  console.error("Uncaught error:", error);
  process.exit(1);
});