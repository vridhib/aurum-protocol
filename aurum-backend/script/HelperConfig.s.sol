// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";


contract HelperConfig is Script {
    struct NetworkConfig {
        address goldUsdPriceFeed;
        address aurumGold;
        address deployerAccount;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant GOLD_USD_PRICE = 5000e8;
    address constant ANVIL_DEFAULT_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    NetworkConfig public activeNetworkConfig;


    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }


    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        address sepoliaDeployerAccount = vm.envAddress("SEPOLIA_DEPLOYER_ACCOUNT");

        return NetworkConfig({
            goldUsdPriceFeed: 0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea,       // Chainlink XAU/USD price feed
            aurumGold: 0x7769F56edC2a1882a51cec1d3c96F31482b5A241,              // Simple deployed gold token address
            deployerAccount: sepoliaDeployerAccount                            // Deploying account address                
        });
    }


    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.goldUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        // Deploy mocks 
        vm.startBroadcast();
        MockV3Aggregator goldUsdPriceFeed = new MockV3Aggregator(DECIMALS, GOLD_USD_PRICE);
        ERC20Mock aurumGoldMock = new ERC20Mock();
        vm.stopBroadcast();

        return NetworkConfig({
            goldUsdPriceFeed: address(goldUsdPriceFeed),
            aurumGold: address(aurumGoldMock),
            deployerAccount: ANVIL_DEFAULT_ACCOUNT
        });
    }
}