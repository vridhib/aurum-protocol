// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BaseTest} from "../../shared/BaseTest.t.sol";
import {AurumEngine} from "../../../src/AurumEngine.sol";


contract RedeemTests is BaseTest {
    // Test that redeemCollater() allows a user to redeeem partial collateral
    function testUserCollateralAmountGetsUpdatedWhenRedeemed() public depositedCollateral {
        uint256 startingCollateralAmount = aue.getUserCollateralAmount(aurumGold, user);
        vm.prank(user);
        aue.redeemCollateral(aurumGold, partialCollateralToRedeem);
        uint256 endingCollateralAmount = aue.getUserCollateralAmount(aurumGold, user);
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

        uint256 actualAUSDMinted = aue.getAUSDMinted(user);
        uint256 actualCollateralAmount = aue.getUserCollateralAmount(aurumGold, user) + aue.getUserCollateralAmount(weth, user);

        assertEq(expectedAUSDMinted, actualAUSDMinted);
        assertEq(expectedCollateralAmount, actualCollateralAmount);
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
}