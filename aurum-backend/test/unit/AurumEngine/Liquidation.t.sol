// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BaseTest} from "../../shared/BaseTest.t.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";
import {AurumEngine} from "../../../src/AurumEngine.sol";

contract LiquidationTests is BaseTest {
// Test that liquidate() reverts if liquidators try to liquidate users with a good health factor
    function testLiquidateRevertsIfUserHealthFactorIsGood() public {
        // Arrange - user setup
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), amountAUSD);
        aue.depositCollateralAndMintAUSD(aurumGold, amountCollateral, amountAUSD);
        vm.stopPrank();

        // Arrange - liquidator setup
        debtToCover = amountAUSD;          // liquidator tries to completely liquidate the user
        vm.startPrank(liquidator);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), debtToCover);
        aue.depositCollateralAndMintAUSD(aurumGold, amountCollateral, debtToCover);
        uint256 userAUSDAmount = aue.getCurrentUserDebt(user);

        // Act / Assert - liquidator tries to liquidate user
        vm.startPrank(liquidator);
        vm.expectRevert(AurumEngine.AurumEngine__HealthFactorOkay.selector);
        aue.liquidate(aurumGold, user, userAUSDAmount);
        vm.stopPrank();
    }


    // Test that the liquidation close factor prevents 100% liquidation over small dips for users with exact collateralization ratio
    function testLiquidationCloseFactorSafetyMechanism() public {      
        // Calculate auToMint to set user at exact collateralization ratio
        uint256 collateralValueUsd = (amountCollateral * uint256(goldPrice));
        uint256 auToMint = ((collateralValueUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION);

        // Arrange - user setup
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), auToMint);
        aue.depositCollateralAndMintAUSD(aurumGold, amountCollateral, auToMint);
        vm.stopPrank();

        // Arrange - liquidator setup
        debtToCover = auToMint;          // liquidator tries to completely liquidate the user (but can only do 50%)
        vm.startPrank(liquidator);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), debtToCover);
        aue.depositCollateralAndMintAUSD(aurumGold, amountCollateral, debtToCover);

        // Act - price drops and liquidator liquidates user 50%
        int256 goldUsdUpdatedPrice = 4950e8;                // simulate a 1% price drop
        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(goldUsdUpdatedPrice);

        aue.liquidate(aurumGold, user, debtToCover);
        vm.stopPrank();

        // Assert
        uint256 remainingAUSDMinted = aue.getCurrentUserDebt(user);
        assertGt(remainingAUSDMinted, 0);
        assertLt(remainingAUSDMinted, auToMint);
    }


    // Test the liquidation close factor requires liquidators to liquidate a max of 50% one time, then another 50% again after another dip
    function testUsersCanBePartiallyLiquidatedTwice() public {      
        // Calculate auToMint to set user at exact collateralization ratio
        uint256 collateralValueUsd = (amountCollateral * uint256(goldPrice));
        uint256 auToMint = ((collateralValueUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION);

        // Arrange - user setup
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), auToMint);
        aue.depositCollateralAndMintAUSD(aurumGold, amountCollateral, auToMint);
        vm.stopPrank();

        // Arrange - liquidator setup
        debtToCover = auToMint;          // liquidator tries to completely liquidate the user (but can only do 50%)
        vm.startPrank(liquidator);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), debtToCover);
        aue.depositCollateralAndMintAUSD(aurumGold, amountCollateral, debtToCover);

        // Act - first simulate a small dip, then a massive crash
        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(4950e8);
        aue.liquidate(aurumGold, user, auToMint); 
        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(4000e8);
        
        // Liquidator tries to liquidate the remaining debt
        uint256 debtBeforeSecondLiquidation = aue.getCurrentUserDebt(user);
        aue.liquidate(aurumGold, user, debtBeforeSecondLiquidation); 
        vm.stopPrank();

        // Assert
        uint256 remainingAUSDMinted = aue.getCurrentUserDebt(user);
        // user's AUSD: 400k -> 200k -> 100k
        assertEq(remainingAUSDMinted, auToMint / 4); 
    }


    // Check liquidate() successfully updates user healthFactor from bad --> good
    function testUserHealthFactorIsGoodAfterBeingLiquidated() public liquidated {
        assertGe(aue.getUserHealthFactor(user), 1e18);
    }


    //Check liquidate() successfully updates liquidator's balance
    function testLiquidatorBalanceIsUpdatedAfterLiquidation() public liquidated {
        uint256 startingLiquidatorBalance = 0; 

        uint256 actualDebtCovered = debtToCover - aue.getCurrentUserDebt(user);
        uint256 tokenAmountFromDebt = aue.getTokenAmountFromUsd(aurumGold, actualDebtCovered);
        uint256 liquidatorPayout = tokenAmountFromDebt + (tokenAmountFromDebt * aue.LIQUIDATION_BONUS() / aue.LIQUIDATION_PRECISION());

        uint256 expectedEndingLiquidatorBalance = startingLiquidatorBalance + liquidatorPayout;
        uint256 actualEndingLiquidatorBalance = ERC20Mock(aurumGold).balanceOf(liquidator);

        assertEq(expectedEndingLiquidatorBalance, actualEndingLiquidatorBalance);
    }


    //Check liquidate() successfully updates the protocol contract's balance
    function testProtocolBalanceIsUpdatedAfterLiquidation() public liquidated {
        uint256 startingProtocolBalance = amountCollateral + amountCollateral; 

        uint256 actualDebtCovered = debtToCover - aue.getCurrentUserDebt(user);
        uint256 tokenAmountFromDebt = aue.getTokenAmountFromUsd(aurumGold, actualDebtCovered);
        uint256 liquidatorPayout = tokenAmountFromDebt + (tokenAmountFromDebt * aue.LIQUIDATION_BONUS() / aue.LIQUIDATION_PRECISION());

        uint256 expectedEndingProtocolBalance = startingProtocolBalance - liquidatorPayout;
        uint256 actualEndingProtocolBalance = ERC20Mock(aurumGold).balanceOf(address(aue));

        assertEq(expectedEndingProtocolBalance, actualEndingProtocolBalance);
    }


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

        // Liquidate user
        // Debt = 1 AUSD.
        // Max Cover (50%) = 0.5 AUSD.
        // Dust Check: 0.5 < 1 (Threshold). 
        // Should set debtToCover to 1 AUSD (100%) and wipe the user out.
        aue.liquidate(aurumGold, user, ONE_AUSD);
        vm.stopPrank();

        // Verify that user debt == 0
        assertEq(aue.getCurrentUserDebt(user), 0);
    }
}