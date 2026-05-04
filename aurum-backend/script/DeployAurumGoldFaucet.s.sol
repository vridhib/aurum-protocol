// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {AurumGoldFaucet} from "../src/faucet/AurumGoldFaucet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Script} from "forge-std/Script.sol";

contract DeployAurumGoldFaucet is Script {
    function run() public returns (AurumGoldFaucet) {
        // Deploy the AUR faucet
        AurumGoldFaucet faucet = deploy();

        // Fund only if the current chain is Ethereum Sepolia
        if (block.chainid == 11155111) fund(faucet);

        return faucet;
    }

    function deploy() public returns (AurumGoldFaucet) {
        HelperConfig config = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = config.getActiveNetworkConfig();
        address aurumGold = networkConfig.collaterals[0].token;
        address deployerAccount = networkConfig.deployerAccount;

        vm.startBroadcast(deployerAccount);
        AurumGoldFaucet faucet = new AurumGoldFaucet(aurumGold);
        vm.stopBroadcast();

        return faucet;
    }


    function fund(AurumGoldFaucet faucet) public {
        HelperConfig config = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = config.getActiveNetworkConfig();
        address aurumGold = networkConfig.collaterals[0].token;
        address deployerAccount = networkConfig.deployerAccount;

        uint256 fundAmount = 100_000 ether;     // 100,000 AUR

        vm.startBroadcast(deployerAccount);
        IERC20(aurumGold).approve(address(faucet), fundAmount);
        faucet.fund(fundAmount);
        vm.stopBroadcast();
    }
}


