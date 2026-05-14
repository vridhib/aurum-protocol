// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {AurumInterestRateModel} from "../../src/interest/AurumInterestRateModel.sol";
import {BaseTest} from "../shared/BaseTest.t.sol";

contract AurumInterestRateModelTest is BaseTest {
    uint256 constant SECONDS_PER_YEAR = 31536000;

    function testGetBorrowRateLowUtilization() public view {
        // utilization = 0% -> base rate only (0.5% APY)
        uint256 rate = interestRateModel.getBorrowRate(0);
        assertEq(rate, (0.005e18) / SECONDS_PER_YEAR);
    }

    function testGetBorrowRateOptimalUtilization() public view {
        // utilization = 75% -> base + 0.75 * 0.04 = 0.005 + 0.03 = 3.5% APY
        uint256 utilization = 0.75e18;
        uint256 expectedYearly = 0.005e18 + (utilization * 0.04e18) / PRECISION; // 0.035e18
        uint256 expectedPerSecond = expectedYearly / SECONDS_PER_YEAR;
        assertEq(interestRateModel.getBorrowRate(utilization), expectedPerSecond);
    }

    function testGetBorrowRateAboveOptimal() public view {
        // utilization = 90% -> normal rate at optimal + jump
        uint256 utilization = 0.9e18;
        uint256 optimal = 0.75e18;
        uint256 normalRate = 0.005e18 + (optimal * 0.04e18) / PRECISION; // 0.035e18
        uint256 excess = utilization - optimal; // 0.15e18
        uint256 surplus = (excess * 0.50e18) / (PRECISION - optimal); // (0.15*0.5)/0.25 = 0.3e18
        uint256 expectedYearly = normalRate + surplus; // 0.035 + 0.3 = 0.335e18 = 33.5% APY
        uint256 expectedPerSecond = expectedYearly / SECONDS_PER_YEAR;
        assertEq(interestRateModel.getBorrowRate(utilization), expectedPerSecond);
    }

    function testGetBorrowRateMaxUtilization() public view {
        uint256 rate = interestRateModel.getBorrowRate(PRECISION);
        assertGt(rate, 0);
    }

    function testGetBorrowRateZeroUtilization() public view {
        uint256 rate = interestRateModel.getBorrowRate(0);
        assertEq(rate, (0.005e18) / SECONDS_PER_YEAR);
    }

    function testBorrowRateIsPerSecond() public view {
        uint256 rate = interestRateModel.getBorrowRate(0.5e18);
        // APY would be ~ (0.005 + 0.5*0.04) = 0.025e18 = 2.5%
        // Per second must be < APY
        assertLt(rate, 0.025e18);
    }
}