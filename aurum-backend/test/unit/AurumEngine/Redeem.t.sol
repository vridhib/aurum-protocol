// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test, console2} from "forge-std/Test.sol";
import {BaseTest} from "../../shared/BaseTest.t.sol";
import {AurumEngine} from "../../../src/AurumEngine.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";


contract RedeemTests is BaseTest {
    // Test that redeemCollater() allows a user to redeeem partial collateral
    function testUserCollateralAmountGetsUpdatedWhenRedeemed() public depositedCollateral {
        uint256 startingCollateralAmount = aue.getUserAccountData(user).collateralAmounts[0]; 
        vm.prank(user);
        aue.redeemCollateral(aurumGold, partialCollateralToRedeem);
        uint256 endingCollateralAmount = aue.getUserAccountData(user).collateralAmounts[0];
        assertGt(startingCollateralAmount, endingCollateralAmount);
    }


    // Test that mintAUSD() reverts if a user tries to redeem their entire collateral without burning all their AUSD prior
    function testRevertsIfUserRedeemsEntireCollateralWithRemainingAUSD() public depositedCollateral {
        // User deposits collateral (depositedCollateral) and mints AUSD
        vm.startPrank(user);
        aue.mintAUSD(amountAUSD);
        // Should revert when the user tries to empty all collateral without burning all AUSD prior
        aue.redeemCollateral(weth, wethAmount);
        vm.expectRevert(abi.encodeWithSelector(AurumEngine.AurumEngine__BreaksHealthFactor.selector, 0));
        aue.redeemCollateral(aurumGold, aurAmount);
        vm.stopPrank();
    }


    // Test that redeemCollateral() reverts if a user tries to redeem 0 collateral
    function testRevertsIfUserRedeemsZeroCollateral() public depositedCollateral {
        vm.prank(user);
        vm.expectRevert(AurumEngine.AurumEngine__NeedsMoreThanZero.selector);
        aue.redeemCollateral(aurumGold, 0);
    }


    // Test that users can empty their account (i.e. they can burn all their AUSD and redeem all their collateral)
    function testUsersCanEmptyAccount() public depositedCollateralAndMintedAUSD(amountAUSD) {
        // User deposits and mints collateral: depositedCollateraldepositedCollateralAndMintedAUSD(10 ether);
        vm.startPrank(user);
        // User calls redeemCollateralAndBurnAUSD
        aue.redeemCollateralAndBurnAUSD(aurumGold, aurAmount, amountAUSD);
        aue.redeemCollateral(weth, wethAmount);
        vm.stopPrank();

        // Check that AUSD minted == 0 and collateral amount == 0
        uint256 expectedAUSDMinted = 0;
        uint256 expectedCollateralAmount = 0;

        uint256 actualAUSDMinted = aue.getUserAccountData(user).totalDebt;
        uint256[] memory collateralAmounts = aue.getUserAccountData(user).collateralAmounts;
        uint256 actualCollateralValue = aue.getUserAccountData(user).totalCollateralValueInUsd;
        
        assertEq(actualCollateralValue, 0);
        assertEq(expectedAUSDMinted, actualAUSDMinted);
        assertEq(expectedCollateralAmount, collateralAmounts.length);
    }


    // Test that redeemCollateral() reverts if the underlying transferFrom returns false
    function testRedeemCollateralRevertsIfTransferFails() public depositedCollateral {
        // // Mock the external call and force the return value to be false
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", user, aurAmount);
        vm.mockCall(aurumGold, data, abi.encode(false));

        // Transaction should revert
        vm.prank(user);
        vm.expectRevert(AurumEngine.AurumEngine__TransferFailed.selector);
        aue.redeemCollateral(aurumGold, aurAmount);
    }


    /********************************************************/
    /******************Redeem With Slippage******************/
    /********************************************************/
    // Base numbers (using depositedCollateralAndMintedAUSD(getMaxSafeMint()) modifier):
    // AUR: 60 AUR @ $5000/AUR, LTV 85% --> adjusted 255,000 USD
    // WETH: 40 WETH @ $2000/WETH, LTV 65% --> adjusted 52,000 USD
    // Total max mint = 307,000 AUSD (minted exactly)

    // Test redeemCollateralWithSlippage() for requiredBurn > maxBurn
    function testRedeemCollateralWithSlippageRevertsIfRequiredBurnExceedsMax() public depositedCollateralAndMintedAUSD(getMaxSafeMint()) {
        // User wants to redeem 10% of WETH (4e18 WETH)
        // Lower WETH price to $1900 -> new max mint = 255000 + (36 * 1900 * 0.65) = 255000 + 44460 = 299460
        // Required burn = 307000 - 299460 = 7540 AUSD
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1900e8);

        uint256 expectedRequiredBurn = 7540e18;
        uint256 maxToBurn = 5300e18; // 5300 AUSD (2000/WETH + 100 extra)

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(AurumEngine.AurumEngine__SlippageExceeded.selector, expectedRequiredBurn));
        aue.redeemCollateralWithSlippage(weth, 4e18, maxToBurn);
    }

    // Test redeemCollateralWithSlippage() for requiredBurn < maxBurn
    function testRedeemCollateralWithSlippageSucceedsWhenRequiredBurnBelowMax() public depositedCollateralAndMintedAUSD(getMaxSafeMint()) {
        // WETH drops to $1900 and redeem amount is 4e18: required burn = 7540 AUSD
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1900e8);

        uint256 expectedRequiredBurn = 7540e18;
        uint256 maxToBurn = expectedRequiredBurn + 1e18; // slightly above required
        uint256 debtBefore = aue.getUserAccountData(user).totalDebt;
        uint256 collateralBefore = aue.getUserAccountData(user).collateralAmounts[1]; // WETH amount

        vm.prank(user);
        uint256 actualRequiredBurn = aue.redeemCollateralWithSlippage(weth, 4e18, maxToBurn);

        assertEq(actualRequiredBurn, expectedRequiredBurn);
        assertApproxEqAbs(aue.getUserAccountData(user).totalDebt,debtBefore - expectedRequiredBurn, 1e18);
        assertEq(aue.getUserAccountData(user).collateralAmounts[1], collateralBefore - 4e18);
    }

    // Test redeemCollateralWithSlippage() for requiredBurn == maxBurn
    function testRedeemCollateralWithSlippageSucceedsWhenRequiredBurnEqualsMax() public depositedCollateralAndMintedAUSD(getMaxSafeMint()) {
        // WETH drops to $1900 and redeem amount is 4e18: required burn = 7540 AUSD
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1900e8);

        uint256 expectedRequiredBurn = 7540e18;
        uint256 maxToBurn = expectedRequiredBurn;
        uint256 debtBefore = aue.getUserAccountData(user).totalDebt;
        uint256 collateralBefore = aue.getUserAccountData(user).collateralAmounts[1]; // WETH amount

        vm.prank(user);
        uint256 actualRequiredBurn = aue.redeemCollateralWithSlippage(weth, 4e18, maxToBurn);

        assertEq(actualRequiredBurn, expectedRequiredBurn);
        assertApproxEqAbs(aue.getUserAccountData(user).totalDebt,debtBefore - expectedRequiredBurn, 1e18);
        assertEq(aue.getUserAccountData(user).collateralAmounts[1], collateralBefore - 4e18);
    }

    // Test redeemCollateralWithSlippage() for requiredBurn == 0
    function testRedeemCollateralWithSlippageBurnsNothingIfRequiredBurnIsZero() public depositedCollateralAndMintedAUSD(getMaxSafeMint()) {
        // WETH price rises to $2250 and redeem amount is 4e18: required burn = 0 AUSD
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(2250e8);

        uint256 expectedRequiredBurn = 0;
        uint256 maxToBurn = 5300e18; // 5300 AUSD (2000/WETH + 100 extra)
        uint256 debtBefore = aue.getUserAccountData(user).totalDebt;
        uint256 collateralBefore = aue.getUserAccountData(user).collateralAmounts[1]; // WETH amount

        vm.prank(user);
        uint256 actualRequiredBurn = aue.redeemCollateralWithSlippage(weth, 4e18, maxToBurn);

        assertEq(actualRequiredBurn, expectedRequiredBurn);
        assertEq(aue.getUserAccountData(user).totalDebt, debtBefore);
        assertEq(aue.getUserAccountData(user).collateralAmounts[1], collateralBefore - 4e18);
    }
}