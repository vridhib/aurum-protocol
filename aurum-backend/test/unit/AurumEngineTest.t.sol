// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployAUSD} from "../../script/DeployAUSD.s.sol";
import {AurumUSD} from "../../src/AurumUSD.sol";
import {AurumEngine} from "../../src/AurumEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";


contract AurumEngineTest is Test {
    DeployAUSD deployer;
    AurumUSD ausd;
    AurumEngine aue;
    HelperConfig config;
    address goldUsdPriceFeed;
    address aurumGold;

    address public user = makeAddr("user");
    address public liquidator = makeAddr("liquidator");

    int256 public collateralPrice = 5000;
    uint256 public amountCollateral = 100 ether;
    uint256 public amountAUSD = 1 ether;
    uint256 public debtToCover;
    uint256 public partialCollateralToRedeem = 1 ether;

    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;
    uint256 public constant LIQUIDATION_THRESHOLD = 80;
    uint256 public constant LIQUIDATION_PRECISION = 100;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant ONE_AUSD = 1e18;
    uint256 public constant ONE_AUR = 1e18;

    function setUp() public {
        deployer = new DeployAUSD();
        (ausd, aue, config) = deployer.run();
        (goldUsdPriceFeed, aurumGold,) = config.activeNetworkConfig(); 
        ERC20Mock(aurumGold).mint(user, STARTING_ERC20_BALANCE);
        ERC20Mock(aurumGold).mint(liquidator, STARTING_ERC20_BALANCE);
    }

    /***************************************************************************/
    /*********************************Modifiers*********************************/
    /***************************************************************************/
    modifier depositedCollateral {
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        aue.depositCollateral(amountCollateral);
        _;
        vm.stopPrank();
    }


    modifier depositedCollateralAndMintedAUSD(uint256 amountOfAUSD) {
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), amountOfAUSD);
        aue.depositCollateralAndMintAUSD(amountCollateral, amountOfAUSD);
        vm.stopPrank();
        _;
    }


    modifier liquidated {
        uint256 collateralValueUsd = (amountCollateral * uint256(collateralPrice));
        uint256 auToMint = ((collateralValueUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION);

        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), auToMint);
        aue.depositCollateralAndMintAUSD(amountCollateral, auToMint);
        vm.stopPrank();

        debtToCover = auToMint;  
        vm.startPrank(liquidator);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), debtToCover);
        aue.depositCollateralAndMintAUSD(amountCollateral, debtToCover);

        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(4950e8);
        aue.liquidate(user, auToMint); 
        vm.stopPrank();
        _;
    }


    /***************************************************************************/
    /********************************Price Tests********************************/
    /***************************************************************************/
    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedAurumGold = 0.02 ether;
        uint256 actualAurumGold = aue.getTokenAmountFromUsd(usdAmount);
        assertEq(expectedAurumGold, actualAurumGold);
    }

    function testGetUsdValue() public view {
        uint256 ethAmount = 10e18;
        // 10e18 ETH * $5000/ETH = $50,000e18
        uint256 expectedUsd = 50_000e18;
        uint256 usdValue = aue.getUsdValue(ethAmount);
        assertEq(usdValue, expectedUsd);
    }


    /***************************************************************************/
    /*************************Deposit Collateral Tests**************************/
    /***************************************************************************/
    // Test that depositCollateral() reverts if the ERC20 transferFrom returns false
    function testDepositCollateralRevertsIfTransferFails() public {
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);

        // Prepare the data for the mock call
        bytes memory data = abi.encodeWithSignature("transferFrom(address,address,uint256)", user, address(aue), amountCollateral);
        // Mock the call: when AurumEngine calls transferFrom on aurumGold with this specific data, force it to return false
        vm.mockCall(aurumGold, data, abi.encode(false));

        vm.expectRevert(AurumEngine.AurumEngine__TransferFailed.selector);
        aue.depositCollateral(amountCollateral);
    }

    // Test that depositCollateral() reverts if the user deposits 0 collateral
    function testRevertsIfUserDepositsZeroCollateral() public {
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        vm.expectRevert(AurumEngine.AurumEngine__NeedsMoreThanZero.selector);
        aue.depositCollateral(0);
        vm.stopPrank();
    }

    // Test that depositCollateral() allows user to deposit collateral and updates account info
    function testUserCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        AurumEngine.AccountInfo memory userAccountInfo = aue.getAccountInformation(user);

        uint256 expectedTotalAUSDMinted = 0;
        uint256 expectedDepositAmount = aue.getTokenAmountFromUsd(userAccountInfo.collateralValueInUsd);

        assertEq(userAccountInfo.totalAUSDMinted, expectedTotalAUSDMinted);
        assertEq(amountCollateral, expectedDepositAmount);
    }


    /***************************************************************************/
    /**************************Redeem Collateral Tests**************************/
    /***************************************************************************/
    // Test that redeemCollater() allows a user to redeeem partial collateral
    function testUserCollateralAmountGetsUpdatedWhenRedeemed() public depositedCollateral {
        uint256 startingCollateralAmount = aue.getAmountCollateral(user);
        aue.redeemCollateral(partialCollateralToRedeem);
        uint256 endingCollateralAmount = aue.getAmountCollateral(user);
        assertGt(startingCollateralAmount, endingCollateralAmount);
    }


    // Test that mintAUSD() reverts if a user tries to redeem their entire collateral without burning all their AUSD prior
    function testRevertsIfUserRedeemsEntireCollateralWithRemainingAUSD() public depositedCollateral {
        // User deposits collateral (depositedCollateral) and mints AUSD
        aue.mintAUSD(amountAUSD);
        // Should revert when the user tries to empty all collateral without burning all AUSD prior
        vm.expectRevert(abi.encodeWithSelector(AurumEngine.AurumEngine__BreaksHealthFactor.selector, 0));
        aue.redeemCollateral(amountCollateral);
    }


    // Test that redeemCollateral() reverts if a user tries to redeem 0 collateral
    function testRevertsIfUserRedeemsZeroCollateral() public depositedCollateral {
        vm.expectRevert(AurumEngine.AurumEngine__NeedsMoreThanZero.selector);
        aue.redeemCollateral(0);
    }


    // Test that users can empty their account (i.e. they can burn all their AUSD and redeem all their collateral)
    function testUsersCanEmptyAccount() public depositedCollateral {
        // User deposits collateral: depositedCollateral
        // User mints AUSD
        aue.mintAUSD(amountAUSD);

        // Approve AurumEngine to spend USER's AUSD
        ausd.approve(address(aue), amountAUSD);

        // User calls redeemCollateralAndBurnAUSD
        aue.redeemCollateralAndBurnAUSD(amountCollateral, amountAUSD);

        // Check that auMinted is 0 and collateralAmount is 0
        uint256 expectedAUSDMinted = 0;
        uint256 expectedCollateralAmount = 0;

        uint256 actualAUSDMinted = aue.getAUSDMinted(user);
        uint256 actualCollateralAmount = aue.getAmountCollateral(user);

        assertEq(expectedAUSDMinted, actualAUSDMinted);
        assertEq(expectedCollateralAmount, actualCollateralAmount);
    }


    // Test that redeemCollateral() reverts if the underlying transferFrom returns false
    function testRedeemCollateralRevertsIfTransferFails() public depositedCollateral {
        // // Mock the external call and force the return value to be false
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", user, amountCollateral);
        vm.mockCall(aurumGold, data, abi.encode(false));

        // Transaction should revert
        vm.expectRevert(AurumEngine.AurumEngine__TransferFailed.selector);
        aue.redeemCollateral(amountCollateral);
    }

    /***************************************************************************/
    /*******************************Mint AUSD Tests******************************/
    /***************************************************************************/
    // Test that mintAUSD() reverts if the underlying token mint fails
    function testMintRevertsIfTokenContractFails() public depositedCollateral {
        // Prepare the data
        bytes memory data = abi.encodeWithSignature("mint(address,uint256)", user, amountAUSD);
        // Mock the call
        vm.mockCall(address(ausd), data, abi.encode(false));

        // AurumEngine should revert with AurumEngine__MintFailed
        vm.expectRevert(AurumEngine.AurumEngine__MintFailed.selector);
        aue.mintAUSD(amountAUSD);
    }


    // Test that mintAUSD() allows users to mint AUSD
    function testUsersCanMintAUSD() public depositedCollateralAndMintedAUSD(amountAUSD) {
        uint256 expectedAUSDAmount = amountAUSD;
        uint256 actualAUSDAmount = aue.getAUSDMinted(user);
        assertEq(expectedAUSDAmount, actualAUSDAmount);
    }


    // Test that mintAUSD() reverts if users try to mint 0 AUSD
    function testUsersCantMintZeroAUSD() public depositedCollateral {
        vm.expectRevert(AurumEngine.AurumEngine__NeedsMoreThanZero.selector);
        aue.mintAUSD(0);
    }


    // Test that mintAUSD() reverts if users try to mint beyong the supply cap
    function testUsersCannotMintPastMaxSupply() public depositedCollateral {
        vm.expectRevert(AurumEngine.AurumEngine__ExceedsMaxSupply.selector);
        aue.mintAUSD(1000000000000000000 ether);
    }


    // Test that mintAUSD() reverts if a user has no collateral
    function testUsersCannotMintAUSDWithoutHavingAnyCollateral() public {
        vm.expectRevert(abi.encodeWithSelector(AurumEngine.AurumEngine__BreaksHealthFactor.selector, 0));
        aue.mintAUSD(amountAUSD);
    }


    /***************************************************************************/
    /*******************************Burn AUSD Tests******************************/
    /***************************************************************************/
    // Test that burnAUSD() allows users to burn AUSD
    function testUserCanBurnAUSD() public depositedCollateralAndMintedAUSD(amountAUSD) {
        uint256 amountToBurn = 1 ether;
        vm.prank(user);
        aue.burnAUSD(amountToBurn);
        uint256 expectedAUSDAmount = amountAUSD - amountToBurn;
        uint256 actualAUSDAmount = aue.getAUSDMinted(user);
        assertEq(expectedAUSDAmount, actualAUSDAmount);
    }


    // Test that burnAUSD() reverts if users try to burn more AUSD than they have
    function testUserCantBurnMoreAUSDThanTheyHave() public depositedCollateralAndMintedAUSD(amountAUSD) {
        uint256 amountToBurn = amountAUSD + 1;
        vm.prank(user);
        vm.expectRevert();
        aue.burnAUSD(amountToBurn);
    }


    // Test that burnAUSD() reverts if users try to burn 0 AUSD
    function testRevertsIfUserBurnsZeroAUSD() public depositedCollateral {
        vm.expectRevert(AurumEngine.AurumEngine__NeedsMoreThanZero.selector);
        aue.burnAUSD(0);
    }


    // Test that burnAUSD() reverts if the underlying transferFrom returns false
    function testBurnAUSDRevertsIfTransferFails() public depositedCollateralAndMintedAUSD(amountAUSD) {
        // Mock the external call
        bytes memory data = abi.encodeWithSignature("transferFrom(address,address,uint256)", user, address(aue), amountAUSD);
        vm.mockCall(address(ausd), data, abi.encode(false));

        vm.prank(user);
        vm.expectRevert(AurumEngine.AurumEngine__TransferFailed.selector);
        aue.burnAUSD(amountAUSD);
    }


    /***************************************************************************/
    /******************************Health Factor Tests**************************/
    /***************************************************************************/
    // Health Factor Calculations
    // Assuming XAU/USD = $5000 as set by HelperConfig.s.sol
    // healthFactor = (((collateralAmount * 5000) * 0.80) / auMinted) * 1e18
    // healthFactor = (((collateralAmount * 5000) * 80) / 100 * auMinted) * 1e18
 
    // Test case 1: getHealthFactor() returns 1 (1e18) when collateral value covers the exact collateralization ratio
    function testHealthFactorIsAtMinWhenThresholdIsMet() public depositedCollateral {
        uint256 expectedHealthFactor = 1e18;
        uint256 collateralAdjustedForThreshold = ((amountCollateral * uint256(collateralPrice)) * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION; 
        uint256 auToMint = (collateralAdjustedForThreshold * PRECISION) / expectedHealthFactor; // should be 400000 ether

        aue.mintAUSD(auToMint);

        uint256 actualHealthFactor = aue.getHealthFactor(user);
        assertEq(expectedHealthFactor, actualHealthFactor);
    }


    // Test case 2: getHealthFactor() returns 2 (2e18) when over-collateralized
    function testHealthFactorIsCorrectWhenOvercollateralized() public depositedCollateral {
        uint256 expectedHealthFactor = 2e18;
        uint256 collateralAdjustedForThreshold = ((amountCollateral * uint256(collateralPrice)) * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION; 
        uint256 auToMint = (collateralAdjustedForThreshold * PRECISION) / expectedHealthFactor; // should be 200000 ether

        aue.mintAUSD(auToMint);

        uint256 actualHealthFactor = aue.getHealthFactor(user);
        assertEq(expectedHealthFactor, actualHealthFactor);
    }


    // Test case 3: getHealthFactor() returns type(uint256).max if no AUSD is minted
    function testHealthFactorReturnsMaxIfNoDebt() public depositedCollateral {
        uint256 expectedHealthFactor = type(uint256).max;
        uint256 actualHealthFactor = aue.getHealthFactor(user);
        assertEq(expectedHealthFactor, actualHealthFactor);
    }


    // Test case 4: getHealthFactor() calculates properly when the collateral price drops
    function testHealthFactorCanGoBelowMinHealthFactor() public depositedCollateralAndMintedAUSD(400000 ether) {
        uint256 startingHealthFactor = 1e18;
        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(4950e8);
        uint256 endingHealthFactor = aue.getHealthFactor(user);
        assertGt(startingHealthFactor, endingHealthFactor);
    }

    // Test case 5: health factor breaks--should expect revert
    // Tested above in testRevertsIfUserRedeemsEntireCollateralWithRemainingAUSD()


    /***************************************************************************/
    /*******************************Liquidation Tests***************************/
    /***************************************************************************/
    // Test that liquidate() reverts if liquidators try to liquidate users with a good health factor
    function testLiquidateRevertsIfUserHealthFactorIsGood() public {
        // Arrange - user setup
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), amountAUSD);
        aue.depositCollateralAndMintAUSD(amountCollateral, amountAUSD);
        vm.stopPrank();

        // Arrange - liquidator setup
        debtToCover = amountAUSD;          // liquidator tries to completely liquidate the user
        vm.startPrank(liquidator);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), debtToCover);
        aue.depositCollateralAndMintAUSD(amountCollateral, debtToCover);
        uint256 userAUSDAmount = aue.getAUSDMinted(user);

        // Act / Assert - liquidator tries to liquidate user
        vm.startPrank(liquidator);
        vm.expectRevert(AurumEngine.AurumEngine__HealthFactorOkay.selector);
        aue.liquidate(user, userAUSDAmount);
        vm.stopPrank();
    }


    // Test that the liquidation close factor prevents 100% liquidation over small dips for users with exact collateralization ratio
    function testLiquidationCloseFactorSafetyMechanism() public {      
        // Calculate auToMint to set user at exact collateralization ratio
        uint256 collateralValueUsd = (amountCollateral * uint256(collateralPrice));
        uint256 auToMint = ((collateralValueUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION);

        // Arrange - user setup
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), auToMint);
        aue.depositCollateralAndMintAUSD(amountCollateral, auToMint);
        vm.stopPrank();

        // Arrange - liquidator setup
        debtToCover = auToMint;          // liquidator tries to completely liquidate the user (but can only do 50%)
        vm.startPrank(liquidator);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), debtToCover);
        aue.depositCollateralAndMintAUSD(amountCollateral, debtToCover);

        // Act - price drops and liquidator liquidates user 50%
        int256 goldUsdUpdatedPrice = 4950e8;                // simulate a 1% price drop
        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(goldUsdUpdatedPrice);

        aue.liquidate(user, debtToCover);
        vm.stopPrank();

        // Assert
        uint256 remainingAUSDMinted = aue.getAUSDMinted(user);
        assertGt(remainingAUSDMinted, 0);
        assertLt(remainingAUSDMinted, auToMint);
    }


    // Test the liquidation close factor requires liquidators to liquidate a max of 50% one time, then another 50% again after another dip
    function testUsersCanBePartiallyLiquidatedTwice() public {      
        // Calculate auToMint to set user at exact collateralization ratio
        uint256 collateralValueUsd = (amountCollateral * uint256(collateralPrice));
        uint256 auToMint = ((collateralValueUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION);

        // Arrange - user setup
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), auToMint);
        aue.depositCollateralAndMintAUSD(amountCollateral, auToMint);
        vm.stopPrank();

        // Arrange - liquidator setup
        debtToCover = auToMint;          // liquidator tries to completely liquidate the user (but can only do 50%)
        vm.startPrank(liquidator);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), debtToCover);
        aue.depositCollateralAndMintAUSD(amountCollateral, debtToCover);

        // Act - first simulate a small dip, then a massive crash
        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(4950e8);
        aue.liquidate(user, auToMint); 
        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(4000e8);
        
        // Liquidator tries to liquidate the remaining debt
        uint256 debtBeforeSecondLiquidation = aue.getAUSDMinted(user);
        aue.liquidate(user, debtBeforeSecondLiquidation); 
        vm.stopPrank();

        // Assert
        uint256 remainingAUSDMinted = aue.getAUSDMinted(user);
        // user's AUSD: 400k -> 200k -> 100k
        assertEq(remainingAUSDMinted, auToMint / 4); 
    }


    // Check liquidate() successfully updates user healthFactor from bad --> good
    function testUserHealthFactorIsGoodAfterBeingLiquidated() public liquidated {
        assertGe(aue.getHealthFactor(user), 1e18);
    }


    //Check liquidate() successfully updates liquidator's balance
    function testLiquidatorBalanceIsUpdatedAfterLiquidation() public liquidated {
        uint256 startingLiquidatorBalance = 0; 

        uint256 actualDebtCovered = debtToCover - aue.getAUSDMinted(user);
        uint256 tokenAmountFromDebt = aue.getTokenAmountFromUsd(actualDebtCovered);
        uint256 liquidatorPayout = tokenAmountFromDebt + (tokenAmountFromDebt * aue.getLiquidationBonus() / aue.getLiquidationPrecision());

        uint256 expectedEndingLiquidatorBalance = startingLiquidatorBalance + liquidatorPayout;
        uint256 actualEndingLiquidatorBalance = ERC20Mock(aurumGold).balanceOf(liquidator);

        assertEq(expectedEndingLiquidatorBalance, actualEndingLiquidatorBalance);
    }


    //Check liquidate() successfully updates the protocol contract's balance
    function testProtocolBalanceIsUpdatedAfterLiquidation() public liquidated {
        uint256 startingProtocolBalance = amountCollateral + amountCollateral; 

        uint256 actualDebtCovered = debtToCover - aue.getAUSDMinted(user);
        uint256 tokenAmountFromDebt = aue.getTokenAmountFromUsd(actualDebtCovered);
        uint256 liquidatorPayout = tokenAmountFromDebt + (tokenAmountFromDebt * aue.getLiquidationBonus() / aue.getLiquidationPrecision());

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
        aue.depositCollateralAndMintAUSD(ONE_AUR, ONE_AUSD);
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
        aue.liquidate(user, ONE_AUSD);
        vm.stopPrank();

        // Verify that user debt == 0
        assertEq(aue.getAUSDMinted(user), 0);
    }


    /******************************************************************************************/
    /********************************View & Pure Function Tests********************************/
    /******************************************************************************************/
    // Test that getCollateralTokenPriceFeed() returns the correct price feed
    function testGetCollateralTokenPriceFeed() public view {
        address priceFeed = aue.getCollateralTokenPriceFeed();
        assertEq(priceFeed, goldUsdPriceFeed);
    }

    // Test that getMinHealthFactor() returns the correct minimum health factor
    function testGetMinHealthFactor() public view {
        uint256 minHealthFactor = aue.getMinHealthFactor();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    // Test that getLiquidationThreshold() returns the correct liqiudation threshold
    function testGetLiquidationThreshold() public view {
        uint256 liquidationThreshold = aue.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    // Test that getAmountCollateral() returns the correct amount of tokens for a user
    function testGetCollateralBalanceOfUser() public depositedCollateral {
        uint256 collateralBalance = aue.getAmountCollateral(user);
        assertEq(collateralBalance, amountCollateral);
    }

    // Test that getAccountCollateralValueInUsd() returns the correct USD value of a user's collateral tokens
    function testGetAccountCollateralValue() public depositedCollateral {
        uint256 collateralValue = aue.getAccountCollateralValueInUsd(user);
        uint256 expectedCollateralValue = aue.getUsdValue(amountCollateral);
        assertEq(collateralValue, expectedCollateralValue);
    }

    // Test that getAUSD() returns the correct AurumUSD address
    function testGetAUSD() public view {
        address ausdAddress = aue.getAUSD();
        assertEq(ausdAddress, address(ausd));
    }

    // Test that getLiquidationPrecision() returns the correct liquidation precision
    function testGetLiquidationPrecision() public view {
        uint256 expectedLiquidationPrecision = 100;
        uint256 actualLiquidationPrecision = aue.getLiquidationPrecision();
        assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
    }

    // Test that getLiquidationBonus() returns the correct liquidation bonus percentage
    function testGetLiquidationBonus() public view {
        uint256 expectedLiquidationBonus = 5;
        uint256 actualLiquidationBonus = aue.getLiquidationBonus();
        assertEq(actualLiquidationBonus, expectedLiquidationBonus);
    }

    // Test that getProtocolFee() returns the correct protocol fee percentage
    function testGetProtocolFee() public view {
        uint256 expectedProtocolFee = 5;
        uint256 actualProtocolFee = aue.getProtocolFee();
        assertEq(actualProtocolFee, expectedProtocolFee);
    }
}