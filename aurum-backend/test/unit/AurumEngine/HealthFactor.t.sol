// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BaseTest} from "../../shared/BaseTest.t.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";

contract HealthFactorTests is BaseTest {
    // Health Factor Calculations
    // Assuming XAU/USD = $5000 as set by HelperConfig.s.sol
    // healthFactor = (((collateralAmount * 5000) * 0.80) / ausdMinted) * 1e18
    // healthFactor = (((collateralAmount * 5000) * 80) / 100 * ausdMinted) * 1e18
 
    // Test case 1: getUserHealthFactor() returns 1 (1e18) when collateral value covers the exact collateralization ratio
    function testHealthFactorIsAtMinWhenThresholdIsMet() public depositedSingleCollateral {
        uint256 expectedHealthFactor = 1e18;
        uint256 collateralAdjustedForThreshold = ((amountCollateral * uint256(goldPrice)) * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION; 
        uint256 ausdToMint = (collateralAdjustedForThreshold * PRECISION) / expectedHealthFactor; // should be 400000 ether

        vm.prank(user);
        aue.mintAUSD(ausdToMint);

        uint256 actualHealthFactor = aue.getUserAccountData(user).healthFactor;
        assertEq(expectedHealthFactor, actualHealthFactor);
    }


    // Test case 2: getUserHealthFactor() returns 2 (2e18) when over-collateralized
    function testHealthFactorIsCorrectWhenOvercollateralized() public depositedSingleCollateral {
        uint256 expectedHealthFactor = 2e18;
        uint256 collateralAdjustedForThreshold = ((amountCollateral * uint256(goldPrice)) * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION; 
        uint256 auToMint = (collateralAdjustedForThreshold * PRECISION) / expectedHealthFactor; // should be 200000 ether

        vm.prank(user);
        aue.mintAUSD(auToMint);

        uint256 actualHealthFactor = aue.getUserAccountData(user).healthFactor;
        assertEq(expectedHealthFactor, actualHealthFactor);
    }


    // Test case 3: getUserHealthFactor() returns type(uint256).max if no AUSD is minted
    function testHealthFactorReturnsMaxIfNoDebt() public depositedSingleCollateral {
        uint256 expectedHealthFactor = type(uint256).max;
        uint256 actualHealthFactor = aue.getUserAccountData(user).healthFactor;
        assertEq(expectedHealthFactor, actualHealthFactor);
    }


    // Test case 4: getUserHealthFactor() calculates properly when the collateral price drops
    function testHealthFactorCanGoBelowMinHealthFactor() public depositedCollateralAndMintedAUSD(getMaxSafeMint()) {
        uint256 startingHealthFactor = 1e18;
        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(4950e8);
        uint256 endingHealthFactor = aue.getUserAccountData(user).healthFactor;
        assertGt(startingHealthFactor, endingHealthFactor);
    }


    // Test case 5: health factor breaks, should expect revert
    // Tested above in testRevertsIfUserRedeemsEntireCollateralWithRemainingAUSD()
}