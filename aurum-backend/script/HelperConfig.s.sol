// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";


contract HelperConfig is Script {
    struct NetworkConfig {
        address goldUsdPriceFeed;
        address aurumGold;
        uint256 deployerKey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant GOLD_USD_PRICE = 5000e8;
    uint256 public constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public activeNetworkConfig;


    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        }
        else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }


    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            goldUsdPriceFeed: 0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea,       //Chainlink XAU/USD price feed
            aurumGold: 0x7769F56edC2a1882a51cec1d3c96F31482b5A241,              // Simple deployed gold token address
            deployerKey: vm.envUint("PRIVATE_KEY")                      
        });
    }


    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.goldUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator goldUsdPriceFeed = new MockV3Aggregator(DECIMALS, GOLD_USD_PRICE);
        ERC20Mock aurumGoldMock = new ERC20Mock();
        vm.stopBroadcast();

        return NetworkConfig({
            goldUsdPriceFeed: address(goldUsdPriceFeed),
            aurumGold: address(aurumGoldMock),
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }
}