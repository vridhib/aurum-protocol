// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test, console2} from "forge-std/Test.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AurumEngine} from "../../../src/AurumEngine.sol";
import {AurumUSD} from "../../../src/AurumUSD.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";
import {MockVolatilityOracle} from "../../../src/oracles/MockVolatilityOracle.sol";
import {BaseTest} from "../../shared/BaseTest.t.sol";

contract PauseUnpauseTests is BaseTest {
    function setUp() public override {
        super.setUp();
        vm.prank(address(aue));
        ausd.mint(address(treasury), 1_000_000e18);
    }

    /*----------Helper Functions----------*/
    function _makeProtocolUnderCollateralized() internal {
        uint256 numOfAccounts = 10;
        for (uint256 i = 0; i < numOfAccounts; i++) {
            address newAccount = address(uint160(i+1));

            vm.startPrank(newAccount);
            // Mint and approve 60 AUR
            ERC20Mock(aurumGold).mint(newAccount, aurAmount);
            ERC20Mock(aurumGold).approve(address(aue), aurAmount);
            aue.depositCollateral(aurumGold, aurAmount);
            // Mint and approve 40 WETH
            ERC20Mock(weth).mint(newAccount, wethAmount);
            ERC20Mock(weth).approve(address(aue), wethAmount);
            aue.depositCollateral(weth, wethAmount);
            // (60 * 5000 * 0.85) + (40 * 2000 * 0.65) = 255k + 52k = 307k max AUSD per account
            aue.mintAUSD(255_000e18);
            vm.stopPrank();
        }
        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(2500e8);
    }



    /********************************************************/
    /*********************Access Control*********************/
    /********************************************************/
    function testNonOwnerCannotPause() public {
        vm.prank(user);
        vm.expectRevert();
        aue.pause();
    }

    function testNonOwnerCannotUnpause() public {
        _makeProtocolUnderCollateralized();
        vm.prank(aue.owner());
        aue.pause();

        vm.prank(user);
        vm.expectRevert();
        aue.unpause();
    }


    /********************************************************/
    /*******************Pause Functionality******************/
    /********************************************************/
    // Test pause is enforced when the condition is met, causing state-changing function calls to revert
    function testPauseWhenConditionMetAndFunctionsRevert() public {
        _makeProtocolUnderCollateralized();
        // Owner pauses
        vm.startPrank(aue.owner());
        aue.pause();
        vm.stopPrank();
        assertTrue(aue.paused());

        // Attempts to use state-changing functions should revert with EnforcedPause()
        bytes memory pauseError = abi.encodeWithSignature("EnforcedPause()");

        // mintAUSD
        vm.expectRevert(pauseError);
        aue.mintAUSD(1e18);

        // burnAUSD
        vm.expectRevert(pauseError);
        aue.burnAUSD(1e18);

        // depositCollateral
        vm.expectRevert(pauseError);
        aue.depositCollateral(aurumGold, 1e18);

        // depositCollateralAndMintAUSD (combines two paused functions)
        vm.expectRevert(pauseError);
        aue.depositCollateralAndMintAUSD(aurumGold, 1e18, 1e18);

        // redeemCollateralAndBurnAUSD (combines two paused functions)
        vm.expectRevert(pauseError);
        aue.redeemCollateralAndBurnAUSD(aurumGold, 1e18, 1e18);

        // liquidate
        vm.expectRevert(pauseError);
        aue.liquidate(aurumGold, user, 1e18);

        // forceClose
        vm.expectRevert(pauseError);
        aue.forceClose(user);

        // performUpkeep
        vm.expectRevert(pauseError);
        aue.performUpkeep("");
    }

    // Test that pause reverts if the condition is not met
    function testPauseRevertsWhenConditionNotMet() public {
        _setUpUserAccount(1e18, 0, 425e18); // Healthy account
        vm.startPrank(aue.owner());
        vm.expectRevert(AurumEngine.AurumEngine__PauseConditionNotMet.selector);
        aue.pause();
        vm.stopPrank();
    }

    // Test that unpause restores 4 main functions (deposit, mint, burn, redeem) to working order
    function testUnpauseRestores4MainFunctions() public {
        _makeProtocolUnderCollateralized();
        vm.startPrank(aue.owner());
        aue.pause();
        aue.unpause();
        vm.stopPrank();

        // Test deposit, mint, burn, and redeem
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), aurAmount);
        aue.depositCollateral(aurumGold, 1e18);
        aue.mintAUSD(100e18);
        ausd.approve(address(aue), 1e18);
        aue.burnAUSD(1e18);
        aue.redeemCollateral(aurumGold, 0.1e18);
        vm.stopPrank();
        assertEq(ausd.balanceOf(user), 99e18);
    }

    
    /********************************************************/
    /******************Perform/Check Upkeep******************/
    /********************************************************/
    function testPerformUpkeepRevertsWhilePaused() public {
        // Setup up debt and warp time so upkeep is needed
        _setUpUserAccount(1e18, 0, 425e18);
        vm.warp(block.timestamp + 1 hours + 1);
        (bool needed, ) = aue.checkUpkeep("");
        assertTrue(needed);

        // Make protocol under-collateralized so we can pause
        _makeProtocolUnderCollateralized();
        vm.prank(aue.owner());
        aue.pause();
        // performUpkeep should revert
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        aue.performUpkeep("");
    }

    function testCheckUpkeepStillWorksWhilePaused() public {
        // Setup up debt and warp time so upkeep is needed
        _setUpUserAccount(1e18, 0, 425e18);
        vm.warp(block.timestamp + 1 hours + 1);
        (bool neededBefore, ) = aue.checkUpkeep("");
        assertTrue(neededBefore);

        // Pause
        _makeProtocolUnderCollateralized();
        vm.prank(aue.owner());
        aue.pause();
        vm.warp(block.timestamp + 6 hours + 1);

        // checkUpkeep should still return true
        (bool neededAfter, ) = aue.checkUpkeep("");
        assertTrue(neededAfter);
    }
}