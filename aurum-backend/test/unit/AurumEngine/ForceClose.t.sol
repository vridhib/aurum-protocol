// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BaseTest} from "../../shared/BaseTest.t.sol";
import {console2, stdStorage, StdStorage} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";
import {MockVolatilityOracle} from "../../../src/oracles/MockVolatilityOracle.sol";
import {AurumEngine} from "../../../src/AurumEngine.sol";


contract ForceCloseTests is BaseTest {
    uint256 constant COLLATERAL_MAPPING_SLOT = 1;

    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.prank(address(aue));
        ausd.mint(address(treasury), 1_000_000e18); // 1M AUSD
    }

    /*----------Helper Functions----------*/
    function _collateralSlot(address account, address token) internal pure returns (bytes32) {
        return keccak256(abi.encode(token, keccak256(abi.encode(account, COLLATERAL_MAPPING_SLOT))));
    }
    /*-----------------------------------*/

    // Test force closure success on: collateral = 0, debt > 0
    function testForceCloseSucceedsOnZeroCollateralNonZeroDebt() public {
        // Setup user
        _setUpUserAccount(1e18, 0, 425e18);
        uint256 debtBefore = aue.getUserAccountData(user).totalDebt;
        uint256 treasuryBalanceBefore = ausd.balanceOf(address(treasury));
        uint256 supplyBefore = ausd.totalSupply();

        // Zero out collateral
        bytes32 slot = _collateralSlot(user, aurumGold);
        vm.store(address(aue), slot, bytes32(uint256(0)));
        // Force close the position
        vm.expectEmit(address(aue));
        emit AurumEngine.ForceClosed(user, debtBefore, 0);
        aue.forceClose(user);

        // Verify the position was closed
        assertEq(aue.getUserAccountData(user).totalDebt, 0);
        assertEq(ausd.balanceOf(address(treasury)), treasuryBalanceBefore - debtBefore);
        assertEq(ausd.totalSupply(), supplyBefore - debtBefore);
        assertEq(aue.getUserAccountData(user).lastIndex, aue.s_cumulativeIndex());
    }

    // Test force closure success on dust scenario (small non-zero collateral with HF < 1e18)
    function testForceCloseSucceedsWithDustCollateral() public {
        // User deposits 0.02 AUR ($100 at $5000/AUR) and mints near max
        _setUpUserAccount(0.02e18, 0, 85e18); // collateral ~$100
        uint256 debtBefore = aue.getUserAccountData(user).totalDebt;
        uint256 treasuryAusdBefore = ausd.balanceOf(address(treasury));
        uint256 supplyBefore = ausd.totalSupply();

        // Slight price drop to make HF < 1 
        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(4990e8);
        assertLt(aue.getUserAccountData(user).healthFactor, 1e18);
        // Force close the position
        vm.expectEmit(address(aue));
        emit AurumEngine.ForceClosed(user, debtBefore, aue.getUserAccountData(user).totalCollateralValueInUsd);
        aue.forceClose(user);

        // Verify position was closed and all collateral was moved to the treasury
        assertEq(aue.getUserAccountData(user).totalDebt, 0);
        assertEq(aue.getUserAccountData(user).totalCollateralValueInUsd, 0);
        assertEq(ausd.balanceOf(address(treasury)), treasuryAusdBefore - debtBefore);
        assertEq(ausd.totalSupply(), supplyBefore - debtBefore);
        assertEq(ERC20Mock(aurumGold).balanceOf(address(treasury)), 0.02e18);
    }

    // Test force closure success on deep insolvency (hf <= 0.50) with large collateral value
    function testForceCloseSucceedsWithDeeplyInsolvent() public {
        // User deposits 1 AUR ($5000/AUR) and mints near max (4250 AUSD)
        _setUpUserAccount(1e18, 0, 4250e18);
        uint256 debtBefore = aue.getUserAccountData(user).totalDebt;
        uint256 treasuryAUSDBefore = ausd.balanceOf(address(treasury));
        uint256 supplyBefore = ausd.totalSupply();

        // Crash price to $1000/AUR, HF becomes ~0.2
        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(1000e8);
        uint256 hf = aue.getUserAccountData(user).healthFactor;
        assertLt(hf, 0.50e18); // deep insolvency
        // Force close bc HF < threshold (even though collateral > $100)
        vm.expectEmit(address(aue));
        emit AurumEngine.ForceClosed(user, debtBefore, aue.getUserAccountData(user).totalCollateralValueInUsd);
        aue.forceClose(user);

        // Verify position was closed and all collateral was moved to the treasury
        assertEq(aue.getUserAccountData(user).totalDebt, 0);
        assertEq(aue.getUserAccountData(user).totalCollateralValueInUsd, 0);
        assertEq(ausd.balanceOf(address(treasury)), treasuryAUSDBefore - debtBefore);
        assertEq(ausd.totalSupply(), supplyBefore - debtBefore);
        assertEq(ERC20Mock(aurumGold).balanceOf(address(aue)), 0); 
        assertEq(ERC20Mock(aurumGold).balanceOf(address(treasury)), 1e18);
    }

    // Test force closure success on multi-collateral deep insolvency 
    function testForceCloseSucceedsMultiCollateralInsolvent() public {
        // User deposits 1 AUR ($5000/AUR) and 10 WETH ($2000/WETH), and mints max
        // (1 * 5000 * 0.85) + (10 * 2000 * 0.65) = 4250 + 13000 = 17250
        _setUpUserAccount(1e18, 10e18, 17250e18); 
        uint256 debtBefore = aue.getUserAccountData(user).totalDebt;
        uint256 treasuryAUSDBefore = ausd.balanceOf(address(treasury));
        // Crash both prices
        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(1000e8);
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(500e8);
        uint256 hf = aue.getUserAccountData(user).healthFactor;
        assertLt(hf, 0.50e18);

        // Force close position
        vm.expectEmit(address(aue));
        emit AurumEngine.ForceClosed(user, debtBefore, aue.getUserAccountData(user).totalCollateralValueInUsd);
        aue.forceClose(user);

        // Verify position was closed and treasury gained collateral
        assertEq(aue.getUserAccountData(user).totalDebt, 0);
        assertEq(aue.getUserAccountData(user).totalCollateralValueInUsd, 0);
        assertEq(ausd.balanceOf(address(treasury)), treasuryAUSDBefore - debtBefore);
        assertEq(ERC20Mock(aurumGold).balanceOf(address(treasury)), 1e18);
        assertEq(ERC20Mock(weth).balanceOf(address(treasury)), 10e18);
    }

    // Test revert on healthy position
    function testForceCloseRevertsHealthyPosition() public depositedCollateralAndMintedAUSD(amountAUSD){
        vm.expectRevert(AurumEngine.AurumEngine__HealthFactorOkay.selector);
        aue.forceClose(user);
    }

    // Test revert on healthy no-debt position (user HF = type(uint256).max)
    function testForceCloseRevertsOnMaxHfPosition() public depositedCollateral {
        vm.expectRevert(AurumEngine.AurumEngine__UserHasNoDebt.selector);
        aue.forceClose(user);
    }

    // Test revert on ineligible position: collateral > max and HF > threshold
    function testForceCloseRevertsWhenAboveMaxForceCloseCollateral() public {
        // Deposit large collateral, that goes slightly underwater
        _setUpUserAccount(1e18, 0, 4250e18);
        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(4999e8); // HF drops to 0.99
        uint256 hf = aue.getUserAccountData(user).healthFactor;
        assertLt(hf, 1e18);    // Underwater
        assertGt(hf, 0.50e18); // But not deeply insolvent
        assertGt(aue.getUserAccountData(user).totalCollateralValueInUsd, aue.MAX_FORCE_CLOSE_COLLATERAL_VALUE());
        vm.expectRevert(AurumEngine.AurumEngine__IneligibleForForceClose.selector);
        aue.forceClose(user);
    }
}