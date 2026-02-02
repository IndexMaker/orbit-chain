#!/usr/bin/env node

const { ethers } = require("ethers");

const ERC20_ABI = [
  "function transfer(address to, uint256 amount) returns (bool)",
  "function balanceOf(address account) view returns (uint256)",
  "function symbol() view returns (string)",
];

async function transferERC20() {
  const args = process.argv.slice(2);

  if (args.length < 5) {
    console.log(
      "Usage: node transfer-erc20.js <rpc_url> <from_private_key> <token_address> <to_address> <amount>"
    );
    process.exit(1);
  }

  const [rpcUrl, fromPrivateKey, tokenAddress, toAddress, amount] = args;

  console.log(`📤 Transferring ${amount} tokens`);
  console.log(`Token: ${tokenAddress}`);
  console.log(`To: ${toAddress}`);

  let provider;
  try {
    provider = new ethers.providers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(fromPrivateKey, provider);

    console.log(`From: ${wallet.address}`);

    const token = new ethers.Contract(tokenAddress, ERC20_ABI, wallet);

    // Get symbol
    let symbol = "TOKEN";
    try {
      symbol = await token.symbol();
    } catch (e) {
      // Ignore if symbol not available
    }

    // Check balance
    const balance = await token.balanceOf(wallet.address);
    console.log(`Current balance: ${ethers.utils.formatEther(balance)} ${symbol}`);

    const amountWei = ethers.utils.parseEther(amount);

    if (balance.lt(amountWei)) {
      console.log(`⚠️  Insufficient balance. Have ${ethers.utils.formatEther(balance)}, need ${amount}`);
      // Transfer what we have
      if (balance.gt(0)) {
        console.log(`Transferring available balance: ${ethers.utils.formatEther(balance)}`);
        const tx = await token.transfer(toAddress, balance);
        console.log(`Transaction sent: ${tx.hash}`);
        await tx.wait();
        console.log(`✅ Transfer confirmed`);
      }
      return;
    }

    const tx = await token.transfer(toAddress, amountWei);
    console.log(`Transaction sent: ${tx.hash}`);
    await tx.wait();
    console.log(`✅ Transferred ${amount} ${symbol} to ${toAddress}`);

    // Verify
    const newBalance = await token.balanceOf(toAddress);
    console.log(`Recipient balance: ${ethers.utils.formatEther(newBalance)} ${symbol}`);
  } catch (error) {
    console.error(`❌ Error: ${error.message}`);
    process.exit(1);
  } finally {
    if (provider) provider.removeAllListeners();
  }
}

transferERC20();
