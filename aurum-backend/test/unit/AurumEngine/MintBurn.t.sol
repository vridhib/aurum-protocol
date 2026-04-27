// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BaseTest} from "../../shared/BaseTest.t.sol";
import {AurumEngine} from "../../../src/AurumEngine.sol";
import {console2} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";


contract MintBurnTests is BaseTest {
    event DebtCeilingHit(address indexed token, uint256 totalDebt, uint256 allocatedDebt);
    event DebtAllocated(address user, address token, uint256 allocatedDebt);
    event DebtDeallocated(address user, address token, uint256 debtReduction);
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
        vm.prank(user);
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

    // Test that mintAUSD() reverts if a user tries to mint without having deposited collateral
    function testUsersCannotMintAUSDWithoutHavingAnyCollateral() public {
        vm.expectRevert(AurumEngine.AurumEngine__NoCollateralDeposited.selector);
        aue.mintAUSD(amountAUSD);
    }


    /***************************************************************************/
    /*******************************Burn AUSD Tests*****************************/
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
    /*******************Debt Allocation & Deallocation Tests********************/
    /***************************************************************************/
    // Test proportional allocation when both gold and WETH are deposited with no debt ceilings hit
    function testMintAUSDProportionalDebtAllocation() public depositedCollateral {
        // Deposit both collaterals: depositedCollateral (60 AUR + 40 WETH)
        // Mint AUSD – total collateral USD value:
        uint256 goldValue = aurAmount * uint256(goldPrice);  // gold: 60 * $5000 = $300,000
        uint256 wethValue = wethAmount * uint256(wethPrice); // weth: 40 * $2000 = $80,000
        uint256 totalValue = goldValue + wethValue;          // total: $380,000

        uint256 mintAmount = 40_000e18;                      // Mint $40,000 worth of AUSD
        vm.prank(user);
        aue.mintAUSD(mintAmount);

        // Expected: proportional to USD values
        uint256 expectedGoldDebt = (mintAmount * goldValue) / totalValue;
        uint256 expectedWethDebt = (mintAmount * wethValue) / totalValue;

        // Check actual debt allocation
        uint256 actualGoldDebt = aue.getUserDebtAllocation(user, aurumGold);
        uint256 actualWethDebt = aue.getUserDebtAllocation(user, weth);

        // Allow for rounding errors (dust)
        assertApproxEqAbs(actualGoldDebt, expectedGoldDebt, 1e15);
        assertApproxEqAbs(actualWethDebt, expectedWethDebt, 1e15);
    }

    // Test the debt ceiling
    function testDebtCeilingEnforced() public depositedCollateral {
        // Lower WETH's debt ceiling to a small value
        uint256 loweredDebtCeiling = 1000e18; // 1000 AUSD
        vm.startPrank(aue.owner());
        aue.setCollateralInfo(weth, aue.DEFAULT_LTV(), loweredDebtCeiling, true);
        vm.stopPrank();

        // Calculate USD values
        uint256 goldValue = aurAmount * uint256(goldPrice);  // gold: 60 * $5000 = $300,000
        uint256 wethValue = wethAmount * uint256(wethPrice); // weth: 40 * $2000 = $80,000
        uint256 totalValue = goldValue + wethValue;          // total: $380,000

        // Mint an amount that would cause WETH's proportional allocation to exceed its ceiling
        // Proportional allocation to WETH = mintAmount * (wethValue / totalValue) 
        // Proportional allocation to WETH should be > loweredCeiling
        // mintAmount * (wethValue / totalValue) > debtCeiling
        // mintAmount = (loweredDebtCeiling / (wethValue / totalValue)) + 1
       
        uint256 mintAmount = 5000e18;
        uint256 weight = (wethValue * aue.PRECISION()) / totalValue;
        uint256 attemptedWethAllocation = (mintAmount * weight) / aue.PRECISION();

        // Expect DebtCeilingHit event for WETH
        vm.expectEmit(address(aue));
        emit DebtCeilingHit(weth, aue.getCollateralTotalDebt(weth), attemptedWethAllocation);

        // Mint AUSD
        vm.prank(user);
        aue.mintAUSD(mintAmount);
 
        // Verify the ceiling was enforced
        assertEq(aue.getCollateralTotalDebt(weth), 0);
        assertEq(aue.getCollateralTotalDebt(aurumGold), mintAmount);
        assertEq(aue.getUserDebtAllocation(user, weth), 0);
        assertEq(aue.getUserDebtAllocation(user, aurumGold), mintAmount);
    }

    // Revert when there is no valid collateral
    function testRevertWhenNoValidCollateral() public depositedCollateral {
        // Set both gold and WETH debt ceilings to 0
        uint256 zeroCeiling = 0;
        vm.startPrank(aue.owner());
        aue.setCollateralInfo(aurumGold, aue.DEFAULT_LTV(), zeroCeiling, true);
        aue.setCollateralInfo(weth, aue.DEFAULT_LTV(), zeroCeiling, true);
        vm.stopPrank();

        // User attempts to mint any amount but reverts
        uint256 mintAmount = ONE_AUSD; // 1 AUSD
        vm.prank(user);
        vm.expectRevert(AurumEngine.AurumEngine__NoCollateralAvailableForDebt.selector);
        aue.mintAUSD(mintAmount);
    }

    function testDustHandlingInMintAUSDAddsRemainderToLastCollateral() public depositedCollateral {
        // User deposits collateral: depositedCollateral (60 AUR + 40 WETH)
        // USD values (using goldPrice=5000, wethPrice=2000):
        uint256 goldValue = aurAmount * uint256(goldPrice);   // 60 * 5000 = 300,000e18
        uint256 wethValue = wethAmount * uint256(wethPrice);  // 40 * 2000 =  80,000e18
        uint256 totalValue = goldValue + wethValue;           // 380,000e18

        // Choose a mint amount that does not divide evenly when split proportionally.
        // Proportional allocations for 1000 AUSD:
        //   gold: 1000 * 300,000 / 380,000 = 789.473...
        //   weth: 1000 * 80,000 / 380,000 = 210.526...
        // Due to integer truncation, the sum of allocatedDebt (789 + 210 = 999) will be less than 1000.
        uint256 mintAmount = 1000e18; // 1000 AUSD
        vm.prank(user);
        aue.mintAUSD(mintAmount);

        // Get actual debt allocations
        uint256 actualGoldAllocation = aue.getUserDebtAllocation(user, aurumGold);
        uint256 actualWethAllocation = aue.getUserDebtAllocation(user, weth);

        // Calculate expected proportional amounts (truncated)
        uint256 goldWeight = (goldValue * aue.PRECISION()) / totalValue;
        uint256 expectedGoldAllocation = (mintAmount * goldWeight) / aue.PRECISION();
        uint256 wethWeight = (wethValue * aue.PRECISION()) / totalValue;
        uint256 expectedWethRawAllocation = (mintAmount * wethWeight) / aue.PRECISION();
        uint256 dust = mintAmount - (expectedGoldAllocation + expectedWethRawAllocation);
        uint256 expectedWethAllocation = expectedWethRawAllocation + dust;  // WETH should get the remaining dust

        assertEq(actualGoldAllocation, expectedGoldAllocation);
        assertEq(actualWethAllocation, expectedWethAllocation);
        assertEq(aue.getCollateralTotalDebt(aurumGold), expectedGoldAllocation);
        assertEq(aue.getCollateralTotalDebt(weth), expectedWethAllocation);
    }

    function testDustHandlingInMintAUSDForSingleCollateral() public {
        // Deposit only gold
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), aurAmount);
        aue.depositCollateral(aurumGold, aurAmount);
        vm.stopPrank();

        uint256 mintAmount = 100e18; 
        vm.prank(user);
        aue.mintAUSD(mintAmount);

        uint256 goldAllocation = aue.getUserDebtAllocation(user, aurumGold);
        assertEq(goldAllocation, mintAmount);
        assertEq(aue.getCollateralTotalDebt(aurumGold), mintAmount);
    }

       // Deallocation on burn – after burning part of the debt, check that each collateral’s totalDebt and user’s allocation decrease proportionally.
    function testDeallocationOnBurnResultsInProportionalReduction() public depositedCollateral {
        // Mint a specific amount of AUSD that will give dust
        uint256 mintAmount = 1000e18;
        vm.prank(user);
        aue.mintAUSD(mintAmount);

        // Burn a portion
        uint256 burnAmount = 300e18;
        vm.startPrank(user);
        ausd.approve(address(aue), burnAmount);
        aue.burnAUSD(burnAmount);
        vm.stopPrank();

        // Capture debt allocations after burn
        uint256 goldAllocationAfterBurn = aue.getUserDebtAllocation(user, aurumGold);
        uint256 wethAllocationAfterBurn = aue.getUserDebtAllocation(user, weth);
        uint256 expectedRemainingDebt = mintAmount - burnAmount;

        // Calculate expected proportional reductions (same logic as mint allocation)
        uint256 goldValue = aurAmount * uint256(goldPrice);   
        uint256 wethValue = wethAmount * uint256(wethPrice);  
        uint256 totalValue = goldValue + wethValue;           

        // Expected remaining debt per collateral (proportional to original USD values)
        uint256 goldWeight = (goldValue * aue.PRECISION()) / totalValue;
        uint256 expectedGoldRemaining = (expectedRemainingDebt * goldWeight) / aue.PRECISION();
        uint256 wethWeight = (wethValue * aue.PRECISION()) / totalValue;
        uint256 expectedWethRawRemaining = (expectedRemainingDebt * wethWeight) / aue.PRECISION();
        uint256 dust = expectedRemainingDebt - (expectedGoldRemaining + expectedWethRawRemaining);
        uint256 expectedWethRemaining = expectedWethRawRemaining + dust; // last collateral (WETH) gets dust

        // Assert that allocations decreased proportionally 
        assertEq(goldAllocationAfterBurn, expectedGoldRemaining);
        assertEq(wethAllocationAfterBurn, expectedWethRemaining);
        assertEq(aue.getCollateralTotalDebt(aurumGold), goldAllocationAfterBurn);
        assertEq(aue.getCollateralTotalDebt(weth), wethAllocationAfterBurn);
    }
}