"""
Rollup contract deployment module with custom gas token support.
Uses cast send for reliable token deployment.
"""

def deploy_rollup_contracts(plan, config, l1_info):
    """
    Deploy Arbitrum Orbit rollup contracts on L1.
    Supports both ETH and custom ERC20 as native gas token.
    """
    use_custom_gas_token = config.get("use_custom_gas_token", False)

    if use_custom_gas_token:
        plan.print("Deploying rollup with CUSTOM GAS TOKEN (ERC20)")
        if config.get("native_token") and config["native_token"] != "":
            plan.print("Using existing token: {}".format(config["native_token"]))
        else:
            plan.print("Will deploy new IND token")
    else:
        plan.print("Deploying rollup with ETH as native gas token")

    plan.print("Preparing rollup deployment configuration...")

    # Create L2 chain configuration
    l2_chain_config = {
        "chainId": config["chain_id"],
        "homesteadBlock": 0,
        "daoForkSupport": True,
        "eip150Block": 0,
        "eip150Hash": "0x0000000000000000000000000000000000000000000000000000000000000000",
        "eip155Block": 0,
        "eip158Block": 0,
        "byzantiumBlock": 0,
        "constantinopleBlock": 0,
        "petersburgBlock": 0,
        "istanbulBlock": 0,
        "muirGlacierBlock": 0,
        "berlinBlock": 0,
        "londonBlock": 0,
        "clique": {
            "period": 0,
            "epoch": 0
        },
        "arbitrum": {
            "EnableArbOS": True,
            "AllowDebugPrecompiles": True,
            "DataAvailabilityCommittee": not config["rollup_mode"],
            "InitialArbOSVersion": 32,
            "InitialChainOwner": config["owner_address"],
            "GenesisBlockNum": 0
        }
    }

    # Create rollup configuration
    rollup_config = {
        "chainId": config["chain_id"],
        "chainName": config["chain_name"],
        "parentChainId": config["l1_chain_id"],
        "maxDataSize": 117964,
        "challengePeriodBlocks": config["challenge_period_blocks"],
        "stakeToken": config["stake_token"],
        "baseStake": config["base_stake"],
        "ownerAddress": config["owner_address"],
        "sequencerAddress": config["sequencer_address"],
        "dataAvailabilityMode": "rollup" if config["rollup_mode"] else "anytrust"
    }

    # Create config artifacts
    config_artifact = plan.render_templates(
        name="rollup-config",
        config={
            "rollup_config.json": struct(
                template=json.encode(rollup_config),
                data={},
            ),
            "l2_chain_config.json": struct(
                template=json.encode(l2_chain_config),
                data={},
            ),
        },
    )

    # Extract WASM module root
    wasm_root_result = plan.run_sh(
        run="cat /home/user/target/machines/latest/module-root.txt | tr -d '\\n'",
        image=config["nitro_image"],
    )
    wasm_module_root = wasm_root_result.output.strip()
    plan.print("WASM module root: {}".format(wasm_module_root))

    # Build environment variables
    env_vars = {
        "PARENT_CHAIN_RPC": l1_info["rpc_url"],
        "DEPLOYER_PRIVKEY": config["owner_private_key"],
        "PARENT_CHAIN_ID": str(config["l1_chain_id"]),
        "CHILD_CHAIN_NAME": config["chain_name"],
        "MAX_DATA_SIZE": "117964",
        "OWNER_ADDRESS": config["owner_address"],
        "SEQUENCER_ADDRESS": config["sequencer_address"],
        "AUTHORIZE_VALIDATORS": "10",
        "CHILD_CHAIN_CONFIG_PATH": "/config/l2_chain_config.json",
        "CHAIN_DEPLOYMENT_INFO": "/config/deployment.json",
        "CHILD_CHAIN_INFO": "/config/chain_info.json",
        "WASM_MODULE_ROOT": wasm_module_root,
    }

    # IND Token bytecode (compiled OpenZeppelin ERC20 with 1B supply)
    ind_token_bytecode = "0x608060405234801561000f575f5ffd5b506040518060400160405280600981526020016824a722102a37b5b2b760b91b8152506040518060400160405280600381526020016212539160ea1b815250816003908161005d919061020a565b50600461006a828261020a565b505050610089336b033b2e3c9fd0803ce800000061008e60201b60201c565b6102e9565b6001600160a01b0382166100e85760405162461bcd60e51b815260206004820152601f60248201527f45524332303a206d696e7420746f20746865207a65726f206164647265737300604482015260640160405180910390fd5b8060025f8282546100f991906102c4565b90915550506001600160a01b0382165f90815260208190526040812080548392906101259084906102c4565b90915550506040518181526001600160a01b038316905f907fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef9060200160405180910390a35050565b505050565b634e487b7160e01b5f52604160045260245ffd5b600181811c9082168061019b57607f821691505b6020821081036101b957634e487b7160e01b5f52602260045260245ffd5b50919050565b601f82111561016e57805f5260205f20601f840160051c810160208510156101e45750805b601f840160051c820191505b81811015610203575f81556001016101f0565b5050505050565b81516001600160401b0381111561022357610223610173565b610237816102318454610187565b846101bf565b6020601f821160018114610269575f83156102525750848201515b5f19600385901b1c1916600184901b178455610203565b5f84815260208120601f198516915b828110156102985787850151825560209485019460019092019101610278565b50848210156102b557868401515f19600387901b60f8161c191681555b50505050600190811b01905550565b808201808211156102e357634e487b7160e01b5f52601160045260245ffd5b92915050565b610878806102f65f395ff3fe608060405234801561000f575f5ffd5b50600436106100a6575f3560e01c8063395093511161006e578063395093511461011f57806370a082311461013257806395d89b411461015a578063a457c2d714610162578063a9059cbb14610175578063dd62ed3e14610188575f5ffd5b806306fdde03146100aa578063095ea7b3146100c857806318160ddd146100eb57806323b872dd146100fd578063313ce56714610110575b5f5ffd5b6100b261019b565b6040516100bf91906106e8565b60405180910390f35b6100db6100d6366004610738565b61022b565b60405190151581526020016100bf565b6002545b6040519081526020016100bf565b6100db61010b366004610760565b610244565b604051601281526020016100bf565b6100db61012d366004610738565b610267565b6100ef61014036600461079a565b6001600160a01b03165f9081526020819052604090205490565b6100b26102a5565b6100db610170366004610738565b6102b4565b6100db610183366004610738565b61034a565b6100ef6101963660046107ba565b610357565b6060600380546101aa906107eb565b80601f01602080910402602001604051908101604052809291908181526020018280546101d6906107eb565b80156102215780601f106101f857610100808354040283529160200191610221565b820191905f5260205f20905b81548152906001019060200180831161020457829003601f168201915b5050505050905090565b5f33610238818585610381565b60019150505b92915050565b5f336102518582856104a4565b61025c85858561051c565b506001949350505050565b335f8181526001602090815260408083206001600160a01b038716845290915281205490919061023890829086906102a0908790610823565b610381565b6060600480546101aa906107eb565b335f8181526001602090815260408083206001600160a01b03871684529091528120549091908381101561033d5760405162461bcd60e51b815260206004820152602560248201527f45524332303a2064656372656173656420616c6c6f77616e63652062656c6f77604482015264207a65726f60d81b60648201526084015b60405180910390fd5b61025c8286868403610381565b5f3361023881858561051c565b6001600160a01b039182165f90815260016020908152604080832093909416825291909152205490565b6001600160a01b0383166103e35760405162461bcd60e51b8152602060048201526024808201527f45524332303a20617070726f76652066726f6d20746865207a65726f206164646044820152637265737360e01b6064820152608401610334565b6001600160a01b0382166104445760405162461bcd60e51b815260206004820152602260248201527f45524332303a20617070726f766520746f20746865207a65726f206164647265604482015261737360f01b6064820152608401610334565b6001600160a01b038381165f8181526001602090815260408083209487168084529482529182902085905590518481527f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925910160405180910390a3505050565b5f6104af8484610357565b90505f19811461051657818110156105095760405162461bcd60e51b815260206004820152601d60248201527f45524332303a20696e73756666696369656e7420616c6c6f77616e63650000006044820152606401610334565b6105168484848403610381565b50505050565b6001600160a01b0383166105805760405162461bcd60e51b815260206004820152602560248201527f45524332303a207472616e736665722066726f6d20746865207a65726f206164604482015264647265737360d81b6064820152608401610334565b6001600160a01b0382166105e25760405162461bcd60e51b815260206004820152602360248201527f45524332303a207472616e7366657220746f20746865207a65726f206164647260448201526265737360e81b6064820152608401610334565b6001600160a01b0383165f90815260208190526040902054818110156106595760405162461bcd60e51b815260206004820152602660248201527f45524332303a207472616e7366657220616d6f756e7420657863656564732062604482015265616c616e636560d01b6064820152608401610334565b6001600160a01b038085165f9081526020819052604080822085850390559185168152908120805484929061068f908490610823565b92505081905550826001600160a01b0316846001600160a01b03167fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef846040516106db91815260200190565b60405180910390a3610516565b602081525f82518060208401528060208501604085015e5f604082850101526040601f19601f83011684010191505092915050565b80356001600160a01b0381168114610733575f5ffd5b919050565b5f5f60408385031215610749575f5ffd5b6107528361071d565b946020939093013593505050565b5f5f5f60608486031215610772575f5ffd5b61077b8461071d565b92506107896020850161071d565b929592945050506040919091013590565b5f602082840312156107aa575f5ffd5b6107b38261071d565b9392505050565b5f5f604083850312156107cb575f5ffd5b6107d48361071d565b91506107e26020840161071d565b90509250929050565b600181811c908216806107ff57607f821691505b60208210810361081d57634e487b7160e01b5f52602260045260245ffd5b50919050565b8082018082111561023e57634e487b7160e01b5f52601160045260245ffdfea2646970667358221220cce59bbabc29d30393fc752e05f4f3d87cad0481798e0a2b0c0f36fbf47d2bbc64736f6c634300081c0033"

    # Build the deployment command
    if use_custom_gas_token and (not config.get("native_token") or config["native_token"] == ""):
        # Deploy new IND token first using cast send, then create rollup
        deploy_cmd = "apt-get update && apt-get install -y curl && " + \
            "echo 'Waiting for L1 node...' && " + \
            "count=0 && " + \
            "while [ $count -lt 30 ]; do " + \
            "response=$(curl -s -X POST -H 'Content-Type: application/json' " + \
            "--data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' " + \
            "$PARENT_CHAIN_RPC) && " + \
            "if echo \"$response\" | grep -q 'result'; then " + \
            "echo 'L1 node is responding' && " + \
            "break; " + \
            "fi && " + \
            "echo 'Waiting for L1 node to respond...' && " + \
            "sleep 2 && " + \
            "count=$((count+1)); " + \
            "done && " + \
            "echo 'Waiting for L1 to mine blocks...' && " + \
            "sleep 15 && " + \
            "count=0 && " + \
            "while [ $count -lt 30 ]; do " + \
            "block_response=$(curl -s -X POST -H 'Content-Type: application/json' " + \
            "--data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' " + \
            "$PARENT_CHAIN_RPC) && " + \
            "if [ \"$?\" -eq 0 ] && echo \"$block_response\" | grep -q '\"result\":\"0x[1-9a-f]'; then " + \
            "echo 'L1 has mined blocks beyond genesis' && " + \
            "break; " + \
            "fi && " + \
            "echo 'Waiting for L1 to mine blocks...' && " + \
            "sleep 2 && " + \
            "count=$((count+1)); " + \
            "done && " + \
            "echo 'Deploying IND Token on L1...' && " + \
            "DEPLOY_RESULT=$(cast send --private-key $DEPLOYER_PRIVKEY --rpc-url $PARENT_CHAIN_RPC --create " + ind_token_bytecode + " --json 2>&1) && " + \
            "export FEE_TOKEN_ADDRESS=$(echo $DEPLOY_RESULT | jq -r '.contractAddress') && " + \
            "echo 'IND Token deployed at: '$FEE_TOKEN_ADDRESS && " + \
            "mkdir -p /config && " + \
            "echo '{\"nativeToken\": \"'$FEE_TOKEN_ADDRESS'\"}' > /config/native_token.json && " + \
            "cp /rollup/rollup_config.json /config/ && cp /rollup/l2_chain_config.json /config/ && " + \
            "yarn create-rollup-testnode && " + \
            "echo 'Deployment complete!' && " + \
            "ls -l /config/*.json && " + \
            "tail -f /dev/null"
    elif use_custom_gas_token:
        # Use existing token address
        env_vars["FEE_TOKEN_ADDRESS"] = config["native_token"]
        deploy_cmd = "apt-get update && apt-get install -y curl && " + \
            "echo 'Waiting for L1 node...' && " + \
            "count=0 && " + \
            "while [ $count -lt 30 ]; do " + \
            "response=$(curl -s -X POST -H 'Content-Type: application/json' " + \
            "--data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' " + \
            "$PARENT_CHAIN_RPC) && " + \
            "if echo \"$response\" | grep -q 'result'; then " + \
            "echo 'L1 node is responding' && " + \
            "break; " + \
            "fi && " + \
            "echo 'Waiting for L1 node to respond...' && " + \
            "sleep 2 && " + \
            "count=$((count+1)); " + \
            "done && " + \
            "echo 'Waiting for L1 to mine blocks...' && " + \
            "sleep 15 && " + \
            "count=0 && " + \
            "while [ $count -lt 30 ]; do " + \
            "block_response=$(curl -s -X POST -H 'Content-Type: application/json' " + \
            "--data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' " + \
            "$PARENT_CHAIN_RPC) && " + \
            "if [ \"$?\" -eq 0 ] && echo \"$block_response\" | grep -q '\"result\":\"0x[1-9a-f]'; then " + \
            "echo 'L1 has mined blocks beyond genesis' && " + \
            "break; " + \
            "fi && " + \
            "echo 'Waiting for L1 to mine blocks...' && " + \
            "sleep 2 && " + \
            "count=$((count+1)); " + \
            "done && " + \
            "echo 'Using existing token: '$FEE_TOKEN_ADDRESS && " + \
            "mkdir -p /config && cp /rollup/rollup_config.json /config/ && cp /rollup/l2_chain_config.json /config/ && " + \
            "yarn create-rollup-testnode && " + \
            "echo 'Deployment complete!' && " + \
            "ls -l /config/*.json && " + \
            "tail -f /dev/null"
    else:
        # Standard ETH gas token deployment
        deploy_cmd = "apt-get update && apt-get install -y curl && " + \
            "echo 'Waiting for L1 node...' && " + \
            "count=0 && " + \
            "while [ $count -lt 30 ]; do " + \
            "response=$(curl -s -X POST -H 'Content-Type: application/json' " + \
            "--data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' " + \
            "$PARENT_CHAIN_RPC) && " + \
            "if echo \"$response\" | grep -q 'result'; then " + \
            "echo 'L1 node is responding' && " + \
            "break; " + \
            "fi && " + \
            "echo 'Waiting for L1 node to respond...' && " + \
            "sleep 2 && " + \
            "count=$((count+1)); " + \
            "done && " + \
            "echo 'Waiting for L1 to mine blocks...' && " + \
            "sleep 15 && " + \
            "count=0 && " + \
            "while [ $count -lt 30 ]; do " + \
            "block_response=$(curl -s -X POST -H 'Content-Type: application/json' " + \
            "--data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' " + \
            "$PARENT_CHAIN_RPC) && " + \
            "if [ \"$?\" -eq 0 ] && echo \"$block_response\" | grep -q '\"result\":\"0x[1-9a-f]'; then " + \
            "echo 'L1 has mined blocks beyond genesis' && " + \
            "break; " + \
            "fi && " + \
            "echo 'Waiting for L1 to mine blocks...' && " + \
            "sleep 2 && " + \
            "count=$((count+1)); " + \
            "done && " + \
            "echo 'Proceeding with ETH gas token deployment' && " + \
            "mkdir -p /config && cp /rollup/rollup_config.json /config/ && cp /rollup/l2_chain_config.json /config/ && " + \
            "yarn create-rollup-testnode && " + \
            "echo 'Deployment complete!' && " + \
            "ls -l /config/*.json && " + \
            "tail -f /dev/null"

    # Deploy rollup contracts
    deployer_service = plan.add_service(
        name="orbit-deployer",
        config=ServiceConfig(
            image=ImageBuildSpec(
                image_name="rollupcreator",
                build_context_dir="./rollupcreator",
                build_args={
                    "NITRO_CONTRACTS_BRANCH": config["nitro_contracts_branch"]
                }
            ),
            cmd=["sh", "-c", deploy_cmd],
            files={
                "/rollup": config_artifact,
            },
            env_vars=env_vars,
        ),
    )

    # Wait for deployment to complete
    plan.wait(
        service_name="orbit-deployer",
        recipe=ExecRecipe(
            command=["test", "-f", "/config/chain_info.json"]
        ),
        field="code",
        assertion="==",
        target_value=0,
        timeout="15m",
        interval="5s"
    )

    # Store deployment artifacts
    deployment_artifact = plan.store_service_files(
        service_name="orbit-deployer",
        src="/config/deployment.json",
        name="deployment-info",
    )

    chain_info_artifact = plan.store_service_files(
        service_name="orbit-deployer",
        src="/config/chain_info.json",
        name="chain-info",
    )

    # Extract key addresses
    rollup_address = plan.exec(
        service_name="orbit-deployer",
        recipe=ExecRecipe(
            command=["sh", "-c", "cat /config/deployment.json | jq -r '.rollup' | tr -d '\\n'"]
        ),
    )["output"].strip()

    bridge_address = plan.exec(
        service_name="orbit-deployer",
        recipe=ExecRecipe(
            command=["sh", "-c", "cat /config/deployment.json | jq -r '.bridge' | tr -d '\\n'"]
        ),
    )["output"].strip()

    inbox_address = plan.exec(
        service_name="orbit-deployer",
        recipe=ExecRecipe(
            command=["sh", "-c", "cat /config/deployment.json | jq -r '.inbox' | tr -d '\\n'"]
        ),
    )["output"].strip()

    sequencer_inbox_address = plan.exec(
        service_name="orbit-deployer",
        recipe=ExecRecipe(
            command=["sh", "-c", "cat /config/deployment.json | jq -r '.\"sequencer-inbox\"' | tr -d '\\n'"]
        ),
    )["output"].strip()

    # Extract native token address if deployed
    native_token_address = ""
    if use_custom_gas_token:
        native_token_result = plan.exec(
            service_name="orbit-deployer",
            recipe=ExecRecipe(
                command=["sh", "-c", "cat /config/native_token.json 2>/dev/null | jq -r '.nativeToken' || cat /config/deployment.json | jq -r '.\"native-token\" // .nativeToken // .feeToken // \"\"' | tr -d '\\n'"]
            ),
        )
        native_token_address = native_token_result["output"].strip()
        if native_token_address and native_token_address != "" and native_token_address != "null":
            plan.print("Native Token (IND) Address: {}".format(native_token_address))

    plan.print("Rollup contracts deployed successfully!")
    plan.print("Rollup address: {}".format(rollup_address))

    return {
        "artifacts": {
            "deployment": deployment_artifact,
            "chain_info": chain_info_artifact,
        },
        "rollup_address": rollup_address,
        "bridge_address": bridge_address,
        "inbox_address": inbox_address,
        "sequencer_inbox_address": sequencer_inbox_address,
        "owner_address": config["owner_address"],
        "sequencer_address": config["sequencer_address"],
        "native_token_address": native_token_address,
    }
