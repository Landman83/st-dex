# Exchange Transaction Debugging Guide

This guide explains how to use the enhanced `execute_trade.js` script to diagnose issues with meta-transactions in the Exchange contract.

## Prerequisites

- Node.js and npm installed
- A `.env` file with the following variables:
  ```
  PRIVATE_KEY=your_private_key
  RPC_URL=https://polygon-rpc.com
  CHAIN_ID=137
  EXCHANGE_ADDRESS=0x4C05d6D5b72ec37BEA51b47a8b8c79a5499F5023
  ```

## Running the Script

```bash
node test/execute_trade.js
```

By default, the script will:
1. Load trade data from `test/signed_trade.json`
2. Use the meta-transaction version (`executeSignedOrderWithPermits`) if permit data is present
3. Perform comprehensive checks before executing the transaction

## Environment Variables

- `EXCHANGE_ADDRESS`: Address of the Exchange contract
- `PRIVATE_KEY`: Private key of the account executing the transaction
- `RPC_URL`: RPC endpoint for the blockchain network
- `CHAIN_ID`: Chain ID of the network (default is 137 for Polygon)
- `TRADE_FILE`: Custom path to load trade data from (defaults to `./test/signed_trade.json`)
- `USE_LEGACY=true`: Force using the non-permit version (`executeSignedOrder`)
- `FORCE_PERMIT=true`: Force using the permit version even if no permit data is present

## Understanding Error Messages

The script will perform extensive validation before submitting transactions:

1. **Order Expiry Check**: Verifies if the order's expiry timestamp is in the future
2. **Token Balance Check**: Confirms both parties have sufficient token balances
3. **Token Allowance Check**: Verifies token allowances or confirms permit data is present
4. **Transaction Simulation**: Performs a dry-run to catch potential errors before submission
5. **Contract Reference Check**: Validates all required contract references are set

## Debugging "Order has expired" Errors

This error occurs when the transaction timestamp is greater than the order's expiry timestamp. Check:

1. The order's expiry value in `signed_trade.json`
2. Current timestamp (printed in script output)
3. Update the expiry to a future timestamp if needed

## Debugging Signature Validation Failures

If you see signature errors, verify:

1. Chain ID matches between where signatures were generated and where transaction is executed
2. Order parameters match what was signed
3. Signature format (v, r, s) is correct

## Debugging Allowance Issues

For transactions that fail due to insufficient allowances:

1. Confirm the appropriate ERC20 approve transactions were executed
2. Or ensure complete and correct permit data is included
3. If using permit, verify the tokens support EIP-2612 permit function

## Advanced Log Analysis

The script outputs detailed information in these sections:

- **NETWORK INFORMATION**: Basic network details
- **ACCOUNT INFORMATION**: Addresses involved in the trade
- **CONTRACT INFORMATION**: Exchange contract and its dependencies
- **TOKEN INFORMATION**: Token addresses, symbols, and decimals
- **BALANCES**: Current token balances of all parties
- **ALLOWANCES**: Current token allowances
- **PERMIT DATA**: Information about EIP-2612 permit usage
- **ORDER TIMING**: Expiry check and validation
- **COMPLIANCE CHECK**: KYC verification status if available
- **TOKEN REGISTRATION**: Registry status if available
- **SIMULATING TRANSACTION**: Dry-run results
- **ERROR ANALYSIS**: Detailed breakdown of potential issues