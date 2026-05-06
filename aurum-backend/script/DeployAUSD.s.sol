// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import {Script} from "forge-std/Script.sol";
import {AurumEngine} from "../src/AurumEngine.sol";
import {AurumUSD} from "../src/AurumUSD.sol";
import {InterestRateModel} from "../src/interest/InterestRateModel.sol";
import {AurumTreasury} from "../src/treasury/AurumTreasury.sol";
import {AurumSavings} from "../src/treasury/AurumSavings.sol";
import {HelperConfig} from "./HelperConfig.s.sol";


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
        AurumUSD ausd = new AurumUSD();

        AurumTreasury treasury = new AurumTreasury(address(ausd));
        AurumSavings savings = new AurumSavings(address(ausd), address(treasury));
        treasury.setSavingsAddress(address(savings));

        InterestRateModel interestRateModel = new InterestRateModel();
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

        ausd.transferOwnership(address(engine));
        vm.stopBroadcast();

        return (ausd, engine, config);
    }
}