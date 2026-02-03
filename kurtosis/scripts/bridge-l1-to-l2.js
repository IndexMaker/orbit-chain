#!/usr/bin/env node

const { ethers } = require("ethers");

// ERC20 ABI for approve
const ERC20_ABI = [
  "function approve(address spender, uint256 amount) returns (bool)",
  "function balanceOf(address account) view returns (uint256)",
  "function allowance(address owner, address spender) view returns (uint256)",
];

// ERC20Inbox ABI for depositERC20
const ERC20_INBOX_ABI = [
  "function depositERC20(uint256 amount) external returns (uint256)",
];

// Regular Inbox ABI for depositEth
const INBOX_ABI = ["function depositEth() external payable returns (uint256)"];

async function bridgeL1ToL2() {
  const args = process.argv.slice(2);

  if (args.length < 4) {
    console.log(
      "Usage: node bridge-l1-to-l2.js <l1_rpc_url> <l2_rpc_url> <funnel_private_key> <inbox_address> [amount] [native_token_address]"
    );
    console.log("");
    console.log("For ETH gas token chains: omit native_token_address");
    console.log(
      "For ERC20 gas token chains: provide native_token_address (inbox_address should be ERC20Inbox)"
    );
    process.exit(1);
  }

  const [
    l1RpcUrl,
    l2RpcUrl,
    funnelPrivateKey,
    inboxAddress,
    amount = "10000",
    nativeTokenAddress = "",
  ] = args;

  const isERC20GasToken =
    nativeTokenAddress && nativeTokenAddress !== "" && nativeTokenAddress !== "0x0000000000000000000000000000000000000000";

  if (isERC20GasToken) {
    console.log(`🌉 Bridging ${amount} ERC20 tokens from L1 to L2`);
    console.log(`Native Token: ${nativeTokenAddress}`);
    console.log(`ERC20Inbox: ${inboxAddress}`);
  } else {
    console.log(`🌉 Bridging ${amount} ETH from L1 to L2`);
    console.log(`Inbox: ${inboxAddress}`);
  }
  console.log(`L1 RPC: ${l1RpcUrl}`);
  console.log(`L2 RPC: ${l2RpcUrl}`);

  let l1Provider, l2Provider;
  try {
    // Use StaticJsonRpcProvider to avoid ENS lookups and network auto-detection
    l1Provider = new ethers.providers.StaticJsonRpcProvider(l1RpcUrl);
    l2Provider = new ethers.providers.StaticJsonRpcProvider(l2RpcUrl);

    // Create wallet from funnel private key
    const l1Wallet = new ethers.Wallet(funnelPrivateKey, l1Provider);
    const l2Wallet = new ethers.Wallet(funnelPrivateKey, l2Provider);

    console.log(`Funnel address: ${l1Wallet.address}`);

    // Get L2 balance before bridging
    const l2BalanceBefore = await l2Wallet.getBalance();
    console.log(
      `L2 balance before: ${ethers.utils.formatEther(l2BalanceBefore)}`
    );

    if (isERC20GasToken) {
      await bridgeERC20(
        l1Wallet,
        l2Wallet,
        inboxAddress,
        nativeTokenAddress,
        amount,
        l2BalanceBefore
      );
    } else {
      await bridgeETH(
        l1Wallet,
        l2Wallet,
        inboxAddress,
        amount,
        l2BalanceBefore
      );
    }
  } catch (error) {
    console.error(`❌ Error bridging L1 to L2: ${error.message}`);
    if (error.reason) console.error(`Reason: ${error.reason}`);
    if (error.data) console.error(`Data: ${error.data}`);
    process.exit(1);
  } finally {
    if (l1Provider) l1Provider.removeAllListeners();
    if (l2Provider) l2Provider.removeAllListeners();
  }
}

async function bridgeERC20(
  l1Wallet,
  l2Wallet,
  erc20InboxAddress,
  nativeTokenAddress,
  amount,
  l2BalanceBefore
) {
  console.log("\n📦 ERC20 Gas Token Bridge Flow");

  // Connect to native token contract
  const nativeToken = new ethers.Contract(
    nativeTokenAddress,
    ERC20_ABI,
    l1Wallet
  );

  // Check token balance on L1
  const tokenBalance = await nativeToken.balanceOf(l1Wallet.address);
  console.log(`L1 token balance: ${ethers.utils.formatEther(tokenBalance)}`);

  if (tokenBalance.eq(0)) {
    console.log("❌ Funnel account has no token balance on L1 - cannot bridge");
    process.exit(1);
  }

  const amountWei = ethers.utils.parseEther(amount);
  let amountToUse;

  if (tokenBalance.lt(amountWei)) {
    console.log(
      `⚠️  Not enough token balance. Need ${amount}, have ${ethers.utils.formatEther(tokenBalance)}`
    );
    // Use available balance
    amountToUse = tokenBalance;
    console.log(`Using available balance: ${ethers.utils.formatEther(amountToUse)}`);
  } else {
    amountToUse = amountWei;
  }

  // Step 1: Approve ERC20Inbox to spend tokens
  console.log("\n1️⃣ Approving ERC20Inbox to spend tokens...");
  const currentAllowance = await nativeToken.allowance(
    l1Wallet.address,
    erc20InboxAddress
  );
  console.log(`Current allowance: ${ethers.utils.formatEther(currentAllowance)}`);

  if (currentAllowance.lt(amountToUse)) {
    const approveTx = await nativeToken.approve(erc20InboxAddress, amountToUse);
    console.log(`Approve tx sent: ${approveTx.hash}`);
    await approveTx.wait();
    console.log("✅ Approval confirmed");
  } else {
    console.log("✅ Sufficient allowance already exists");
  }

  // Step 2: Call depositERC20 on ERC20Inbox
  console.log("\n2️⃣ Calling depositERC20 on ERC20Inbox...");
  const erc20Inbox = new ethers.Contract(
    erc20InboxAddress,
    ERC20_INBOX_ABI,
    l1Wallet
  );

  const depositTx = await erc20Inbox.depositERC20(amountToUse, {
    gasLimit: 500000,
  });
  console.log(`Deposit tx sent: ${depositTx.hash}`);

  const receipt = await depositTx.wait();
  console.log(`✅ L1 transaction confirmed in block ${receipt.blockNumber}`);

  // Wait for L2 balance to update
  await waitForL2Balance(l2Wallet, l2BalanceBefore, "tokens");
}

async function bridgeETH(
  l1Wallet,
  l2Wallet,
  inboxAddress,
  amount,
  l2BalanceBefore
) {
  console.log("\n📦 ETH Bridge Flow");

  // Check L1 ETH balance
  const l1Balance = await l1Wallet.getBalance();
  console.log(`L1 ETH balance: ${ethers.utils.formatEther(l1Balance)}`);

  if (l1Balance.eq(0)) {
    console.log("❌ Funnel account has no L1 ETH balance - cannot bridge");
    process.exit(1);
  }

  const amountWei = ethers.utils.parseEther(amount);
  let amountToUse;

  if (l1Balance.lt(amountWei)) {
    console.log(
      `⚠️  Not enough L1 balance. Need ${amount} ETH, have ${ethers.utils.formatEther(l1Balance)} ETH`
    );
    // Reserve some for gas
    const gasEstimate = ethers.utils.parseEther("0.01");
    const availableAmount = l1Balance.sub(gasEstimate);
    if (availableAmount.gt(0)) {
      console.log(`Using available balance: ${ethers.utils.formatEther(availableAmount)} ETH`);
      amountToUse = availableAmount;
    } else {
      console.log("❌ Insufficient balance even for gas");
      process.exit(1);
    }
  } else {
    amountToUse = amountWei;
  }

  // Bridge transaction - depositEth on Inbox
  console.log("\n📤 Calling depositEth on Inbox...");
  const inbox = new ethers.Contract(inboxAddress, INBOX_ABI, l1Wallet);

  const bridgeTx = await inbox.depositEth({
    value: amountToUse,
    gasLimit: 300000,
  });
  console.log(`Transaction sent: ${bridgeTx.hash}`);

  const receipt = await bridgeTx.wait();
  console.log(`✅ L1 transaction confirmed in block ${receipt.blockNumber}`);

  // Wait for L2 balance to update
  await waitForL2Balance(l2Wallet, l2BalanceBefore, "ETH");
}

async function waitForL2Balance(l2Wallet, l2BalanceBefore, unit) {
  console.log(`\n⏳ Waiting for L2 balance to update...`);
  const maxWaitTime = 300; // 5 minutes (retryables can take a while)
  const checkInterval = 5; // 5 seconds

  for (let i = 0; i < maxWaitTime / checkInterval; i++) {
    const l2BalanceAfter = await l2Wallet.getBalance();
    const bridgedAmount = l2BalanceAfter.sub(l2BalanceBefore);

    if (bridgedAmount.gt(0)) {
      console.log(`\n✅ Bridge successful!`);
      console.log(`L2 balance after: ${ethers.utils.formatEther(l2BalanceAfter)} ${unit}`);
      console.log(`Bridged amount: ${ethers.utils.formatEther(bridgedAmount)} ${unit}`);
      return;
    }

    await new Promise((resolve) => setTimeout(resolve, checkInterval * 1000));
    if ((i + 1) % 5 === 0) {
      console.log(`Still waiting... (${(i + 1) * checkInterval}s elapsed)`);
    }
  }

  console.log(
    "\n⚠️  Bridge transaction sent but L2 balance did not update within timeout"
  );
  console.log("This may be normal - the bridge might take longer to process");
}

bridgeL1ToL2();
