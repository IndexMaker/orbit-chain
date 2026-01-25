FROM node:18-bullseye-slim

# Install necessary dependencies including jq for JSON processing
RUN apt-get update && \
    apt-get install -y git python3 make gcc g++ curl jq && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set token bridge version - v1.2.5 has native token support
ARG TOKEN_BRIDGE_BRANCH=v1.2.5

# Install Foundry (required for token bridge contracts)
RUN curl -L https://foundry.paradigm.xyz | bash
ENV PATH="${PATH}:/root/.foundry/bin"
RUN foundryup --install 1.0.0

# Set working directory
WORKDIR /workspace

# Clone the token bridge repository and checkout the specified branch
RUN git clone --no-checkout https://github.com/OffchainLabs/token-bridge-contracts.git ./ && \
    git checkout ${TOKEN_BRIDGE_BRANCH}

# Install dependencies and build
RUN yarn install && yarn cache clean
RUN yarn build

# Create a mock docker command that returns empty (so the script falls back to rollup address)
RUN echo '#!/bin/sh\necho ""' > /usr/local/bin/docker && chmod +x /usr/local/bin/docker
