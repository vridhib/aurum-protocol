// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BaseTest} from "../../shared/BaseTest.t.sol";
import {MockVolatilityOracle} from "../../../src/oracles/MockVolatilityOracle.sol";
import {AurumEngine} from "../../../src/AurumEngine.sol";

contract DynamicLtvTest is BaseTest {
    // Test LTV stays at base when volatility <= baseline volatility
    function testLtvUnchangedWhenVolatilityWithinBaseline() public {
        // Gold baseline = 15%, set volatility to 10%
        vm.prank(MockVolatilityOracle(goldVolatilityFeed).owner());
        MockVolatilityOracle(goldVolatilityFeed).setVolatility(0.10e18);

        // LTV should remain the same as before
        uint256 ltvBefore = aue.getCollateralInfo(aurumGold).ltv;
        vm.prank(aue.owner());
        aue.performUpkeep(abi.encode(false, true)); // only update LTV
        uint256 ltvAfter = aue.getCollateralInfo(aurumGold).ltv;
        
        assertEq(ltvAfter, ltvBefore);
    }

    // Test LTV decreases when volatility exceeds baseline
    function testLtvDecreasesWhenVolatilityAboveBaseline() public {
        // Gold baseline 15%, set volatility to 25%
        vm.prank(MockVolatilityOracle(goldVolatilityFeed).owner());
        MockVolatilityOracle(goldVolatilityFeed).setVolatility(0.25e18);
        vm.prank(aue.owner());
        aue.performUpkeep(abi.encode(false, true)); // only update LTV;

        // Calculate new LTV
        uint256 excess = MockVolatilityOracle(goldVolatilityFeed).getAnnualizedVolatility() - aue.getCollateralInfo(aurumGold).baselineVolatility;
        uint256 reduction = ((excess) * aue.VOLATILITY_REDUCTION_FACTOR()) / 1e17;
        uint256 actualNewLtv = aue.getCollateralInfo(aurumGold).ltv;
        uint256 expectedNewLtv = aue.getCollateralInfo(aurumGold).baseLtv - reduction;

        // Should result in a 5% reduction: baseLtv - reduction = 85 - 5 = 80
        assertEq(actualNewLtv, 80); 
        assertEq(actualNewLtv, expectedNewLtv);
    }

    // Test LTV never falls below minLtv (LTV floor)
    function testLtvFlooredAtMinLtv() public {
        // Set volatility extremely high: 200%
        vm.prank(MockVolatilityOracle(goldVolatilityFeed).owner());
        MockVolatilityOracle(goldVolatilityFeed).setVolatility(2.0e18);
        vm.prank(aue.owner());
        aue.performUpkeep(abi.encode(false, true)); // only update LTV;
        uint256 actualNewLtv = aue.getCollateralInfo(aurumGold).ltv;
        uint256 expectedNewLtv = aue.getCollateralInfo(aurumGold).minLtv;

        // Should result in ltv == minLtv
        assertEq(actualNewLtv, 60);
        assertEq(actualNewLtv, expectedNewLtv);
    }

    // Test LTV never exceeds baseLtv (LTV ceiling)
    function testLtvCappedAtBaseLtv() public {
        // Set volatility extremely low
        vm.prank(MockVolatilityOracle(goldVolatilityFeed).owner());
        MockVolatilityOracle(goldVolatilityFeed).setVolatility(0.01e18);
        vm.prank(aue.owner());
        aue.performUpkeep(abi.encode(false, true)); // only update LTV;

        uint256 actualNewLtv = aue.getCollateralInfo(aurumGold).ltv;
        uint256 expectedNewLtv = aue.getCollateralInfo(aurumGold).baseLtv;
        // Should result in ltv == baseLtv
        assertEq(actualNewLtv, 85);
        assertEq(actualNewLtv, expectedNewLtv);
    }

    // Test volatility update only affects the target collateral
    function testLtvUpdateAffectsOnlyTargetCollateral() public {
        // Set gold volatility high, weth volatility low
        vm.prank(MockVolatilityOracle(goldVolatilityFeed).owner());
        MockVolatilityOracle(goldVolatilityFeed).setVolatility(0.35e18);
        vm.prank(aue.owner());
        aue.performUpkeep(abi.encode(false, true)); // only update LTV;

        // Should update collaterals independently
        uint256 goldLtv = aue.getCollateralInfo(aurumGold).ltv;
        uint256 wethLtv = aue.getCollateralInfo(weth).ltv;   
        assertEq(goldLtv, 75); // 85 - ((20/10)*5) = 75
        assertEq(wethLtv, 65); // unchanged (still 65)
    }   

    // Test setCollateralInfo updates volatility feed when non-zero address given
    function testSetCollateralInfoUpdatesVolatilityFeed() public {
        address newFeed = makeAddr("newVolFeed");
        vm.prank(aue.owner());
        aue.setCollateralInfo(aurumGold, newFeed, 0, 0, true);
        assertEq(aue.getCollateralInfo(aurumGold).volatilityFeed, newFeed);
    }

    // Test setCollateralInfo updates LTV when non-zero value given
    function testSetCollateralInfoUpdatesLTV() public {
        uint256 newLTV = 80;
        vm.prank(aue.owner());
        aue.setCollateralInfo(aurumGold, address(0), newLTV, 0, true);
        assertEq(aue.getCollateralInfo(aurumGold).ltv, newLTV);
    }
}
