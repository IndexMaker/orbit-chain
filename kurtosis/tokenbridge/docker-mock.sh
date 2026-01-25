#!/bin/bash
# Mock docker script for Kurtosis token-bridge deployment
# Simulates docker commands by reading from mounted config files

# Parse the command
if [[ "$1" == "ps" ]]; then
    # Return a fake container name for sequencer
    if [[ "$*" == *"sequencer"* ]]; then
        echo "sequencer"
    elif [[ "$*" == *"l3node"* ]]; then
        echo ""  # No L3 node
    else
        echo ""
    fi
elif [[ "$1" == "exec" ]]; then
    # Handle docker exec commands
    shift  # Remove 'exec'
    container="$1"
    shift  # Remove container name

    # The rest should be the command (usually 'cat /config/deployment.json')
    if [[ "$*" == *"deployment.json"* ]]; then
        # Read from mounted config
        if [[ -f /config/deployment.json ]]; then
            cat /config/deployment.json
        else
            # Return minimal valid JSON if file doesn't exist
            echo '{"bridge":"","inbox":"","sequencer-inbox":"","rollup":""}'
        fi
    elif [[ "$*" == *"l3deployment.json"* ]]; then
        # No L3 deployment
        echo '{}'
    else
        # Execute the actual command
        eval "$@"
    fi
else
    # For other docker commands, just succeed silently
    exit 0
fi
