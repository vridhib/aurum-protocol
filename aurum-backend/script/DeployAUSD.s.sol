// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {AurumEngine} from "../src/AurumEngine.sol";
import {AurumUSD} from "../src/AurumUSD.sol";
import {HelperConfig} from "./HelperConfig.s.sol";


contract DeployAUSD is Script {
    function run() external returns(AurumUSD, AurumEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address goldUsdPriceFeed, address goldToken, uint256 deployerKey) = config.activeNetworkConfig();

        vm.startBroadcast(deployerKey);
        AurumUSD ausd = new AurumUSD();
        AurumEngine engine = new AurumEngine(goldToken, goldUsdPriceFeed, address(ausd));

        ausd.transferOwnership(address(engine));
        vm.stopBroadcast();

        return (ausd, engine, config);
    }
}