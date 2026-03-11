// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployAUSD} from "../../script/DeployAUSD.s.sol";
import {AurumEngine} from "../../src/AurumEngine.sol";
import {AurumUSD} from "../../src/AurumUSD.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Handler} from "./Handler.t.sol";
import {OracleLib, AggregatorV3Interface} from "../../src/libraries/OracleLib.sol";


contract InvariantsTest is StdInvariant, Test {
    DeployAUSD deployer;
    AurumEngine aue;
    AurumUSD ausd;
    HelperConfig config;
    address goldToken;
    address goldPriceFeed;
    Handler handler;

    using OracleLib for AggregatorV3Interface;


    function setUp() external {
        deployer = new DeployAUSD();
        (ausd, aue, config) = deployer.run();
        (goldPriceFeed, goldToken,) = config.activeNetworkConfig();
        
        handler = new Handler(aue, ausd, goldToken, goldPriceFeed);
        targetContract(address(handler));
    }


    // Invariant 1: The protocol must always be overcollateralized
    function invariant_protocolMustBeOvercollateralized() external view {
        // Calculate total collateral value in USD
        uint256 totalGoldDeposited = ERC20Mock(goldToken).balanceOf(address(aue));

        // Calculate the USD value of the collateral tokens
        uint256 totalCollateralValue = aue.getUsdValue(totalGoldDeposited);
        
        // Get the total debt/AUSD supply
        uint256 totalDscSupply = ausd.totalSupply();

        console.log("Total Collateral Value:", totalCollateralValue);
        console.log("Total AUSD Supply:", totalDscSupply);
        assert(totalCollateralValue >= totalDscSupply);
    }


    // Invariant 2: Getter functions should never revert
    function invariant_gettersShouldNotRevert() external view {
        aue.getCollateralTokenPriceFeed();
        aue.getPrecision();
        aue.getMaxAUSDSupply();
        aue.getLiquidationBonus();
        aue.getProtocolFee();
        aue.getAdditionalFeedPrecision();
        aue.getLiquidationCloseFactor();
        aue.getLiquidationThreshold();
        aue.getMinHealthFactor();
        
        // Check system-wide account info (treasury/contract itself)
        aue.getAccountInformation(address(aue));
    }
    

    // Invariant 3: Supply should not exceed MAX_DSC_SUPPLY
    function invariant_supplyCap() external view {
        uint256 actualSupply = ausd.totalSupply();
        uint256 maxSupply = aue.getMaxAUSDSupply();
        assert(actualSupply <= maxSupply);
    }
}