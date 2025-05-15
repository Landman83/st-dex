// Script to generate a trade with EIP-712 signatures and ERC20 permit signatures
const fs = require('fs');
const ethers = require('ethers');
require('dotenv').config();

// Import EIP-712 domain and types
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

// EIP-2612 Permit type definition
const PERMIT_TYPE = [
  { name: "owner", type: "address" },
  { name: "spender", type: "address" },
  { name: "value", type: "uint256" },
  { name: "nonce", type: "uint256" },
  { name: "deadline", type: "uint256" }
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

// EIP-712 Domain for the Exchange
const exchangeDomain = {
  name: "Numena Exchange",
  version: "1.0.0",
  chainId: CHAIN_ID,
  verifyingContract: EXCHANGE_ADDRESS
};

// Function to sign an order using EIP-712
async function signOrder(order, wallet, role) {
  // Sign the order with EIP-712
  const signature = await wallet._signTypedData(
    exchangeDomain,
    { OrderInfo: ORDER_TYPE },
    order
  );
  
  console.log(`Signed order as ${role} (${wallet.address}): ${signature}`);
  return signature;
}

// Function to create and sign a token permit
async function signPermit(tokenAddress, ownerWallet, tokenName, spender, value, nonce, deadline) {
  // EIP-712 Domain for the token
  const tokenDomain = {
    name: tokenName,
    version: "1",
    chainId: CHAIN_ID,
    verifyingContract: tokenAddress
  };

  // Permit data
  const permitData = {
    owner: ownerWallet.address,
    spender: spender,
    value: value,
    nonce: nonce,
    deadline: deadline
  };

  // Sign the permit
  const signature = await ownerWallet._signTypedData(
    tokenDomain,
    { Permit: PERMIT_TYPE },
    permitData
  );

  // Split signature to get v, r, s
  const sig = ethers.utils.splitSignature(signature);
  
  console.log(`Signed permit for ${tokenName} (${tokenAddress}): v=${sig.v}, r=${sig.r}, s=${sig.s}`);
  
  return {
    v: sig.v,
    r: sig.r,
    s: sig.s
  };
}

// Create and sign a trade with permits
async function generateMetaTransaction() {
  // Set expiry to 30 days from now
  const expiry = Math.floor(Date.now() / 1000) + 30 * 24 * 60 * 60;
  
  // Permit deadline can be longer (60 days)
  const permitDeadline = Math.floor(Date.now() / 1000) + 60 * 24 * 60 * 60;

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

  // Sign permits for both tokens (assuming both support EIP-2612)
  // You would need to get the actual nonces from the token contracts in production
  const makerTokenNonce = 0;  // Should get from token contract in production
  const takerTokenNonce = 0;  // Should get from token contract in production
  
  // Sign permit for maker's token
  const makerPermit = await signPermit(
    SECURITY_TOKEN_ADDRESS,
    deployerWallet,
    "Security Token",  // Replace with actual token name
    EXCHANGE_ADDRESS,
    order.makerAmount,
    makerTokenNonce,
    permitDeadline
  );
  
  // Sign permit for taker's token
  const takerPermit = await signPermit(
    CASH_TOKEN_ADDRESS,
    buyerWallet,
    "Cash Token",  // Replace with actual token name
    EXCHANGE_ADDRESS,
    order.takerAmount,
    takerTokenNonce,
    permitDeadline
  );

  // Prepare the final trade data with permits
  const tradeData = {
    description: "Security token purchase with cash token using meta-transactions",
    domain: {
      name: exchangeDomain.name,
      version: exchangeDomain.version,
      chainId: exchangeDomain.chainId,
      verifyingContract: exchangeDomain.verifyingContract
    },
    order: order,
    signatures: {
      maker: makerSignature,
      taker: takerSignature
    },
    permits: {
      maker: {
        token: SECURITY_TOKEN_ADDRESS,
        owner: deployerWallet.address,
        value: order.makerAmount,
        deadline: permitDeadline,
        v: makerPermit.v,
        r: makerPermit.r,
        s: makerPermit.s
      },
      taker: {
        token: CASH_TOKEN_ADDRESS,
        owner: buyerWallet.address,
        value: order.takerAmount,
        deadline: permitDeadline,
        v: takerPermit.v,
        r: takerPermit.r,
        s: takerPermit.s
      }
    }
  };

  // Write to JSON file
  fs.writeFileSync(
    './test/signed_meta_trade.json', 
    JSON.stringify(tradeData, null, 2)
  );
  
  console.log("Signed meta-transaction trade written to test/signed_meta_trade.json");
  
  // Also write a validation file for use with test scripts
  const validationData = {
    sellerAddress: deployerWallet.address,
    buyerAddress: buyerWallet.address,
    securityTokenAddress: SECURITY_TOKEN_ADDRESS,
    cashTokenAddress: CASH_TOKEN_ADDRESS,
    securityTokenAmount: order.makerAmount,
    cashTokenAmount: order.takerAmount,
    permitDeadline: permitDeadline
  };
  
  fs.writeFileSync(
    './test/meta_trade_validation.json',
    JSON.stringify(validationData, null, 2)
  );
  
  console.log("Validation data written to test/meta_trade_validation.json");
}

// Run the script
generateMetaTransaction().catch((error) => {
  console.error("Error generating meta-transaction trade:", error);
});