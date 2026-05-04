// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

interface IVolatilityOracle {
     /// @return volatility as a decimal with 18 decimals, e.g., 0.3e18 = 30% annualized volatility
    function getAnnualizedVolatility() external view returns (uint256);
}