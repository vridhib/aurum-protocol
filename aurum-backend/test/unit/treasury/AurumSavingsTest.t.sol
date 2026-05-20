// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test, console2} from "forge-std/Test.sol";
import {AurumSavings} from "../../../src/treasury/AurumSavings.sol";
import {AurumUSD} from "../../../src/AurumUSD.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {AurumTreasuryTest} from "./AurumTreasuryTest.t.sol";
import {BaseTest} from "../../shared/BaseTest.t.sol";


contract AurumSavingsTest is AurumTreasuryTest {
    uint256 depositAmount = 100e18;
    uint256 withdrawAmount = 10e18;

    modifier depositedIntoSavings {
        vm.prank(owner);
        ausd.mint(user, depositAmount);
        vm.startPrank(user);
        ausd.approve(address(savings), depositAmount);
        savings.deposit(depositAmount);
        vm.stopPrank();
        _;
    }

    function testDeposit() public depositedIntoSavings {
        assertEq(savings.getUserShares(user), depositAmount); // accruedPerShare starts at 1e18
        assertEq(savings.getTotalShares(), depositAmount);
        assertEq(ausd.balanceOf(address(savings)), depositAmount);
    }

    function testWithdraw() public depositedIntoSavings{
        uint256 shares = savings.getUserShares(user);
        vm.prank(user);
        savings.withdraw(shares);

        assertEq(savings.getUserShares(user), 0);
        assertEq(savings.getTotalShares(), 0);
        assertEq(ausd.balanceOf(user), shares); // original 100e18
        assertEq(ausd.balanceOf(address(savings)), 0);
    }

    function testYieldAccrual() public depositedIntoSavings {
        // User deposits 100e18 worth of shares via `depositedIntoSavings` modifier
        // Set savings rate to 10%
        uint256 startingUserBalance = ausd.balanceOf(user);
        uint256 startingAccruedPerShare = savings.getAccruedPerShare();

        vm.prank(address(treasury));
        savings.setSavingsRate(0.10e18);
        // Fast forward 1 year
        vm.warp(block.timestamp + ONE_YEAR);
        // User withdraws 10e18 worth of shares, 1.1e18 * 10e18 shares = 11e18 AUSD
        vm.startPrank(user);
        savings.withdraw(withdrawAmount);
        vm.stopPrank();

        // Initial deposit was 100e18, then after 1 year the user withdrew 10e18 worth of shares
        // They should have 90e18 shares left.
        // If they currently have 90e18 shares, and the accruedPerShare is now 1.10e18 (due to 10% yield)
        // Then the value of their remaining shares should be 90e18 * 1.10 = 99e18.
        uint256 endingUserBalance = ausd.balanceOf(user);
        uint256 endingAccruedPerShare = savings.getAccruedPerShare();
        assertEq(endingUserBalance, startingUserBalance + (withdrawAmount * endingAccruedPerShare) / 1e18); // 10e18 shares * 1.10e18 accruedPerShare = 11e18 AUSD
        assertGt(endingAccruedPerShare, startingAccruedPerShare);
    }

    function testSetSavingsRateRevertsIfNonTreasuryAddress() public {
        vm.prank(user);
        vm.expectRevert(AurumSavings.AurumSavings__OnlyTreasuryCanSetSavingsRate.selector);
        savings.setSavingsRate(0.05e18);
    }

    function testSetSavingsRateMaxCap() public {
        vm.prank(address(treasury));
        vm.expectRevert(AurumSavings.AurumSavings__SavingsRateTooHigh.selector);
        savings.setSavingsRate(0.25e18);
    }

    function testDepositRevertsOnZero() public {
        vm.prank(user);
        vm.expectRevert(AurumSavings.AurumSavings__MustBeGreaterThanZero.selector);
        savings.deposit(0);
    }

    function testWithdrawRevertsOnInsufficientShares() public {
        vm.prank(user);
        vm.expectRevert(AurumSavings.AurumSavings__InsufficientShares.selector);
        savings.withdraw(1);
    }
}