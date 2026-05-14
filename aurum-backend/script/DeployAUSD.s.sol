// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AurumEngine} from "../src/AurumEngine.sol";
import {AurumUSD} from "../src/AurumUSD.sol";
import {AurumInterestRateModel} from "../src/interest/AurumInterestRateModel.sol";
import {AurumTreasury} from "../src/treasury/AurumTreasury.sol";
import {AurumSavings} from "../src/treasury/AurumSavings.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {AurumGold} from "../src/AurumGold.sol";
import {AurumGoldFaucet} from "../src/faucet/AurumGoldFaucet.sol";


contract DeployAUSD is Script {
    function run() external returns(AurumUSD, AurumEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = config.getActiveNetworkConfig();

        uint256 length = networkConfig.collaterals.length;
        address[] memory tokens = new address[](length);
        address[] memory priceFeeds = new address[](length);
        address[] memory volFeeds = new address[](length);
        uint256[] memory baseVols = new uint256[](length);
        uint256[] memory baseLtvs = new uint256[](length);
        uint256[] memory minLtvs = new uint256[](length);
        uint256[] memory debtCeilings = new uint256[](length);
        uint256[] memory minCloseFactors = new uint256[](length);
        uint256[] memory maxCloseFactors = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            HelperConfig.CollateralConfig memory cc = networkConfig.collaterals[i];
            tokens[i] = cc.token;
            priceFeeds[i] = cc.priceFeed;
            volFeeds[i] = cc.volatilityFeed;
            baseVols[i] = cc.baselineVolatility;
            baseLtvs[i] = cc.baseLtv;
            minLtvs[i] = cc.minLtv;
            debtCeilings[i] = cc.debtCeiling;
            minCloseFactors[i] = cc.minCloseFactor;
            maxCloseFactors[i] = cc.maxCloseFactor;
        }

        vm.startBroadcast(networkConfig.deployerAccount);

        // 1. Deploy core protocol
        AurumUSD ausd = new AurumUSD();
        AurumTreasury treasury = new AurumTreasury(address(ausd));
        AurumSavings savings = new AurumSavings(address(ausd), address(treasury));

        AurumInterestRateModel interestRateModel = new AurumInterestRateModel();
        AurumEngine engine = new AurumEngine(
            tokens, 
            priceFeeds,
            volFeeds,
            baseVols,
            baseLtvs,
            minLtvs,
            debtCeilings,
            minCloseFactors,
            maxCloseFactors, 
            address(ausd), 
            address(interestRateModel), 
            address(treasury)
        );

        treasury.initializeAddresses(address(savings), address(engine));
        ausd.transferOwnership(address(engine));

        // 2. Deploy the faucet (on Sepolia)
        if (block.chainid == 11155111) {
            // Mint 100,000 AUR to the deployer
            uint256 initialFaucetFunding = 100_000e18;
            address goldToken = networkConfig.collaterals[0].token;
            AurumGold(goldToken).mintFromGoldDeposit(networkConfig.deployerAccount, initialFaucetFunding);

            // Deploy the faucet
            AurumGoldFaucet faucet = new AurumGoldFaucet(goldToken);

            // Approve and fund the faucet
            IERC20(goldToken).approve(address(faucet), initialFaucetFunding);
            faucet.fund(initialFaucetFunding);
        }

        vm.stopBroadcast();

        return (ausd, engine, config);
    }
}