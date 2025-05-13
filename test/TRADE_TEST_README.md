# Exchange Trade Testing

This directory contains scripts for generating and executing signed trades on the Exchange contract.

## Overview

The test workflow has two main steps:
1. Generate a signed trade with real EIP-712 signatures
2. Execute the trade on the Exchange contract

## Setup

1. Create a `.env` file in the project root with the following variables:

```
# Network
RPC_URL=http://localhost:8545
CHAIN_ID=1337  # Use 137 for Polygon Mainnet

# Contract Addresses
EXCHANGE_ADDRESS=0x...  # Your deployed Exchange address
SECURITY_TOKEN_ADDRESS=0x...  # Address of the security token (seller's token)
CASH_TOKEN_ADDRESS=0x...  # Address of the cash token (buyer's token)

# Wallets
PRIVATE_KEY=0x...  # Seller/deployer private key
BUYER_PRIVATE_KEY=0x...  # Buyer private key
```

2. Install dependencies (if not already installed):

```bash
npm install ethers@5.7.2 dotenv
```

## Generating a Signed Trade

Run the following command to generate a properly signed trade:

```bash
node test/generate_trade.js
```

This will:
1. Create an order where the deployer sells security tokens in exchange for cash tokens
2. Sign the order with both the deployer's private key (as maker/seller) and the buyer's private key (as taker/buyer)
3. Write the signed trade to `test/signed_trade.json`
4. Write validation data to `test/trade_validation.json`

The script ensures the signatures are valid EIP-712 signatures that will be accepted by the Exchange contract.

## Executing the Trade

To execute the signed trade on the Exchange contract:

```bash
node test/execute_trade.js
```

This script will:
1. Load the signed trade from `test/signed_trade.json`
2. Connect to the smart contracts on the network
3. Check initial token balances
4. Approve tokens for the Exchange contract
5. Execute the signed order
6. Verify the final balances to confirm the trade was successful

## Important Notes

### EIP-712 Domain Parameters

The domain parameters in the generated signatures MUST match those used in the Signatures contract:

```javascript
const domain = {
  name: "Numena Exchange",  // Must match name in Signatures contract
  version: "1.0.0",         // Must match version in Signatures contract
  chainId: CHAIN_ID,
  verifyingContract: EXCHANGE_ADDRESS
};
```

### Token Approvals

Before executing a trade, both parties must approve the Exchange contract to transfer their tokens:

- Seller must approve the Exchange contract to spend the security tokens
- Buyer must approve the Exchange contract to spend the cash tokens

The `execute_trade.js` script handles these approvals automatically.

### Nonces

Each order requires a unique nonce for both maker and taker to prevent replay attacks. The Exchange contract tracks used nonces. If you receive a "nonce already used" error, you'll need to increment the nonces in the generated orders.

## Debugging

If the trade execution fails, check the following:

1. Are the contract addresses in `.env` correct?
2. Do the wallets have sufficient token balances?
3. Is the Exchange contract properly deployed and initialized?
4. Do the EIP-712 domain parameters match?
5. Are the signatures valid? (Check that the signatures in the JSON file are complete and correct)
6. Has the order already been executed? (Nonce issue)
7. Has the order expired?