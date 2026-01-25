"""
Token bridge deployment module with ERC20 gas token support.
Uses mock docker to read config from mounted files for Kurtosis compatibility.
"""

def deploy_token_bridge(plan, config, l1_info, nodes_info, rollup_info):
    """
    Deploy token bridge between L1 and L2.
    Supports both ETH and custom ERC20 gas token chains.
    """
    use_custom_gas_token = config.get("use_custom_gas_token", False)
    native_token_address = rollup_info.get("native_token_address", "")

    if use_custom_gas_token and native_token_address and native_token_address != "":
        plan.print("Deploying token bridge for ERC20 gas token chain...")
        plan.print("Native token address: {}".format(native_token_address))
    else:
        plan.print("Deploying token bridge for ETH gas token chain...")

    # Build environment variables
    env_vars = {
        "ROLLUP_OWNER_KEY": "0x" + config["owner_private_key"],
        "ROLLUP_ADDRESS": rollup_info["rollup_address"],
        "PARENT_KEY": "0x" + config["owner_private_key"],
        "PARENT_RPC": l1_info["rpc_url"],
        "CHILD_KEY": "0x" + config["owner_private_key"],
        "CHILD_RPC": nodes_info["sequencer"]["rpc_url"],
    }

    # Add native token address for custom gas token chains
    if use_custom_gas_token and native_token_address and native_token_address != "":
        env_vars["NATIVE_TOKEN"] = native_token_address
        env_vars["NATIVE_TOKEN_ADDRESS"] = native_token_address

    deploy_cmd = (
        "echo 'Starting token bridge deployment...' && " +
        "echo 'Environment variables:' && " +
        "env | grep -E '(PARENT_RPC|CHILD_RPC|ROLLUP_ADDRESS|NATIVE_TOKEN)' && " +
        "echo 'Config file:' && cat /config/deployment.json && " +
        "echo 'Running yarn deploy:local:token-bridge...' && " +
        "if ! yarn deploy:local:token-bridge; then " +
        "    echo 'Token bridge deployment failed!' && " +
        "    exit 1; " +
        "fi && " +
        "if [ ! -f /workspace/network.json ]; then " +
        "    echo 'network.json not found after deployment!' && " +
        "    ls -la /workspace/ && " +
        "    exit 1; " +
        "fi && " +
        "echo 'Token bridge deployment completed successfully' && " +
        "echo 'Created network.json:' && " +
        "cat /workspace/network.json && " +
        "tail -f /dev/null"
    )

    # Deploy bridge contracts - mount the rollup deployment config
    bridge_deployer = plan.add_service(
        name="token-bridge-deployer",
        config=ServiceConfig(
            image=ImageBuildSpec(
                image_name="tokenbridge",
                build_context_dir="./tokenbridge",
                build_args={
                    "TOKEN_BRIDGE_BRANCH": config.get("token_bridge_branch", "v1.2.5")
                }
            ),
            cmd=["sh", "-c", deploy_cmd],
            env_vars=env_vars,
            files={
                "/config": rollup_info["artifacts"]["deployment"],
            },
        ),
    )

    # Wait for the deployment to complete by checking for network.json file
    plan.wait(
        service_name="token-bridge-deployer",
        recipe=ExecRecipe(
            command=["sh", "-c", "if [ -f /workspace/network.json ]; then echo 'Success: network.json found'; exit 0; else echo 'network.json not found, listing workspace:'; ls -la /workspace/; exit 1; fi"]
        ),
        field="code",
        assertion="==",
        target_value=0,
        timeout="15m",
        interval="10s"
    )

    # Copy the network configuration files
    plan.exec(
        service_name="token-bridge-deployer",
        recipe=ExecRecipe(
            command=["sh", "-c", "cp /workspace/network.json /workspace/l1l2_network.json && cp /workspace/network.json /workspace/localNetwork.json"]
        )
    )

    # Store network configuration
    network_artifact = plan.store_service_files(
        service_name="token-bridge-deployer",
        src="/workspace/network.json",
        name="token-bridge-network",
    )

    # Extract bridge addresses
    l1_gateway = plan.exec(
        service_name="token-bridge-deployer",
        recipe=ExecRecipe(
            command=["sh", "-c", "cat /workspace/network.json | jq -r '.l2Network.tokenBridge.l1ERC20Gateway'"]
        ),
    )["output"].strip()

    l1_router = plan.exec(
        service_name="token-bridge-deployer",
        recipe=ExecRecipe(
            command=["sh", "-c", "cat /workspace/network.json | jq -r '.l2Network.tokenBridge.l1GatewayRouter'"]
        ),
    )["output"].strip()

    l2_gateway = plan.exec(
        service_name="token-bridge-deployer",
        recipe=ExecRecipe(
            command=["sh", "-c", "cat /workspace/network.json | jq -r '.l2Network.tokenBridge.l2ERC20Gateway'"]
        ),
    )["output"].strip()

    l2_router = plan.exec(
        service_name="token-bridge-deployer",
        recipe=ExecRecipe(
            command=["sh", "-c", "cat /workspace/network.json | jq -r '.l2Network.tokenBridge.l2GatewayRouter'"]
        ),
    )["output"].strip()

    plan.print("✅ Token bridge deployed successfully!")

    return {
        "artifacts": {
            "network": network_artifact,
        },
        "l1": {
            "gateway": l1_gateway,
            "router": l1_router,
        },
        "l2": {
            "gateway": l2_gateway,
            "router": l2_router,
        },
    }
