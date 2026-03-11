-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil 

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install cyfrin/foundry-devops@0.1.0 && forge install smartcontractkit/chainlink-brownie-contracts@0.6.1 && forge install foundry-rs/forge-std@v1.5.3 && forge install openzeppelin/openzeppelin-contracts@v4.8.3 

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test 

coverage :; forge coverage --report debug > coverage-report.txt

snapshot :; forge snapshot

format :; forge fmt

deploy-gold-token:
	@forge script script/DeployAurumGold.s.sol:DeployAurumGold --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

deploy-ausd:
	@forge script script/DeployAUSD.s.sol:DeployAUSD --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

deploy-aur-faucet:
	@forge script script/DeployAurumGoldFaucet.s.sol:DeployAurumGoldFaucet --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv 