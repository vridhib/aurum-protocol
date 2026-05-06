// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {MockVolatilityOracle} from "../src/oracles/MockVolatilityOracle.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";


contract HelperConfig is Script {
    struct CollateralConfig {
        address token;
        address priceFeed;
        address volatilityFeed;
        uint256 baselineVolatility;
        uint256 baseLtv;
        uint256 minLtv;
        uint256 debtCeiling;
        uint256 minCloseFactor;
        uint256 maxCloseFactor;
    }

    struct NetworkConfig {
        CollateralConfig[] collaterals;
        address deployerAccount;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant GOLD_USD_PRICE = 5000e8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    uint256 public constant INITIAL_GOLD_VOLATILITY = 0.15e18;
    uint256 public constant INITIAL_ETH_VOLATILITY = 0.60e18;
    address constant ANVIL_DEFAULT_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    NetworkConfig private activeNetworkConfig;


    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }


    function getSepoliaEthConfig() public returns (NetworkConfig memory) {
        address sepoliaDeployerAccount = vm.envAddress("SEPOLIA_DEPLOYER_ACCOUNT");

        vm.startBroadcast(sepoliaDeployerAccount);
        MockVolatilityOracle goldVolatilityFeed = new MockVolatilityOracle(INITIAL_GOLD_VOLATILITY);
        vm.stopBroadcast();

        CollateralConfig[] memory collaterals = new CollateralConfig[](2);
        collaterals[0] = CollateralConfig({                               // Gold collateral config
            token: 0x7769F56edC2a1882a51cec1d3c96F31482b5A241,            // Deployed AurumGold token address
            priceFeed: 0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea,        // Chainlink XAU/USD price feed
            volatilityFeed: address(goldVolatilityFeed),                  // Mock volatility feed deployed above
            baselineVolatility: 0.15e18,
            baseLtv: 85, 
            minLtv: 60,
            debtCeiling: 50_000_000 * 1e18,
            minCloseFactor: 0.155e18,
            maxCloseFactor: 0.75e18
        });
        collaterals[1] = CollateralConfig({                               // WETH collateral config
            token: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,            // Sepolia WETH address
            priceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,        // Chainlink ETH/USD price feed
            volatilityFeed: 0x31D04174D0e1643963b38d87f26b0675Bb7dC96e,   // ETH-USD 24hr Realized Volatility
            baselineVolatility: 0.60e18,
            baseLtv: 65, 
            minLtv: 40,
            debtCeiling: 30_000_000 * 1e18,
            minCloseFactor: 0.20e18,
            maxCloseFactor: 0.85e18
        });

        return NetworkConfig({
            collaterals: collaterals,
            deployerAccount: sepoliaDeployerAccount  // Keystore deploying account address                
        });
    }


    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.collaterals.length != 0) {
            return activeNetworkConfig;
        }

        // Deploy mocks 
        vm.startBroadcast();
        MockV3Aggregator goldUsdPriceFeed = new MockV3Aggregator(DECIMALS, GOLD_USD_PRICE);
        ERC20Mock aurumGoldMock = new ERC20Mock();
        MockVolatilityOracle goldVolatilityFeed = new MockVolatilityOracle(INITIAL_GOLD_VOLATILITY);

        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock();
        MockVolatilityOracle ethVolatilityFeed = new MockVolatilityOracle(INITIAL_ETH_VOLATILITY);
        vm.stopBroadcast();

        CollateralConfig[] memory collaterals = new CollateralConfig[](2);
        collaterals[0] = CollateralConfig({ // Gold collateral config
            token: address(aurumGoldMock),            
            priceFeed: address(goldUsdPriceFeed),       
            volatilityFeed: address(goldVolatilityFeed),
            baselineVolatility: 0.15e18,
            baseLtv: 85, 
            minLtv: 60,
            debtCeiling: 50_000_000 * 1e18,
            minCloseFactor: 0.155e18,
            maxCloseFactor: 0.75e18
        });
        collaterals[1] = CollateralConfig({ // WETH collateral config
            token: address(wethMock),
            priceFeed: address(ethUsdPriceFeed),
            volatilityFeed: address(ethVolatilityFeed),
            baselineVolatility: 0.60e18,
            baseLtv: 65, 
            minLtv: 40,
            debtCeiling: 30_000_000 * 1e18,
            minCloseFactor: 0.20e18,
            maxCloseFactor: 0.85e18
        });

        return NetworkConfig({
            collaterals: collaterals,
            deployerAccount: ANVIL_DEFAULT_ACCOUNT  // Default anvil account address                
        });
    }


    function getActiveNetworkConfig() external view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}