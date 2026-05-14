// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/**
 * @title AurumInterestRateModel
 * @notice Kinked utilization curve with a low base rate due to gold's stability
 * @dev Optimized for gold's low volatility (gold's ~15-21% vs ETH's ~60-80%)
 */
 contract AurumInterestRateModel {
    uint256 private constant PRECISION = 1e18;
    uint256 private constant SECONDS_PER_YEAR = 31536000;

    /// @dev Base rate: 0.5% APY (gold is relatively stable)
    uint256 private s_baseRate = 0.005e18;

    /// @dev Slope1: increases up to optimal utilization (max 4% extra)
    uint256 private s_multiplier = 0.04e18;

    /// @dev Optimal utilization: 75% (due to lower volatility of gold)
    uint256 private s_optimalUtilization = 0.75e18;

    /// @dev Slope2: above optimal, borrow rate spikes aggressively
    uint256 private s_jumpMultiplier = 0.50e18;

    constructor() {} 

    /**
     * @param utilization is totalDebt / totalCollateralValue (in 1e18)
     * @return borrowRate per second in 1e18
     */
    function getBorrowRate(uint256 utilization) external view returns (uint256) {
        uint256 ratePerYear;
        // Case 1: utilization <= optimal (0% - 75%)
        if (utilization <= s_optimalUtilization) {
            // Linear: 0.005e18 + ((utilization * 0.04e18) / 1e18)
            ratePerYear = s_baseRate + ((utilization * s_multiplier) / PRECISION);
        }
        // Case 2: utilization > optimal (76% - 100%)
        else { 
            // Compute rate at optimal
            uint256 normalRate = s_baseRate + ((s_optimalUtilization * s_multiplier) / PRECISION);
            // Calculute excess utilization
            uint256 excess = utilization - s_optimalUtilization;
            // Add steep slope: (excess * 0.50e18) / (1e18 - 0.75e18)
            uint256 surplus = (excess * s_jumpMultiplier) / (PRECISION - s_optimalUtilization);
            ratePerYear = normalRate + surplus;
        }

        // Convert yearly rate to per-second rate
        return ratePerYear / SECONDS_PER_YEAR;
    }
 }