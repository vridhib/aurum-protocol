-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil 

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install smartcontractkit/chainlink-brownie-contracts@0.6.1 && forge install foundry-rs/forge-std@v1.5.3 && forge install openzeppelin/openzeppelin-contracts@v4.8.3 

# Update Dependencies
update:; forge update

build:; forge build --via-ir

test :; forge test --via-ir

snapshot :; forge snapshot

format :; forge fmt

deploy-ausd:
	@forge script script/DeployAUSD.s.sol:DeployAUSD --via-ir --rpc-url $(SEPOLIA_RPC_URL) --account sepolia-deployer --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv