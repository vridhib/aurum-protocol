// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IVolatilityOracle} from "./IVolatilityOracle.sol";

contract ChainlinkVolatilityOracle is IVolatilityOracle {
    error ChainlinkVolatilityOracle__StalePrice();

    AggregatorV3Interface private immutable i_priceFeed;
    uint256 private immutable i_decimals;

    constructor(address priceFeed, uint256 decimals) {
        i_priceFeed = AggregatorV3Interface(priceFeed);
        i_decimals = decimals;
    }

    function getAnnualizedVolatility() external view override returns (uint256) {
        (,int256 answer,,uint256 updatedAt,) = i_priceFeed.latestRoundData();
        if (updatedAt <= block.timestamp - 2 hours) {
            revert ChainlinkVolatilityOracle__StalePrice();
        }
        // ETH-USD 24hr Realized Volatility: 0x31D04174D0e1643963b38d87f26b0675Bb7dC96e
        // Decimals: 5
        return uint256(answer) * 1e13; // 1e5 * 1e13 = 1e18;
    }
}