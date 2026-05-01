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
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns(AurumUSD, AurumEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address goldUsdPriceFeed, address wethUsdPriceFeed, address goldToken, address weth, address deployerAccount) = config.activeNetworkConfig();
        tokenAddresses = [goldToken, weth];
        priceFeedAddresses = [goldUsdPriceFeed, wethUsdPriceFeed];

        vm.startBroadcast(deployerAccount);
        AurumUSD ausd = new AurumUSD();

        AurumTreasury treasury = new AurumTreasury(address(ausd));
        AurumSavings savings = new AurumSavings(address(ausd), address(treasury));
        treasury.setSavingsAddress(address(savings));

        InterestRateModel interestRateModel = new InterestRateModel();
        AurumEngine engine = new AurumEngine(
            tokenAddresses, 
            priceFeedAddresses, 
            address(ausd), 
            address(interestRateModel), 
            address(treasury)
        );

        ausd.transferOwnership(address(engine));
        vm.stopBroadcast();

        return (ausd, engine, config);
    }
}