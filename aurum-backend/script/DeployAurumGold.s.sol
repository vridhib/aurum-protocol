// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {AurumGold} from "../src/AurumGold.sol";

contract DeployAurumGold is Script {
    function run() external returns (address) {
        vm.startBroadcast();
        AurumGold aurumGold = new AurumGold();
        vm.stopBroadcast();
        return address(aurumGold);
    }
}