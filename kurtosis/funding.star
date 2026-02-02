"""
L2 account funding module using a dedicated Node.js container.
"""

config_module = import_module("./config.star")

def deploy_l2_funding(plan, config, l2_info):
    """
    Deploy L2 funding service with proper service patterns.
    """
    # Upload funding scripts as artifact
    funding_scripts = plan.upload_files(
        src="./scripts/",
        name="funding-scripts"
    )
    
    # Deploy funding service with proper ready conditions
    funding_service = plan.add_service(
        name="l2-funding",
        config=ServiceConfig(
            image="node:20-bookworm-slim",
            cmd=[
                "sh", "-c", 
                "cd /workspace && npm install && tail -f /dev/null"
            ],
            files={
                "/workspace": funding_scripts,
            },
            ready_conditions=ReadyCondition(
                recipe=ExecRecipe(
                    command=["test", "-d", "/workspace/node_modules"]
                ),
                field="code",
                assertion="==",
                target_value=0,
                timeout="5m",
                interval="10s"
            ),
        ),
    )
    
    plan.print("✅ L2 funding service deployed!")
    
    return {
        "service": funding_service,
    }

def fund_l2_accounts(plan, config, l1_info, l2_info, rollup_info):
    """
    Fund L2 accounts using structured funding approach.
    """
    # Prepare funding configuration
    funding_config = _prepare_funding_config(config)

    if len(funding_config["accounts"]) == 0:
        plan.print("No accounts require L2 funding")
        return {"funded_accounts": 0}

    # For ERC20 gas token chains, first transfer tokens from deployer to funnel
    use_custom_gas_token = rollup_info.get("use_custom_gas_token", False)
    if use_custom_gas_token:
        _execute_token_distribution(plan, config, l1_info, rollup_info, funding_config)

    # Execute funding phases
    _execute_bridge_funding(plan, funding_config, l1_info, l2_info, rollup_info)
    _execute_account_funding(plan, funding_config, l2_info)

    return {"funded_accounts": len(funding_config["accounts"])}

def _prepare_funding_config(config):
    """Prepare funding configuration with validation."""
    all_accounts = config_module.get_all_prefunded_accounts(config)
    funnel_key = config_module.STANDARD_ACCOUNTS["funnel"]["private_key"]
    funnel_address = config_module.STANDARD_ACCOUNTS["funnel"]["address"]

    accounts_list = []
    for addr, info in all_accounts.items():
        if info["name"] != "funnel" and float(info["balance_l2"]) > 0:
            accounts_list.append({
                "name": info["name"],
                "address": addr,
                "amount": str(info["balance_l2"])
            })

    return {
        "accounts": accounts_list,
        "funnel_key": funnel_key,
        "funnel_address": funnel_address
    }


def _execute_token_distribution(plan, config, l1_info, rollup_info, funding_config):
    """Transfer native tokens from deployer to funnel on L1 (for ERC20 gas token chains)."""
    native_token_address = rollup_info.get("native_token_address", "")
    if not native_token_address or native_token_address == "":
        plan.print("Warning: Native token address not available, skipping token distribution")
        return

    # Calculate total needed for bridging (with buffer)
    total_needed = 0
    for acc in funding_config["accounts"]:
        total_needed += float(acc["amount"])
    transfer_amount = str(int(total_needed * 1.5))  # 50% buffer

    plan.print("Distributing {} IND tokens from deployer to funnel on L1".format(transfer_amount))

    # Get deployer (l2owner) private key
    deployer_key = config["owner_private_key"]
    funnel_address = funding_config["funnel_address"]

    # Execute token transfer
    plan.exec(
        service_name="l2-funding",
        recipe=ExecRecipe(
            command=[
                "node", "/workspace/transfer-erc20.js",
                l1_info["rpc_url"],
                deployer_key,
                native_token_address,
                funnel_address,
                transfer_amount
            ]
        )
    )

def _execute_bridge_funding(plan, funding_config, l1_info, l2_info, rollup_info):
    """Execute bridge funding phase. Supports both ETH and ERC20 gas token chains."""
    use_custom_gas_token = rollup_info.get("use_custom_gas_token", False)
    native_token_address = rollup_info.get("native_token_address", "")

    # Determine which inbox to use
    if use_custom_gas_token:
        # For ERC20 gas token chains, use ERC20Inbox (which is stored in inbox_address)
        inbox_address = rollup_info.get("erc20_inbox_address", "") or rollup_info.get("inbox_address", "")
        if not inbox_address or inbox_address == "":
            plan.print("Warning: ERC20Inbox address not available, skipping bridge funding")
            return
        if not native_token_address or native_token_address == "":
            plan.print("Warning: Native token address not available, skipping bridge funding")
            return
    else:
        inbox_address = rollup_info.get("inbox_address", "")
        if not inbox_address or inbox_address == "":
            plan.print("Warning: Inbox address not available, skipping bridge funding")
            return

    # Calculate bridge amount
    total_needed = 0
    for acc in funding_config["accounts"]:
        total_needed += float(acc["amount"])
    bridge_amount = str(int(total_needed * 1.2))  # 20% buffer

    if use_custom_gas_token:
        plan.print("Bridging {} IND tokens from L1 to L2 via ERC20Inbox".format(bridge_amount))
        plan.print("Native Token: {}".format(native_token_address))
        plan.print("ERC20Inbox: {}".format(inbox_address))
    else:
        plan.print("Bridging {} ETH from L1 to L2".format(bridge_amount))

    # Build command args - add native token address for ERC20 chains
    bridge_args = [
        "node", "/workspace/bridge-l1-to-l2.js",
        l1_info["rpc_url"],
        l2_info["sequencer"]["rpc_url"],
        funding_config["funnel_key"],
        inbox_address,
        bridge_amount
    ]

    # Add native token address for ERC20 gas token chains
    if use_custom_gas_token and native_token_address and native_token_address != "":
        bridge_args.append(native_token_address)

    # Execute bridge operation
    plan.exec(
        service_name="l2-funding",
        recipe=ExecRecipe(
            command=bridge_args
        )
    )

def _execute_account_funding(plan, funding_config, l2_info):
    """Execute L2 account funding phase."""
    # Create funding configuration using heredoc approach
    plan.exec(
        service_name="l2-funding",
        recipe=ExecRecipe(
            command=[
                "sh", "-c", 
                "cat > /workspace/accounts.json << 'EOF'\n{}\nEOF".format(
                    json.encode(funding_config["accounts"])
                )
            ]
        )
    )
    
    # Execute funding with proper error handling
    plan.exec(
        service_name="l2-funding",
        recipe=ExecRecipe(
            command=[
                "node", "/workspace/fund-all.js",
                l2_info["sequencer"]["rpc_url"],
                funding_config["funnel_key"],
                "/workspace/accounts.json"
            ]
        )
    )
    
    # Verify funding results
    plan.exec(
        service_name="l2-funding",
        recipe=ExecRecipe(
            command=[
                "node", "/workspace/check-balances.js",
                l2_info["sequencer"]["rpc_url"],
                "accounts.json"
            ]
        )
    ) 