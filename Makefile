.PHONY: fork deploy-local test build clean install help

# Default target
help:
	@echo "Titan Contracts - Available Commands:"
	@echo ""
	@echo "  make fork          - Start Anvil with Base mainnet fork"
	@echo "  make deploy-local  - Deploy all contracts to local fork"
	@echo "  make test          - Run all tests"
	@echo "  make build         - Build all contracts"
	@echo "  make clean         - Clean build artifacts"
	@echo "  make install       - Install dependencies"
	@echo ""

# Start Anvil with Base mainnet fork
fork:
	@echo "Starting Anvil with Base mainnet fork..."
	anvil --fork-url https://mainnet.base.org --chain-id 8453 --block-time 2

# Deploy contracts to local fork
deploy-local:
	@echo "Deploying contracts to local fork..."
	@mkdir -p deployments
	forge script script/DeployLocal.s.sol:DeployLocal --rpc-url http://127.0.0.1:8545 --broadcast -vvv

# Run tests
test:
	forge test -vvv

# Build contracts
build:
	forge build

# Clean build artifacts
clean:
	forge clean
	rm -rf cache out

# Install dependencies
install:
	forge install
	npm install
