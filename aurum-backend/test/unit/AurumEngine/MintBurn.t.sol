// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BaseTest} from "../../shared/BaseTest.t.sol";
import {AurumEngine} from "../../../src/AurumEngine.sol";
import {InterestRateModel} from "../../../src/interest/InterestRateModel.sol";
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
        uint256 actualAUSDAmount = aue.getUserAccountData(user).totalDebt;
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
        uint256 actualAUSDAmount = aue.getUserAccountData(user).totalDebt;
        assertEq(expectedAUSDAmount, actualAUSDAmount);
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
        uint256 actualGoldDebt = aue.getUserAccountData(user).debtAllocations[0];
        uint256 actualWethDebt = aue.getUserAccountData(user).debtAllocations[1];

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
        emit DebtCeilingHit(weth, 0, attemptedWethAllocation);

        // Mint AUSD
        vm.prank(user);
        aue.mintAUSD(mintAmount);
 
        // Verify the ceiling was enforced
        assertEq(aue.getCollateralInfo(weth).totalNormalizedDebt, 0);
        assertEq(aue.getCollateralInfo(aurumGold).totalNormalizedDebt, mintAmount);
        assertEq(aue.getUserAccountData(user).debtAllocations[1], 0);
        assertEq(aue.getUserAccountData(user).debtAllocations[0], mintAmount);
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
        uint256 actualGoldAllocation = aue.getUserAccountData(user).debtAllocations[0];
        uint256 actualWethAllocation = aue.getUserAccountData(user).debtAllocations[1];

        // Calculate expected proportional amounts (truncated)
        uint256 goldWeight = (goldValue * aue.PRECISION()) / totalValue;
        uint256 expectedGoldAllocation = (mintAmount * goldWeight) / aue.PRECISION();
        uint256 wethWeight = (wethValue * aue.PRECISION()) / totalValue;
        uint256 expectedWethRawAllocation = (mintAmount * wethWeight) / aue.PRECISION();
        uint256 dust = mintAmount - (expectedGoldAllocation + expectedWethRawAllocation);
        uint256 expectedWethAllocation = expectedWethRawAllocation + dust;  // WETH should get the remaining dust

        assertEq(actualGoldAllocation, expectedGoldAllocation);
        assertEq(actualWethAllocation, expectedWethAllocation);
        assertEq(aue.getCollateralInfo(aurumGold).totalNormalizedDebt, expectedGoldAllocation);
        assertEq(aue.getCollateralInfo(weth).totalNormalizedDebt, expectedWethAllocation);
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

        uint256 goldAllocation = aue.getUserAccountData(user).debtAllocations[0];
        assertEq(goldAllocation, mintAmount);
        assertEq(aue.getCollateralInfo(aurumGold).totalNormalizedDebt, mintAmount);
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
        uint256 goldAllocationAfterBurn = aue.getUserAccountData(user).debtAllocations[0];
        uint256 wethAllocationAfterBurn = aue.getUserAccountData(user).debtAllocations[1];
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
        assertEq(aue.getCollateralInfo(aurumGold).totalNormalizedDebt, goldAllocationAfterBurn);
        assertEq(aue.getCollateralInfo(weth).totalNormalizedDebt, wethAllocationAfterBurn);
    }
    /***************************************************************************/
    /*******************Interest Accrual Tests********************/
    /***************************************************************************/
    // Test that the cumulative index increases after time passes
    function testCumulativeIndexAndUserDebtIncreaseOverTime() public depositedCollateralAndMintedAUSD(largeAUSDAmount) {
        // Deposited 100 collateral and minted 10000e18 (10,000 AUSD)
        uint256 currentIndexBefore = aue.s_cumulativeIndex();
        uint256 normalizedDebtBefore = aue.getUserAccountData(user).debtAllocations[0] + aue.getUserAccountData(user).debtAllocations[1];
        uint256 actualdebtBefore = aue.getUserAccountData(user).totalDebt;

        // Warp forward 1 year
        vm.warp(block.timestamp + ONE_YEAR);
        _bypassStalePriceChecks();
        // Update index without minting
        aue.updateIndex();
        uint256 currentIndexAfter = aue.s_cumulativeIndex();
        uint256 normalizedDebtAfter = aue.getUserAccountData(user).debtAllocations[0] + aue.getUserAccountData(user).debtAllocations[1];
        uint256 actualDebtAfter = aue.getUserAccountData(user).totalDebt;
        uint256 expectedDebtAfter = actualdebtBefore * currentIndexAfter / currentIndexBefore;

        assertEq(expectedDebtAfter, actualDebtAfter);
        assertEq(normalizedDebtBefore, normalizedDebtAfter);
        assertGt(currentIndexAfter, currentIndexBefore);
        assertEq(aue.getUserAccountData(user).lastIndex, currentIndexBefore);
        assertEq(aue.getCollateralInfo(aurumGold).totalNormalizedDebt + aue.getCollateralInfo(weth).totalNormalizedDebt, normalizedDebtBefore);
    }

    // Test that protocol fee is minted to treasury when interest is paid via burn
    function testProtocolFeeMintedOnBurnAfterInterest() 
        public 
        depositedCollateralAndMintedAUSD(amountAUSD) 
    {
        // Mint initial AUSD: depositedCollateralAndMintedAUSD(10e18)
        // Pre‑fund the user with enough AUSD to cover the future interest
        // Owner mints to user in this case; could also be from a DEX
        vm.prank(ausd.owner());
        ausd.mint(user, amountAUSD);
        vm.prank(user);
        ausd.approve(address(aue), amountAUSD);

        uint256 initialDebt = aue.getUserAccountData(user).totalDebt;
        // Warp forward 1 year
        vm.warp(block.timestamp + ONE_YEAR);
        _bypassStalePriceChecks();  // prevent stale price revert
        // Trigger interest accrual
        aue.updateIndex();
        uint256 debtWithInterest = aue.getUserAccountData(user).totalDebt;
        uint256 interest = debtWithInterest - initialDebt;

        // User burns the full debt (including interest)
        vm.startPrank(user);
        ausd.approve(address(aue), debtWithInterest);
        aue.burnAUSD(debtWithInterest);
        vm.stopPrank();
    
        // Treasury should have received PROTOCOL_RESERVE_PERCENT of the interest
        uint256 expectedFee = (interest * aue.PROTOCOL_RESERVE_PERCENT()) / aue.LIQUIDATION_AND_FEE_PRECISION();
        uint256 treasuryBalance = ausd.balanceOf(aue.i_treasury());
        uint256 finalUserActualDebt = aue.getUserAccountData(user).totalDebt;
        uint256 finalUserNormalizedDebt = aue.getUserAccountData(user).debtAllocations[0] + aue.getUserAccountData(user).debtAllocations[1];
        uint256 finalGlobalNormalizedDebt = aue.getCollateralInfo(aurumGold).totalNormalizedDebt + aue.getCollateralInfo(weth).totalNormalizedDebt;

        assertEq(treasuryBalance, expectedFee);
        assertEq(finalUserActualDebt, 0);
        assertEq(finalUserNormalizedDebt, 0);
        assertEq(finalGlobalNormalizedDebt, 0);
        assertEq(aue.getUserAccountData(user).lastIndex, aue.s_cumulativeIndex());
    }

    // Ensure that calling `updateIndex()` immediately after a mint doesn't change the index or debt
    function testNoAccrualWhenTimeHasNotPassed() public depositedCollateralAndMintedAUSD(amountAUSD) {
        uint256 indexBefore = aue.s_cumulativeIndex();
        uint256 userLastIndexBefore = aue.getUserAccountData(user).lastIndex;
        uint256 actualDebtBefore = aue.getUserAccountData(user).totalDebt;
        uint256 normalizedDebtBefore = aue.getUserAccountData(user).debtAllocations[0] + aue.getUserAccountData(user).debtAllocations[1];

        aue.updateIndex();
        assertEq(aue.s_cumulativeIndex(), indexBefore);
        assertEq(aue.getUserAccountData(user).lastIndex, userLastIndexBefore);
        assertEq(aue.getUserAccountData(user).debtAllocations[0] + aue.getUserAccountData(user).debtAllocations[1], normalizedDebtBefore);
        assertEq(aue.getUserAccountData(user).totalDebt, actualDebtBefore);
    }

    // Ensure there is no index change when a user's debt is 0
    function testNoAccrualWhenZeroTotalDebt() public depositedCollateral {
        uint256 indexBefore = aue.s_cumulativeIndex();
        uint256 actualDebtBefore = aue.getUserAccountData(user).totalDebt;
        uint256 normalizedDebtBefore = aue.getUserAccountData(user).debtAllocations[0] + aue.getUserAccountData(user).debtAllocations[1];
        
        vm.warp(block.timestamp + ONE_YEAR);
        _bypassStalePriceChecks(); 
        aue.updateIndex();
        
        assertEq(aue.s_cumulativeIndex(), indexBefore);
        assertEq(aue.getUserAccountData(user).totalDebt, actualDebtBefore);
        assertEq(aue.getUserAccountData(user).debtAllocations[0] + aue.getUserAccountData(user).debtAllocations[1], normalizedDebtBefore);
    }

    // Ensure the interest accrual is different for different users
    function testInterestAccrualForDifferentUsers() public depositedCollateral {
        // User A: deposited 60 AUR + 40 WETH and minted 1000 AUSD at block.timestamp
        // User B: deposited 60 AUR and minted 1000 AUSD at block.timestamp + 180 days
        address userA = user;
        address userB = makeAddr("userB");
        uint256 mintAmounts = 1000e18;

        // Give userB collateral
        ERC20Mock(aurumGold).mint(userB, aurAmount);
        vm.startPrank(userB);
        ERC20Mock(aurumGold).approve(address(aue), aurAmount);
        aue.depositCollateral(aurumGold, aurAmount);
        vm.stopPrank();

        // User A mints at block.timestamp
        vm.startPrank(userA);
        aue.mintAUSD(mintAmounts);
        vm.stopPrank();
        // User B mints at block.timestamp + 180 days
        vm.warp(block.timestamp + 180 days);
        _bypassStalePriceChecks();
        vm.startPrank(userB);
        aue.mintAUSD(mintAmounts);
        vm.stopPrank();
        
        vm.warp(block.timestamp + 180 days);
        _bypassStalePriceChecks();
        aue.updateIndex();
        
        uint256 actualDebtA = aue.getUserAccountData(userA).totalDebt;
        uint256 actualDebtB = aue.getUserAccountData(userB).totalDebt;
        // debtA should have accrued interest for 360 days and debtB for 180 days.
        uint256 expectedDebtA = (aue.getUserAccountData(userA).debtAllocations[0] + aue.getUserAccountData(userA).debtAllocations[1]) * aue.s_cumulativeIndex() / PRECISION;
        uint256 expectedDebtB = aue.getUserAccountData(userB).debtAllocations[0] * aue.s_cumulativeIndex() / PRECISION;

        assertGt(actualDebtA, actualDebtB);
        assertEq(expectedDebtA, actualDebtA);
        assertEq(expectedDebtB, actualDebtB);
        assertGt(aue.getUserAccountData(userB).lastIndex, aue.getUserAccountData(userA).lastIndex);
    }

    function testPartialBurnPreservesProportionalDebt() public depositedCollateralAndMintedAUSD(amountAUSD) {
        // amounts from modifier: user has collateral in gold & weth, minted amountAUSD (10e18)
        uint256 userNormGoldBefore = aue.getUserAccountData(user).debtAllocations[0];
        uint256 userNormWethBefore = aue.getUserAccountData(user).debtAllocations[1];
        uint256 totalUserNormBefore = userNormGoldBefore + userNormWethBefore;

        // User burns half of the minted amount (no time passed so debt = minted amount)
        uint256 burnAmount = amountAUSD / 2; // 5e18
        vm.startPrank(user);
        ausd.approve(address(aue), burnAmount);
        aue.burnAUSD(burnAmount);
        vm.stopPrank();

        // After burning half, normalized debt should be halved
        uint256 userNormGoldAfter = aue.getUserAccountData(user).debtAllocations[0];
        uint256 userNormWethAfter = aue.getUserAccountData(user).debtAllocations[1];
        uint256 totalUserNormAfter = userNormGoldAfter + userNormWethAfter;
        // allow 1 wei rounding difference
        assertApproxEqAbs(totalUserNormAfter, totalUserNormBefore / 2, 1);

        // Global normalized debt must match user's (only user in system)
        uint256 globalNormGoldAfter = aue.getCollateralInfo(aurumGold).totalNormalizedDebt;
        uint256 globalNormWethAfter = aue.getCollateralInfo(weth).totalNormalizedDebt;
        assertEq(globalNormGoldAfter, userNormGoldAfter);
        assertEq(globalNormWethAfter, userNormWethAfter);

        // Now warp forward to accrue interest on the remaining debt
        vm.warp(block.timestamp + ONE_YEAR);
        _bypassStalePriceChecks();
        aue.updateIndex();

        uint256 currentIndex = aue.s_cumulativeIndex();
        uint256 expectedRemainingDebt = (totalUserNormAfter * currentIndex) / PRECISION;
        uint256 actualRemainingDebt = aue.getUserAccountData(user).totalDebt;

        assertEq(actualRemainingDebt, expectedRemainingDebt);
    }

    // Test user's last index is updated to current cumulative index on mint
    function testLastIndexUpdatesOnMintAfterAccrual() public depositedCollateralAndMintedAUSD(amountAUSD) {
        uint256 oldIndex = aue.getUserAccountData(user).lastIndex;
        vm.warp(block.timestamp + 30 days);
        _bypassStalePriceChecks();
        vm.prank(user);
        aue.mintAUSD(ONE_AUSD);
        uint256 newIndex = aue.getUserAccountData(user).lastIndex;
        assertGt(newIndex, oldIndex);
        assertEq(newIndex, aue.s_cumulativeIndex());
    }

    //  Ensure no overflow when utilization > 100% (capped) and interest rate model’s jump multiplier works.
    function testHighUtilizationNoOverflow() public {
        // Set up collateral token with LTV = 100% to allow minteing up to full collateral value
        vm.startPrank(aue.owner());
        aue.setCollateralInfo(aurumGold, 100, aue.DEFAULT_DEBT_CEILING(), true);
        vm.stopPrank();

        // Give user some gold and deposit
        uint256 goldAmount = 100e18; // 100 tokens
        ERC20Mock(aurumGold).mint(user, goldAmount);
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), goldAmount);
        aue.depositCollateral(aurumGold, goldAmount);
        uint256 usdValue = aue.getUsdValue(aurumGold, goldAmount);
        aue.mintAUSD(usdValue); // utilization should now be 100%
        vm.stopPrank();

        // Mock the rate model to return a high borrow rate per second 
        uint256 highRatePerSec = 1e15; // 0.1% per second
        vm.mockCall(
            address(interestRateModel),
            abi.encodeWithSelector(InterestRateModel.getBorrowRate.selector),
            abi.encode(highRatePerSec)
        );

        // Warp forward a short time
        vm.warp(block.timestamp + 100); // 100 seconds
        _bypassStalePriceChecks();

        uint256 indexBefore = aue.s_cumulativeIndex();
        aue.updateIndex();
        uint256 indexAfter = aue.s_cumulativeIndex();

        assertGt(indexAfter, indexBefore);
    }

    // When user repays only part of the debt, the fee should be proportional to the interest portion of that repayment.
    function testProtocolFeeOnlyOnInterestPaid() public depositedCollateralAndMintedAUSD(amountAUSD) {
        // User deposited 60 AUR + 40 WETH and minted 10e18 AUSD
        uint256 initialDebt = aue.getUserAccountData(user).totalDebt;
        // Pre‑fund user with extra AUSD to pay the interest later
        vm.prank(ausd.owner());
        ausd.mint(user, 100e18); // more than enough
        vm.prank(user);
        ausd.approve(address(aue), 100e18);

        // Warp 1 year to accrue interest
        vm.warp(block.timestamp + ONE_YEAR);
        _bypassStalePriceChecks();
        aue.updateIndex();
        uint256 totalDebt = aue.getUserAccountData(user).totalDebt;
        uint256 interest = totalDebt - initialDebt;

        // Burn only the interest amount
        vm.startPrank(user);
        aue.burnAUSD(interest);
        vm.stopPrank();

        // Treasury receives 10% of the interest
        uint256 expectedFee = (interest * aue.PROTOCOL_RESERVE_PERCENT()) / aue.LIQUIDATION_AND_FEE_PRECISION();
        assertEq(ausd.balanceOf(aue.i_treasury()), expectedFee);
        // User's remaining debt should be approximately the principal
        uint256 remainingDebt = aue.getUserAccountData(user).totalDebt;
        assertApproxEqAbs(remainingDebt, initialDebt, 1e10);
        // User's normalized debt should be reduced proportionally
        uint256 userNormAfter = aue.getUserAccountData(user).debtAllocations[0] + aue.getUserAccountData(user).debtAllocations[1];
        assertGt(userNormAfter, 0);
    }

    function testFullBurnZeroesNormalizedDebt() public depositedCollateralAndMintedAUSD(amountAUSD) {
        uint256 actualDebt = aue.getUserAccountData(user).totalDebt;
        vm.startPrank(user);
        ausd.approve(address(aue), actualDebt);
        aue.burnAUSD(actualDebt);
        vm.stopPrank();

        uint256 normDebt = aue.getUserAccountData(user).debtAllocations[0] + aue.getUserAccountData(user).debtAllocations[1];
        assertEq(normDebt, 0);

        // Global normalized debt should also be zero since this is the only user
        uint256 globalNormDebt = aue.getCollateralInfo(aurumGold).totalNormalizedDebt + aue.getCollateralInfo(weth).totalNormalizedDebt;
        assertEq(globalNormDebt, 0);
    }

    function testBurnWithoutInterestNoFee() public depositedCollateralAndMintedAUSD(amountAUSD) {
        // No time warp, so no accrued interest
        uint256 treasuryBefore = ausd.balanceOf(aue.i_treasury());
        uint256 debt = aue.getUserAccountData(user).totalDebt;

        vm.startPrank(user);
        ausd.approve(address(aue), debt);
        aue.burnAUSD(debt);
        vm.stopPrank();

        assertEq(ausd.balanceOf(aue.i_treasury()), treasuryBefore);
    }

    function testBurnMoreThanDebtCapped() public depositedCollateralAndMintedAUSD(amountAUSD) {
        uint256 debt = aue.getUserAccountData(user).totalDebt;
        uint256 overAmount = debt * 2;

        // Fund user with enough to burn
        vm.prank(ausd.owner());
        ausd.mint(user, overAmount);
        uint256 userBalanceBefore = ausd.balanceOf(user);

        vm.startPrank(user);
        ausd.approve(address(aue), overAmount);
        aue.burnAUSD(overAmount);
        vm.stopPrank();

        // Debt should be zero, and user should only lose `debt` amount not `overAmount`
        assertEq(aue.getUserAccountData(user).totalDebt, 0);
        assertEq(ausd.balanceOf(user), userBalanceBefore - debt);
    }
}