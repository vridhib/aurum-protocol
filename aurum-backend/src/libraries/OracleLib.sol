// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @notice This library validates that the Chainlink price data is updated before usage.
 * @dev    AurumEngine relies on accurate, timely prices. If a price feed is stale, the
 *         protocol freezes. This is an intentional design to prevent the mispricing of 
 *         collateral and to protect the system during extreme oracle network failures.
 */
library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours; // 1 hour heartbeat + 2 hour safety margin

    /**
     * @notice Fetches the latest round data and reverts if the price is stale or invalid.
     * @param priceFeed The Chainlink AggregatorV3Interface to query.
     * @return roundId The round ID of the returned data.
     * @return answer The price in the feed's native decimals.
     * @return startedAt The timestamp when the round started.
     * @return updatedAt The timestamp when the round was last updated.
     * @return answeredInRound The round ID in which the answer was computed.
     */
    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        if (updatedAt == 0 || answeredInRound < roundId) revert OracleLib__StalePrice();

        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) revert OracleLib__StalePrice();

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    /// @notice Returns the staleness threshold used by the library.
    function getTimeout(AggregatorV3Interface /* chainlinkFeed */) public pure returns (uint256) {
        return TIMEOUT;
    }
}