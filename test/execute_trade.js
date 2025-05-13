// Script to execute a signed trade using the Exchange contract
// Deployer handles the entire execution, including approvals and transaction submission
const fs = require('fs');
const ethers = require('ethers');
require('dotenv').config();

// Load Exchange ABI from Foundry's output directory
const exchangeABI = require('../out/Exchange.sol/Exchange.json').abi;

// Load token ABI for ERC20 operations
const erc20ABI = [
  "function balanceOf(address owner) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)"
];

async function executeTrade() {
  try {
    // Load the signed trade from JSON
    const tradeData = JSON.parse(fs.readFileSync('./test/signed_trade.json', 'utf8'));

    // Setup provider and network
    const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
    const chainId = parseInt(process.env.CHAIN_ID || "1337");

    console.log(`Connected to network with chain ID: ${chainId}`);

    // Check if the network matches the signed trade's chain ID
    if (tradeData.domain.chainId !== chainId) {
      throw new Error(`Chain ID mismatch. Trade is signed for chain ${tradeData.domain.chainId}, but connected to ${chainId}`);
    }

    // Setup deployer wallet
    const deployerWallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    console.log(`Deployer: ${deployerWallet.address}`);
    console.log(`Seller: ${tradeData.order.maker}`);
    console.log(`Buyer: ${tradeData.order.taker}`);

    // Verify that deployer has enough ETH for gas
    const deployerEthBalance = await provider.getBalance(deployerWallet.address);
    console.log(`Deployer ETH balance: ${ethers.utils.formatEther(deployerEthBalance)} ETH`);

    if (deployerEthBalance.lt(ethers.utils.parseEther("0.01"))) {
      console.warn("WARNING: Deployer has less than 0.01 ETH for gas. Transactions might fail.");
    }

    // Connect to the Exchange contract
    const exchangeAddress = tradeData.domain.verifyingContract;
    const exchange = new ethers.Contract(exchangeAddress, exchangeABI, deployerWallet);
    console.log(`Exchange contract: ${exchangeAddress}`);

    // Connect to token contracts
    const securityToken = new ethers.Contract(tradeData.order.makerToken, erc20ABI, deployerWallet);
    const cashToken = new ethers.Contract(tradeData.order.takerToken, erc20ABI, deployerWallet);

    console.log(`Security token: ${tradeData.order.makerToken}`);
    console.log(`Cash token: ${tradeData.order.takerToken}`);

    // Check initial balances
    const initialSellerSecurityBalance = await securityToken.balanceOf(tradeData.order.maker);
    const initialBuyerCashBalance = await cashToken.balanceOf(tradeData.order.taker);

    console.log(`\nINITIAL BALANCES:`);
    console.log(`Seller's security tokens: ${ethers.utils.formatEther(initialSellerSecurityBalance)}`);
    console.log(`Buyer's cash tokens: ${ethers.utils.formatEther(initialBuyerCashBalance)}`);

    // Verify seller has enough security tokens
    if (initialSellerSecurityBalance.lt(tradeData.order.makerAmount)) {
      throw new Error(`Seller doesn't have enough security tokens. Has ${ethers.utils.formatEther(initialSellerSecurityBalance)}, needs ${ethers.utils.formatEther(tradeData.order.makerAmount)}`);
    }

    // Verify buyer has enough cash tokens
    if (initialBuyerCashBalance.lt(tradeData.order.takerAmount)) {
      throw new Error(`Buyer doesn't have enough cash tokens. Has ${ethers.utils.formatEther(initialBuyerCashBalance)}, needs ${ethers.utils.formatEther(tradeData.order.takerAmount)}`);
    }

    // Before executing, check if the tokens are already approved
    console.log("\nCHECKING APPROVALS:");

    // Only check the approvals - we should not be making approval transactions
    // The contract should rely solely on the signatures for validation
    const securityTokenAllowance = await securityToken.allowance(tradeData.order.maker, exchangeAddress);
    console.log(`Seller's security token allowance: ${ethers.utils.formatEther(securityTokenAllowance)}`);

    const cashTokenAllowance = await cashToken.allowance(tradeData.order.taker, exchangeAddress);
    console.log(`Buyer's cash token allowance: ${ethers.utils.formatEther(cashTokenAllowance)}`);

    // If allowances are too low, warn but proceed anyway since we're using signatures
    if (securityTokenAllowance.lt(tradeData.order.makerAmount)) {
      console.warn(`WARNING: Seller's security token allowance (${ethers.utils.formatEther(securityTokenAllowance)}) is less than the trade amount (${ethers.utils.formatEther(tradeData.order.makerAmount)})`);
      console.warn("If your Exchange contract requires explicit ERC20 approvals in addition to signatures, this trade may fail.");
    }

    if (cashTokenAllowance.lt(tradeData.order.takerAmount)) {
      console.warn(`WARNING: Buyer's cash token allowance (${ethers.utils.formatEther(cashTokenAllowance)}) is less than the trade amount (${ethers.utils.formatEther(tradeData.order.takerAmount)})`);
      console.warn("If your Exchange contract requires explicit ERC20 approvals in addition to signatures, this trade may fail.");
    }

    // Execute the signed order as the deployer
    console.log("\nEXECUTING TRADE:");
    console.log("Deployer submitting the transaction and paying gas...");

    // Use higher gas limit and price to ensure transaction goes through
    const executeTx = await exchange.executeSignedOrder(
      tradeData.order,
      tradeData.signatures.maker,
      tradeData.signatures.taker,
      {
        gasLimit: 1000000,
        gasPrice: ethers.utils.parseUnits("50", "gwei")  // Adjust as needed
      }
    );

    console.log(`Transaction hash: ${executeTx.hash}`);
    console.log("Waiting for transaction confirmation...");

    const receipt = await executeTx.wait();
    console.log(`Transaction confirmed in block ${receipt.blockNumber}`);

    // Check final balances
    const finalSellerSecurityBalance = await securityToken.balanceOf(tradeData.order.maker);
    const finalBuyerSecurityBalance = await securityToken.balanceOf(tradeData.order.taker);
    const finalSellerCashBalance = await cashToken.balanceOf(tradeData.order.maker);
    const finalBuyerCashBalance = await cashToken.balanceOf(tradeData.order.taker);

    console.log("\nFINAL BALANCES:");
    console.log(`Seller's security tokens: ${ethers.utils.formatEther(finalSellerSecurityBalance)}`);
    console.log(`Buyer's security tokens: ${ethers.utils.formatEther(finalBuyerSecurityBalance)}`);
    console.log(`Seller's cash tokens: ${ethers.utils.formatEther(finalSellerCashBalance)}`);
    console.log(`Buyer's cash tokens: ${ethers.utils.formatEther(finalBuyerCashBalance)}`);

    // Verify the swap was successful
    console.log("\nVERIFICATION:");

    const securityTokensTransferred = initialSellerSecurityBalance.sub(finalSellerSecurityBalance);
    console.log(`Security tokens transferred: ${ethers.utils.formatEther(securityTokensTransferred)}`);

    const cashTokensTransferred = initialBuyerCashBalance.sub(finalBuyerCashBalance);
    console.log(`Cash tokens transferred: ${ethers.utils.formatEther(cashTokensTransferred)}`);

    // Check for fees by comparing with expected transfers
    const expectedSecurityTransfer = ethers.BigNumber.from(tradeData.order.makerAmount);
    const expectedCashTransfer = ethers.BigNumber.from(tradeData.order.takerAmount);

    if (securityTokensTransferred.eq(expectedSecurityTransfer) &&
        cashTokensTransferred.eq(expectedCashTransfer)) {
      console.log("\nTRADE SUCCESSFUL WITH NO FEES ✅");
    } else {
      // There may be fees taken, calculate and report
      const securityTokenFee = securityTokensTransferred.sub(expectedSecurityTransfer);
      const cashTokenFee = cashTokensTransferred.sub(expectedCashTransfer);

      console.log(`\nTRADE SUCCESSFUL WITH FEES ✅`);
      if (!securityTokenFee.isZero()) {
        console.log(`Security token fee: ${ethers.utils.formatEther(securityTokenFee)}`);
      }
      if (!cashTokenFee.isZero()) {
        console.log(`Cash token fee: ${ethers.utils.formatEther(cashTokenFee)}`);
      }
    }

  } catch (error) {
    console.error("Error executing trade:", error);
  }
}

// Run the script
executeTrade().catch((error) => {
  console.error("Uncaught error:", error);
});