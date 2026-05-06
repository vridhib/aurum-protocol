// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BaseTest} from "../../shared/BaseTest.t.sol";
import {console2} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";
import {MockVolatilityOracle} from "../../../src/oracles/MockVolatilityOracle.sol";
import {AurumEngine} from "../../../src/AurumEngine.sol";


contract LiquidationTests is BaseTest {
    uint256 goldMaxCloseFactor = 0.75e18;
    uint256 goldMinCloseFactor = 0.155e18;
    uint256 wethMaxCloseFactor = 0.85e18;
    uint256 wethMinCloseFactor = 0.20e18;
    uint256 maxAusdAmount = 425_000e18; // Max mintable AUSD amount for 100 AUR @ $5000/AUR
    uint256 liquidatorAusd = 200_000e18;

    modifier liquidated {
        uint256 collateralValueUsd = (amountCollateral * uint256(goldPrice));
        uint256 ausdToMint = ((collateralValueUsd * aue.getCollateralInfo(aurumGold).ltv) / LIQUIDATION_PRECISION);

        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), ausdToMint);
        aue.depositCollateralAndMintAUSD(aurumGold, amountCollateral, ausdToMint);
        vm.stopPrank();

        debtToCover = ausdToMint;  
        vm.startPrank(liquidator);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), debtToCover);
        aue.depositCollateralAndMintAUSD(aurumGold, amountCollateral, debtToCover);

        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(4950e8);
        aue.liquidate(aurumGold, user, ausdToMint); 
        vm.stopPrank();
        _;
    }

    function _setUpLiquidationScenario() private {
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), maxAusdAmount);
        aue.depositCollateralAndMintAUSD(aurumGold, amountCollateral, maxAusdAmount);
        vm.stopPrank();

        vm.startPrank(liquidator);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), liquidatorAusd);
        aue.depositCollateralAndMintAUSD(aurumGold, amountCollateral, liquidatorAusd);
        vm.stopPrank();

        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(4950e8);
    }

    function _setUpLiquidator() private {
        vm.startPrank(liquidator);
        ERC20Mock(aurumGold).approve(address(aue), aurAmount);
        ERC20Mock(weth).approve(address(aue), wethAmount);
        ausd.approve(address(aue), liquidatorAusd);
        aue.depositCollateral(aurumGold, aurAmount);
        aue.depositCollateral(weth, wethAmount);
        aue.mintAUSD(liquidatorAusd);
        vm.stopPrank();
    }

    function _expectedCloseFactor(uint256 hf, uint256 maxCf, uint256 minCf, uint256 excessVol) private pure returns (uint256) {
        uint256 boost = (excessVol * 0.05e18) / 0.10e18;
        uint256 effectiveMax = maxCf + boost;
        if (effectiveMax > 1e18) effectiveMax = 1e18;
        uint256 deficit = 1e18 - hf;
        return minCf + ((effectiveMax - minCf) * deficit) / 1e18;
    }

    
    /********************************************************/
    /***********************Core Logic***********************/
    /********************************************************/
    function testLiquidateRevertsIfUserHealthFactorIsGood() public {
        // Setup user
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), amountAUSD);
        aue.depositCollateralAndMintAUSD(aurumGold, amountCollateral, amountAUSD);
        vm.stopPrank();

        // Setup liquidator
        vm.startPrank(liquidator);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), debtToCover);
        aue.depositCollateralAndMintAUSD(aurumGold, amountCollateral, liquidatorAusd);
        uint256 userAusdAmount = aue.getUserAccountData(user).totalDebt;
    
        // Liquidator unsuccessfully tries to liquidate user
        vm.expectRevert(AurumEngine.AurumEngine__HealthFactorOkay.selector);
        aue.liquidate(aurumGold, user, userAusdAmount);
        vm.stopPrank();
    }


    function testMultiCollateralLiquidationPicksOneToken() public {
        // User deposits both collaterals and mints proportionally
        uint256 mintAmount = 300_000e18;
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), aurAmount);
        ERC20Mock(weth).approve(address(aue), wethAmount);
        aue.depositCollateral(aurumGold, aurAmount);
        aue.depositCollateral(weth, wethAmount);
        // Mint: gold LTV 85%, weth LTV 65%
        aue.mintAUSD(mintAmount);
        vm.stopPrank();

        uint256 goldAllocBefore = aue.getUserAccountData(user).debtAllocations[0];
        uint256 wethAllocBefore = aue.getUserAccountData(user).debtAllocations[1];
        uint256 userDebtBefore = aue.getUserAccountData(user).totalDebt;

        // Price drop for both tokens to trigger HF < 1
        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(4700e8);
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1800e8);
        uint256 hfBefore = aue.getUserAccountData(user).healthFactor;
        assertLt(hfBefore, aue.MIN_HEALTH_FACTOR());

        // Liquidator picks gold only
        vm.startPrank(liquidator);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), userDebtBefore);
        aue.depositCollateral(aurumGold, amountCollateral);
        aue.mintAUSD(userDebtBefore);
        // Liquidate gold, trying to cover the entire debt
        aue.liquidate(aurumGold, user, userDebtBefore);
        vm.stopPrank();

        uint256 userDebtAfter = aue.getUserAccountData(user).totalDebt;
        assertLt(userDebtAfter, userDebtBefore);

        // The debt allocations for both tokens should have been reduced proportionally
        uint256 goldAllocAfter = aue.getUserAccountData(user).debtAllocations[0];
        uint256 wethAllocAfter = aue.getUserAccountData(user).debtAllocations[1];
        assertLt(goldAllocAfter, goldAllocBefore);
        assertLt(wethAllocAfter, wethAllocBefore);
    }


    function testLiquidationDynamicCloseFactor() public liquidated {      
        // At goldPrice = $5000
        // ausdToMint = ((100 * 5000) * 85) / 100 = 425,000 AUSD
        uint256 expectedCf = _expectedCloseFactor(0.99e18, goldMaxCloseFactor, goldMinCloseFactor, 0);
        uint256 expectedMaxDebtToCover = (maxAusdAmount * expectedCf) / 1e18;
        uint256 expectedRemainingDebt = maxAusdAmount - expectedMaxDebtToCover;

        uint256 remainingDebtAfterLiquidation = aue.getUserAccountData(user).totalDebt;
        assertLt(remainingDebtAfterLiquidation, maxAusdAmount);
        assertApproxEqAbs(remainingDebtAfterLiquidation, expectedRemainingDebt, 1e18);
    }


    function testWethLiquidationDynamicCloseFactor() public {
        // User deposits WETH only, mints at max LTV
        uint256 wethCollateral = 50e18;
        uint256 mintAmount = (wethCollateral * 2000 * 65) / 100; // LTV 65%
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(aue), wethCollateral);
        aue.depositCollateralAndMintAUSD(weth, wethCollateral, mintAmount);
        vm.stopPrank();

        // Price drop to make HF < 1
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1950e8);
        uint256 hfBefore = aue.getUserAccountData(user).healthFactor;
        assertLt(hfBefore, aue.MIN_HEALTH_FACTOR());

        // Liquidator
        uint256 debtToCover = mintAmount / 2;
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(aue), wethCollateral);
        ausd.approve(address(aue), mintAmount);
        aue.depositCollateralAndMintAUSD(weth, wethCollateral, debtToCover);
        aue.liquidate(weth, user, debtToCover);
        vm.stopPrank();

        // Verify the close factor matches expectation for WETH parameters
        uint256 expectedCf = _expectedCloseFactor(hfBefore, wethMaxCloseFactor, wethMinCloseFactor, 0);
        uint256 expectedMaxDebtToCover = (mintAmount * expectedCf) / 1e18;
        uint256 expectedRemainingDebt = mintAmount - expectedMaxDebtToCover;
        uint256 remainingDebt = aue.getUserAccountData(user).totalDebt;
        assertApproxEqAbs(remainingDebt, expectedRemainingDebt, 1e18);
    }

    function testUserHealthFactorIsGoodAfterBeingLiquidated() public liquidated {
        assertGe(aue.getUserAccountData(user).healthFactor, aue.MIN_HEALTH_FACTOR());
    }


    /********************************************************/
    /******************Volatility Interactions***************/
    /********************************************************/
    function testLiquidationDynamicCloseFactorWithVolatilityBoost() public {
        // User mints at max LTV
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), maxAusdAmount);
        aue.depositCollateralAndMintAUSD(aurumGold, amountCollateral, maxAusdAmount);
        vm.stopPrank();

        // Price drop to $4900 and volatility spikes to 20%
        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(4900e8);
        uint256 hfBefore = aue.getUserAccountData(user).healthFactor;
        assertLt(hfBefore, aue.MIN_HEALTH_FACTOR());
        vm.prank(MockVolatilityOracle(goldVolatilityFeed).owner());
        MockVolatilityOracle(goldVolatilityFeed).setVolatility(0.20e18);

        // Calculate the expected close factor with volatility boost
        uint256 expectedCf = _expectedCloseFactor(hfBefore, goldMaxCloseFactor, goldMinCloseFactor, 0.05e18);

        // Liquidator prepares AUSD
        uint256 liquidationAmount = 200_000e18;
        vm.startPrank(liquidator);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), liquidationAmount);
        aue.depositCollateralAndMintAUSD(aurumGold, amountCollateral, liquidationAmount);
        aue.liquidate(aurumGold, user, liquidationAmount);
        vm.stopPrank();

        // Verify volatility boost was applied
        uint256 expectedMaxDebtToCover = (maxAusdAmount * expectedCf) / 1e18;
        uint256 expectedRemainingDebt = maxAusdAmount - expectedMaxDebtToCover;
        uint256 actualRemainingDebt = aue.getUserAccountData(user).totalDebt;
        assertApproxEqAbs(actualRemainingDebt, expectedRemainingDebt, 1e18);
        assertLt(actualRemainingDebt, maxAusdAmount);
    }

    function testCloseFactorEffectiveMaxCappedAt100Percent() public depositedCollateralAndMintedAUSD(getMaxSafeMint()) {
        // Set volatility to an absurdly high value: 1000%
        vm.prank(MockVolatilityOracle(goldVolatilityFeed).owner());
        MockVolatilityOracle(goldVolatilityFeed).setVolatility(10e18); 
        // Slight price drop to make HF < 1
        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(4900e8);
        uint256 hf = aue.getUserAccountData(user).healthFactor;
        assertLt(hf, aue.MIN_HEALTH_FACTOR());

        // Liquidator liquidates user
        _setUpLiquidator();
        uint256 debtBefore = aue.getUserAccountData(user).totalDebt;
        vm.prank(liquidator);
        aue.liquidate(aurumGold, user, liquidatorAusd);

        // Compute close factor manually: effectiveMax <= 1e18
        uint256 expectedCf = _expectedCloseFactor(hf, goldMaxCloseFactor, goldMinCloseFactor, 9.85e18);
        assertLe(expectedCf, 1e18);

        // Verify the debt reduction matches the capped close factor
        uint256 expectedMaxDebtToCover = (debtBefore * expectedCf) / 1e18;
        uint256 expectedRemainingDebt = debtBefore - expectedMaxDebtToCover;
        assertEq(aue.getUserAccountData(user).totalDebt, expectedRemainingDebt);
    }


    /********************************************************/
    /****************Multi-Step Liquidations*****************/
    /********************************************************/
    function testMultiplePartialLiquidationsAfterSuccessivePriceDrops() public liquidated {
        // After first liquidation (`liquidated`) user HF >= 1e18
        uint256 debtBeforeLiquidation2 = aue.getUserAccountData(user).totalDebt;

        // Deep price drop
        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(4000e8);
        uint256 hfAfterDrop = aue.getUserAccountData(user).healthFactor;
        assertLt(hfAfterDrop, aue.MIN_HEALTH_FACTOR());

        // Second liquidation: liquidator tries to cover the full remaining debt
        vm.prank(liquidator);
        aue.liquidate(aurumGold, user, debtBeforeLiquidation2);
        uint256 debtAfterLiquidation2 = aue.getUserAccountData(user).totalDebt;
        assertLt(debtAfterLiquidation2, debtBeforeLiquidation2);

        // Health factor after second liquidation may be lower; that's expected
        uint256 hfAfterLiquidation2 = aue.getUserAccountData(user).healthFactor;
        assertLt(hfAfterLiquidation2, aue.MIN_HEALTH_FACTOR());

        // Verify the close factor formula against the actual change
        uint256 expectedCf = _expectedCloseFactor(hfAfterDrop, goldMaxCloseFactor, goldMinCloseFactor, 0);
        uint256 expectedMaxDebtToCover = (debtBeforeLiquidation2 * expectedCf) / 1e18;
        uint256 expectedRemainingDebt = debtBeforeLiquidation2 - expectedMaxDebtToCover;

        assertApproxEqAbs(debtAfterLiquidation2, expectedRemainingDebt, 1e18);
    }


    /********************************************************/
    /*******************Balance & Rewards********************/
    /********************************************************/
    function testLiquidatorBalanceIsUpdatedAfterLiquidation() public liquidated {
        uint256 startingLiquidatorBalance = 0; 

        uint256 actualDebtCovered = debtToCover - aue.getUserAccountData(user).totalDebt;
        uint256 tokenAmountFromDebt = aue.getTokenAmountFromUsd(aurumGold, actualDebtCovered);
        uint256 liquidatorPayout = tokenAmountFromDebt + (tokenAmountFromDebt * aue.LIQUIDATION_BONUS() / aue.LIQUIDATION_AND_FEE_PRECISION());

        uint256 expectedEndingLiquidatorBalance = startingLiquidatorBalance + liquidatorPayout;
        uint256 actualEndingLiquidatorBalance = ERC20Mock(aurumGold).balanceOf(liquidator);
        assertEq(expectedEndingLiquidatorBalance, actualEndingLiquidatorBalance);
    }


    function testProtocolBalanceIsUpdatedAfterLiquidation() public liquidated {
        uint256 startingProtocolBalance = amountCollateral + amountCollateral; 

        uint256 actualDebtCovered = debtToCover - aue.getUserAccountData(user).totalDebt;
        uint256 tokenAmountFromDebt = aue.getTokenAmountFromUsd(aurumGold, actualDebtCovered);
        uint256 liquidatorPayout = tokenAmountFromDebt + (tokenAmountFromDebt * aue.LIQUIDATION_BONUS() / aue.LIQUIDATION_AND_FEE_PRECISION());

        uint256 expectedEndingProtocolBalance = startingProtocolBalance - liquidatorPayout;
        uint256 actualEndingProtocolBalance = ERC20Mock(aurumGold).balanceOf(address(aue));
        assertEq(expectedEndingProtocolBalance, actualEndingProtocolBalance);
    }


    /********************************************************/
    /***********************Edge Cases***********************/
    /********************************************************/
    function testLiquidationClearsDustDebt() public {
        // Setup specific price environment (1 Gold Token = $2.00 USD)
        int256 price = 2e8; 
        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(price);

        // User deposits 1 Gold and mints 1 AUSD
        // Initial health factor = ($2.00 * 0.8) / $1.00 = 1.6
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), ONE_AUR);
        ausd.approve(address(aue), ONE_AUR);
        aue.depositCollateralAndMintAUSD(aurumGold, ONE_AUR, ONE_AUSD);
        vm.stopPrank();

        // Setup Liquidator with 1 AUSD
        vm.prank(address(aue));
        ausd.mint(liquidator, ONE_AUSD);
        
        vm.startPrank(liquidator);
        ausd.approve(address(aue), ONE_AUR);

        // Crash the gold price (to $1.10) to trigger liquidation
        // Updated health factor = ($1.10 * 0.8) / $1.00 = 0.88 (Liquidatable!)
        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(1.1e8);

        // Liquidate user: should set debtToCover to 1 AUSD (100%) and wipe the user out.
        aue.liquidate(aurumGold, user, ONE_AUSD);
        vm.stopPrank();

        // Verify that user debt == 0
        assertEq(aue.getUserAccountData(user).totalDebt, 0);
    }


    function testLiquidatorCannotExceedMaxDebtToCover() public {
        _setUpLiquidationScenario();
        uint256 debtBefore = aue.getUserAccountData(user).totalDebt;
        uint256 hfBefore = aue.getUserAccountData(user).healthFactor;

        // Liquidator tries to cover an enormous amount
        uint256 hugeAmount = 1_000_000e18;
        vm.prank(liquidator);
        aue.liquidate(aurumGold, user, hugeAmount);

        // Verify liquidator cannot cover full `debtBefore` amount
        uint256 expectedCf = _expectedCloseFactor(hfBefore, goldMaxCloseFactor, goldMinCloseFactor, 0);
        uint256 expectedMaxDebtToCover = (debtBefore * expectedCf) / 1e18;
        uint256 expectedRemainingDebt = debtBefore - expectedMaxDebtToCover;
        assertEq(expectedRemainingDebt, aue.getUserAccountData(user).totalDebt);
    }


    function testLiquidationRevertsWhenCollateralTooLow() public {
        _setUpLiquidator();
        // User deposits tiny collateral, mints a bit, goes underwater
        uint256 tinyAmount = 0.1e18;
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), tinyAmount);
        aue.depositCollateralAndMintAUSD(aurumGold, tinyAmount, 10e18);
        vm.stopPrank();

        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(1e8); // crash price
        uint256 hf = aue.getUserAccountData(user).healthFactor;
        assertLt(hf, aue.MIN_HEALTH_FACTOR());

        // Try to liquidate more debt than collateral can cover (including penalty)
        vm.prank(liquidator);
        vm.expectRevert(); // underflow in _redeemCollateral
        aue.liquidate(aurumGold, user, liquidatorAusd);
    }
}