// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IVolatilityOracle} from "./IVolatilityOracle.sol";
import {OracleLib} from "../libraries/OracleLib.sol";


/**
 * @title ChainlinkVolatilityOracle
 * @notice Adapts a Chainlink realized-volatility data feed into the IVolatilityOracle interface.
 * @dev The underlying feed uses 5 decimals. This contracts scales the answer to 18-decimal precision, so the engine sees annualized volatility as a standard (1e18) precision value.
 */
contract ChainlinkVolatilityOracle is IVolatilityOracle {
    using OracleLib for AggregatorV3Interface;

    AggregatorV3Interface private immutable i_priceFeed;
    uint256 private immutable i_decimals;

    /// @param priceFeed The Chainlink AggregatorV3Interface address of the realized-volatility feed.
    constructor(address priceFeed) {
        i_priceFeed = AggregatorV3Interface(priceFeed);
    }

    /// @inheritdoc IVolatilityOracle
    /// @return volatility as a decimal with 18 decimals, e.g., 0.3e18 = 30% annualized volatility
    function getAnnualizedVolatility() external view override returns (uint256) {
        (,int256 answer,,,) = i_priceFeed.staleCheckLatestRoundData();

        return uint256(answer) * 1e13;
    }
}