// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BaseTest} from "../../shared/BaseTest.t.sol";
import {console2} from "forge-std/Test.sol";
import {MockVolatilityOracle} from "../../../src/oracles/MockVolatilityOracle.sol";
import {AurumEngine} from "../../../src/AurumEngine.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract UpkeepTest is BaseTest {
    function testCheckUpkeepReturnsFalseWhenNoDebt() public view {
        (bool needed, ) = aue.checkUpkeep("");
        assertFalse(needed);
    }

    function testCheckUpkeepFalseWhenNotOverdue() public depositedCollateralAndMintedAUSD(amountAUSD) {
        // Both index and LTV were just updated
        uint256 indexBeforeUpkeep = aue.s_cumulativeIndex();
        uint256 indexLastUpdateBefore = aue.s_indexLastUpdate();
        uint256 goldLtvBeforeUpkeep = aue.getCollateralInfo(aurumGold).ltv;
        uint256 wethLtvBeforeUpkeep = aue.getCollateralInfo(weth).ltv;
        uint256 ltvLastUpdateBefore = aue.s_ltvLastUpdate();

        // Warp just under the index interval
        vm.warp(block.timestamp + 59 minutes);
        (bool needed, ) = aue.checkUpkeep("");

        // Assert neither index nor ltv were updated
        assertFalse(needed);
        assertEq(indexBeforeUpkeep, aue.s_cumulativeIndex());
        assertEq(indexLastUpdateBefore, aue.s_indexLastUpdate());
        assertEq(goldLtvBeforeUpkeep, aue.getCollateralInfo(aurumGold).ltv);
        assertEq(wethLtvBeforeUpkeep, aue.getCollateralInfo(weth).ltv);
        assertEq(ltvLastUpdateBefore, aue.s_ltvLastUpdate());
    }

    function testCheckUpkeepTrueWhenIndexOverdue() public depositedCollateralAndMintedAUSD(amountAUSD) {
        // Both index and LTV were just updated
        uint256 indexBeforeUpkeep = aue.s_cumulativeIndex();
        uint256 indexLastUpdateBefore = aue.s_indexLastUpdate();
        uint256 goldLtvBeforeUpkeep = aue.getCollateralInfo(aurumGold).ltv;
        uint256 wethLtvBeforeUpkeep = aue.getCollateralInfo(weth).ltv;
        uint256 ltvLastUpdateBefore = aue.s_ltvLastUpdate();

        // Warp just enough for the index interval to pass
        vm.warp(block.timestamp + 1 hours);
        (bool needed, bytes memory performData) = aue.checkUpkeep("");
        assertTrue(needed);
        vm.prank(aue.owner());
        aue.performUpkeep(performData);
        
        // Assert only the index was updated
        assertLt(indexBeforeUpkeep, aue.s_cumulativeIndex());
        assertLt(indexLastUpdateBefore, aue.s_indexLastUpdate());
        assertEq(goldLtvBeforeUpkeep, aue.getCollateralInfo(aurumGold).ltv);
        assertEq(wethLtvBeforeUpkeep, aue.getCollateralInfo(weth).ltv);
        assertEq(ltvLastUpdateBefore, aue.s_ltvLastUpdate());
    }

    function testCheckUpkeepTrueWhenLtvOverdue() public depositedCollateralAndMintedAUSD(amountAUSD) {
        // Both index and LTV were just updated
        uint256 indexBeforeUpkeep = aue.s_cumulativeIndex();
        uint256 indexLastUpdateBefore = aue.s_indexLastUpdate();
        uint256 goldLtvBeforeUpkeep = aue.getCollateralInfo(aurumGold).ltv;
        uint256 wethLtvBeforeUpkeep = aue.getCollateralInfo(weth).ltv;
        uint256 ltvLastUpdateBefore = aue.s_ltvLastUpdate();

        // Volatilities are updated
        vm.startPrank(MockVolatilityOracle(goldVolatilityFeed).owner());
        MockVolatilityOracle(goldVolatilityFeed).setVolatility(0.20e18);
        MockVolatilityOracle(ethVolatilityFeed).setVolatility(0.65e18);
        vm.stopPrank();

        // Warp just enough for the ltv interval to pass (+ index interval)
        vm.warp(block.timestamp + 1 days);
        _bypassStalePriceChecks();
        (bool needed, bytes memory performData) = aue.checkUpkeep("");
        assertTrue(needed);
        vm.prank(aue.owner());
        aue.performUpkeep(performData);
        
        // Assert both the index and LTVs were updated
        assertLt(indexBeforeUpkeep, aue.s_cumulativeIndex());
        assertLt(indexLastUpdateBefore, aue.s_indexLastUpdate());
        // Increased the volatility, so the LTV should go down
        assertGt(goldLtvBeforeUpkeep, aue.getCollateralInfo(aurumGold).ltv);
        assertGt(wethLtvBeforeUpkeep, aue.getCollateralInfo(weth).ltv);
        assertLt(ltvLastUpdateBefore, aue.s_ltvLastUpdate());
    }    


    function testPerformUpkeepDoesNothingWhenNoIntervalsPassed() public depositedCollateralAndMintedAUSD(amountAUSD) {
        uint256 indexBeforeUpkeep = aue.s_cumulativeIndex();
        uint256 indexLastUpdateBefore = aue.s_indexLastUpdate();
        uint256 goldLtvBeforeUpkeep = aue.getCollateralInfo(aurumGold).ltv;
        uint256 wethLtvBeforeUpkeep = aue.getCollateralInfo(weth).ltv;
        uint256 ltvLastUpdateBefore = aue.s_ltvLastUpdate();
        (, bytes memory performData) = aue.checkUpkeep("");
        vm.prank(aue.owner());
        aue.performUpkeep(performData);

        assertEq(indexBeforeUpkeep, aue.s_cumulativeIndex());
        assertEq(indexLastUpdateBefore, aue.s_indexLastUpdate());
        assertEq(goldLtvBeforeUpkeep, aue.getCollateralInfo(aurumGold).ltv);
        assertEq(wethLtvBeforeUpkeep, aue.getCollateralInfo(weth).ltv);
        assertEq(ltvLastUpdateBefore, aue.s_ltvLastUpdate());
    }

    function testPerformUpkeepRevertsIfNotForwarderOrOwner() public {
        vm.prank(user);
        vm.expectRevert(AurumEngine.AurumEngine__OnlyForwarderOrOwner.selector);
        aue.performUpkeep(abi.encode(true, true));
    }

    function testOnlyOwnerCanSetForwarder() public {
        vm.prank(aue.owner());
        aue.setForwarderAddress(address(0));
    }

    function testRevertIfNonOwnerSetsForwarder() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        aue.setForwarderAddress(address(0));
    }
}

