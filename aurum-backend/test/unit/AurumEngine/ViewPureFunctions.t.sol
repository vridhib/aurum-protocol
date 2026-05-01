// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BaseTest} from "../../shared/BaseTest.t.sol";
import {AurumEngine} from "../../../src/AurumEngine.sol";

contract ViewPureFunctionsTests is BaseTest {
    /******************************************************************************************/
    /********************************View & Pure Function Tests********************************/
    /******************************************************************************************/
    // Test that getCollateralInfo() returns the correct collateral price feed address
    function testGetCollateralInfo() public view {
        AurumEngine.CollateralInfo memory goldInfo = aue.getCollateralInfo(aurumGold);
        AurumEngine.CollateralInfo memory wethInfo = aue.getCollateralInfo(weth);
        assertEq(goldInfo.priceFeed, goldUsdPriceFeed);
        assertEq(wethInfo.priceFeed, ethUsdPriceFeed);
    }

    // Test that getMinHealthFactor() returns the correct minimum health factor
    function testGetMinHealthFactor() public view {
        uint256 minHealthFactor = aue.MIN_HEALTH_FACTOR();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    // Test that getLiquidationThreshold() returns the correct liqiudation threshold
    function testGetLiquidationThreshold() public view {
        uint256 liquidationThreshold = aue.LIQUIDATION_THRESHOLD();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    // Test that getUserAccountData() returns the correct collateral amounts for a user
    function testGetUserAccountData() public depositedCollateral {
        AurumEngine.UserAccountData memory userData = aue.getUserAccountData(user);
        assertEq(userData.collateralAmounts[0], aurAmount);
        assertEq(userData.collateralAmounts[1], wethAmount);
    }

    // Test that getAccountCollateralValueInUsd() returns the correct USD value of a user's collateral tokens
    function testGetAccountCollateralValue() public depositedCollateral {
        uint256 collateralValue = aue.getUserAccountData(user).totalCollateralValueInUsd;
        uint256 expectedAurValue = aue.getUsdValue(aurumGold, aurAmount);
        uint256 expectedWethValue = aue.getUsdValue(weth, wethAmount);

        assertEq(collateralValue, expectedAurValue + expectedWethValue);
    }

    // Test that getAUSD() returns the correct AurumUSD address
    function testGetAUSD() public view {
        address ausdAddress = address(aue.i_ausd());
        assertEq(ausdAddress, address(ausd));
    }

    // Test that getLiquidationPrecision() returns the correct liquidation precision
    function testGetLiquidationPrecision() public view {
        uint256 expectedLiquidationPrecision = 100;
        uint256 actualLiquidationPrecision = aue.LIQUIDATION_AND_FEE_PRECISION();
        assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
    }

    // Test that getLiquidationBonus() returns the correct liquidation bonus percentage
    function testGetLiquidationBonus() public view {
        uint256 expectedLiquidationBonus = 5;
        uint256 actualLiquidationBonus = aue.LIQUIDATION_BONUS();
        assertEq(actualLiquidationBonus, expectedLiquidationBonus);
    }

    // Test that getProtocolFee() returns the correct protocol fee percentage
    function testGetProtocolFee() public view {
        uint256 expectedProtocolFee = 5;
        uint256 actualProtocolFee = aue.PROTOCOL_FEE();
        assertEq(actualProtocolFee, expectedProtocolFee);
    }

    /***************************************************************************/
    /********************************Price Tests********************************/
    /***************************************************************************/
    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedAurumGold = 0.02 ether;
        uint256 actualAurumGold = aue.getTokenAmountFromUsd(aurumGold, usdAmount);
        assertEq(expectedAurumGold, actualAurumGold);
    }

    function testGetUsdValue() public view {
        uint256 ethAmount = 10e18;
        // 10e18 ETH * $5000/ETH = $50,000e18
        uint256 expectedUsd = 50_000e18;
        uint256 usdValue = aue.getUsdValue(aurumGold, ethAmount);
        assertEq(usdValue, expectedUsd);
    }

}