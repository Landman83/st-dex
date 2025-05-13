// Script to generate a single valid trade with real EIP-712 signatures
const fs = require('fs');
const ethers = require('ethers');
require('dotenv').config();

// Import EIP-712 domain and types that must match the Exchange contract
const DOMAIN_TYPE = [
  { name: "name", type: "string" },
  { name: "version", type: "string" },
  { name: "chainId", type: "uint256" },
  { name: "verifyingContract", type: "address" }
];

// Must exactly match the OrderInfo struct in the Exchange contract
const ORDER_TYPE = [
  { name: "maker", type: "address" },
  { name: "makerToken", type: "address" },
  { name: "makerAmount", type: "uint256" },
  { name: "taker", type: "address" },
  { name: "takerToken", type: "address" },
  { name: "takerAmount", type: "uint256" },
  { name: "makerNonce", type: "uint256" },
  { name: "takerNonce", type: "uint256" },
  { name: "expiry", type: "uint256" }
];

// These values should be set in your .env file
const EXCHANGE_ADDRESS = process.env.EXCHANGE_ADDRESS;
const SECURITY_TOKEN_ADDRESS = process.env.SECURITY_TOKEN_ADDRESS;
const CASH_TOKEN_ADDRESS = process.env.CASH_TOKEN_ADDRESS;
const CHAIN_ID = parseInt(process.env.CHAIN_ID || "1337");  // Use your chain ID

// Wallet setup - deployer is selling, buyer is buying
const deployerPrivateKey = process.env.PRIVATE_KEY;  // Seller
const buyerPrivateKey = process.env.BUYER_PRIVATE_KEY;  // Buyer

// Create wallet instances
const deployerWallet = new ethers.Wallet(deployerPrivateKey);
const buyerWallet = new ethers.Wallet(buyerPrivateKey);

console.log(`Seller (deployer) address: ${deployerWallet.address}`);
console.log(`Buyer address: ${buyerWallet.address}`);

// EIP-712 Domain - must match what's in the Signatures contract
const domain = {
  name: "Numena Exchange",
  version: "1.0.0",
  chainId: CHAIN_ID,
  verifyingContract: EXCHANGE_ADDRESS
};

// Function to sign an order using EIP-712
async function signOrder(order, wallet, role) {
  // Sign the order with EIP-712
  const signature = await wallet._signTypedData(
    domain,
    { OrderInfo: ORDER_TYPE },
    order
  );
  
  console.log(`Signed order as ${role} (${wallet.address}): ${signature}`);
  return signature;
}

// Create and sign a single trade
async function generateTrade() {
  // Set expiry to 30 days from now
  const expiry = Math.floor(Date.now() / 1000) + 30 * 24 * 60 * 60;
  
  // Define the order: deployer sells security tokens, buyer purchases with cash tokens
  const order = {
    maker: deployerWallet.address,          // Seller
    makerToken: SECURITY_TOKEN_ADDRESS,     // Security token being sold
    makerAmount: ethers.utils.parseEther("100").toString(), // 100 security tokens
    taker: buyerWallet.address,             // Buyer
    takerToken: CASH_TOKEN_ADDRESS,         // Cash token used to buy
    takerAmount: ethers.utils.parseEther("1000").toString(), // 1000 cash tokens
    makerNonce: 0,                          // First transaction for maker
    takerNonce: 0,                          // First transaction for taker
    expiry: expiry                          // 30 days expiry
  };

  console.log("Generated order:", order);

  // Sign the order
  const makerSignature = await signOrder(order, deployerWallet, "seller");
  const takerSignature = await signOrder(order, buyerWallet, "buyer");

  // Prepare the final trade data
  const tradeData = {
    description: "Security token purchase with cash token",
    domain: {
      name: domain.name,
      version: domain.version,
      chainId: domain.chainId,
      verifyingContract: domain.verifyingContract
    },
    order: order,
    signatures: {
      maker: makerSignature,
      taker: takerSignature
    }
  };

  // Write to JSON file
  fs.writeFileSync(
    './test/signed_trade.json', 
    JSON.stringify(tradeData, null, 2)
  );
  
  console.log("Signed trade written to test/signed_trade.json");
  
  // Also write a validation file for use with test scripts
  const validationData = {
    sellerAddress: deployerWallet.address,
    buyerAddress: buyerWallet.address,
    securityTokenAddress: SECURITY_TOKEN_ADDRESS,
    cashTokenAddress: CASH_TOKEN_ADDRESS,
    securityTokenAmount: order.makerAmount,
    cashTokenAmount: order.takerAmount
  };
  
  fs.writeFileSync(
    './test/trade_validation.json',
    JSON.stringify(validationData, null, 2)
  );
  
  console.log("Validation data written to test/trade_validation.json");
}

// Run the script
generateTrade().catch((error) => {
  console.error("Error generating trade:", error);
});