// Script to check KYC status for an address
require('dotenv').config();
const ethers = require('ethers');

// Simple ABI fragments for the necessary functions
const complianceAbi = [
  "function isKYCVerified(address _address) view returns (bool)",
  "function identityRegistry() view returns (address)",
  "function checkCompliance(address _from, address _to, address _token, uint256 _amount) view returns (bool)",
];

const identityRegistryAbi = [
  "function isVerified(address _address) view returns (bool)",
  "function hasAttribute(address _address, bytes32 _attribute) view returns (bool)",
  "function getAttribute(address _address, bytes32 _attribute) view returns (bytes32)",
];

const tokenAbi = [
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function balanceOf(address account) view returns (uint256)",
];

async function main() {
  console.log("🔍 KYC STATUS CHECKER WITH ENHANCED DEBUGGING\n");

  // Load env variables
  const rpcUrl = process.env.RPC_URL || "https://polygon-rpc.com";
  const buyerAddress = process.env.BUYER_ADDRESS;
  const sellerAddress = process.env.SELLER_ADDRESS;
  const privateKey = process.env.PRIVATE_KEY;
  const complianceAddress = process.env.COMPLIANCE_ADDRESS;
  const registryAddress = process.env.IDENTITY_REGISTRY_ADDRESS;
  const makerTokenAddress = process.env.MAKER_TOKEN_ADDRESS;
  const takerTokenAddress = process.env.TAKER_TOKEN_ADDRESS;

  // Validate required env variables
  if (!buyerAddress) {
    console.error("❌ BUYER_ADDRESS environment variable is required");
    process.exit(1);
  }

  if (!complianceAddress) {
    console.error("❌ COMPLIANCE_ADDRESS environment variable is required");
    process.exit(1);
  }

  // Setup provider and wallet
  console.log(`Connecting to ${rpcUrl}...`);
  const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
  let wallet;
  
  if (privateKey) {
    wallet = new ethers.Wallet(privateKey, provider);
    console.log(`Using wallet address: ${wallet.address}`);
  } else {
    console.log("No private key provided, running in read-only mode");
  }

  // Get network information
  const network = await provider.getNetwork();
  console.log(`\n🌐 NETWORK INFORMATION:`);
  console.log(`Connected to network: ${network.name} (Chain ID: ${network.chainId})`);

  // Connect to Compliance contract
  const compliance = new ethers.Contract(
    complianceAddress,
    complianceAbi,
    provider
  );
  
  console.log(`\n🏛️ COMPLIANCE CONTRACT CHECKS:`);
  console.log(`Compliance Contract: ${complianceAddress}`);

  // Check KYC status through Compliance contract
  try {
    const isVerified = await compliance.isKYCVerified(buyerAddress);
    console.log(`Buyer KYC verified via isKYCVerified(): ${isVerified ? '✅ YES' : '❌ NO'}`);
    
    if (sellerAddress) {
      const isSellerVerified = await compliance.isKYCVerified(sellerAddress);
      console.log(`Seller KYC verified via isKYCVerified(): ${isSellerVerified ? '✅ YES' : '❌ NO'}`);
    }
  } catch (error) {
    console.log(`❌ Error checking isKYCVerified: ${error.message}`);
  }

  // Try to simulate a transfer via compliance check if token addresses are provided
  if (makerTokenAddress && takerTokenAddress && sellerAddress) {
    try {
      // Check seller to buyer compliance
      const transferCompliant = await compliance.checkCompliance(
        sellerAddress,
        buyerAddress,
        makerTokenAddress,
        ethers.utils.parseEther("1") // Simulate a 1 token transfer
      );
      console.log(`\nCompliance check for seller→buyer transfer: ${transferCompliant ? '✅ PASSED' : '❌ FAILED'}`);
      
      // Check buyer to seller compliance (reverse direction)
      const reverseCompliant = await compliance.checkCompliance(
        buyerAddress,
        sellerAddress,
        takerTokenAddress,
        ethers.utils.parseEther("1") // Simulate a 1 token transfer
      );
      console.log(`Compliance check for buyer→seller transfer: ${reverseCompliant ? '✅ PASSED' : '❌ FAILED'}`);
    } catch (error) {
      console.log(`❌ Error checking transfer compliance: ${error.message}`);
    }
  }

  // Try to get Identity Registry from Compliance if available
  let foundRegistryAddress;
  try {
    foundRegistryAddress = await compliance.identityRegistry();
    console.log(`\nIdentity Registry found in Compliance: ${foundRegistryAddress}`);
  } catch (error) {
    console.log(`\nNo identityRegistry() function found in Compliance contract: ${error.message}`);
  }

  // Use provided registry address or the one found in compliance
  const identityRegistryToUse = registryAddress || foundRegistryAddress;
  
  if (identityRegistryToUse && identityRegistryToUse !== ethers.constants.AddressZero) {
    console.log(`\n🔖 IDENTITY REGISTRY CHECKS:`);
    console.log(`Identity Registry: ${identityRegistryToUse}`);
    
    const registry = new ethers.Contract(
      identityRegistryToUse,
      identityRegistryAbi,
      provider
    );

    // Check isVerified
    try {
      const isVerified = await registry.isVerified(buyerAddress);
      console.log(`Buyer verified via isVerified(): ${isVerified ? '✅ YES' : '❌ NO'}`);
      
      if (sellerAddress) {
        const isSellerVerified = await registry.isVerified(sellerAddress);
        console.log(`Seller verified via isVerified(): ${isSellerVerified ? '✅ YES' : '❌ NO'}`);
      }
    } catch (error) {
      console.log(`❌ Error checking isVerified: ${error.message}`);
    }

    // Check for KYC_VERIFIED attribute
    const KYC_ATTRIBUTE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("KYC_VERIFIED"));
    console.log(`\nChecking for attribute: KYC_VERIFIED (${KYC_ATTRIBUTE})`);
    
    try {
      const hasKYC = await registry.hasAttribute(buyerAddress, KYC_ATTRIBUTE);
      console.log(`Buyer has KYC attribute: ${hasKYC ? '✅ YES' : '❌ NO'}`);
      
      if (sellerAddress) {
        const sellerHasKYC = await registry.hasAttribute(sellerAddress, KYC_ATTRIBUTE);
        console.log(`Seller has KYC attribute: ${sellerHasKYC ? '✅ YES' : '❌ NO'}`);
      }
      
      // Try to get the actual attribute value
      try {
        const kycValue = await registry.getAttribute(buyerAddress, KYC_ATTRIBUTE);
        console.log(`Buyer KYC attribute value: ${kycValue}`);
      } catch (error) {
        console.log(`Cannot get attribute value: ${error.message}`);
      }
    } catch (error) {
      console.log(`❌ Error checking hasAttribute: ${error.message}`);
    }
  } else {
    console.log(`\n❌ No Identity Registry address available for further checks`);
  }

  // Check token-specific information if provided
  if (makerTokenAddress && takerTokenAddress) {
    console.log(`\n💰 TOKEN INFORMATION:`);
    
    // Check maker token
    const makerToken = new ethers.Contract(
      makerTokenAddress,
      tokenAbi,
      provider
    );
    
    try {
      const symbol = await makerToken.symbol();
      const decimals = await makerToken.decimals();
      console.log(`Maker Token: ${makerTokenAddress} (${symbol}, ${decimals} decimals)`);
      
      if (sellerAddress) {
        const balance = await makerToken.balanceOf(sellerAddress);
        console.log(`Seller's ${symbol} balance: ${ethers.utils.formatUnits(balance, decimals)}`);
      }
      
      // Check buyer's balance of maker token
      const buyerMakerBalance = await makerToken.balanceOf(buyerAddress);
      console.log(`Buyer's ${symbol} balance: ${ethers.utils.formatUnits(buyerMakerBalance, decimals)}`);
    } catch (error) {
      console.log(`❌ Error checking maker token: ${error.message}`);
    }
    
    // Check taker token
    const takerToken = new ethers.Contract(
      takerTokenAddress,
      tokenAbi,
      provider
    );
    
    try {
      const symbol = await takerToken.symbol();
      const decimals = await takerToken.decimals();
      console.log(`Taker Token: ${takerTokenAddress} (${symbol}, ${decimals} decimals)`);
      
      // Check buyer's balance
      const buyerBalance = await takerToken.balanceOf(buyerAddress);
      console.log(`Buyer's ${symbol} balance: ${ethers.utils.formatUnits(buyerBalance, decimals)}`);
      
      if (sellerAddress) {
        const sellerBalance = await takerToken.balanceOf(sellerAddress);
        console.log(`Seller's ${symbol} balance: ${ethers.utils.formatUnits(sellerBalance, decimals)}`);
      }
    } catch (error) {
      console.log(`❌ Error checking taker token: ${error.message}`);
    }
  }

  console.log("\n✅ KYC status check complete");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(`❌ Error in main function: ${error.message}`);
    if (error.stack) console.error(error.stack);
    process.exit(1);
  });