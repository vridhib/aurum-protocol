// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Vridhi Brahmbhatt
 * @notice This library is used to check the Chainlink Oracle for stale data.
 *         If a price is stale, the function will revert, and render the AurumEngine unusable--this is by design.
 *         We want the AurumEngine to freeze if prices become stale.
 * 
 *         So, if the Chainlink network explodes and you have a lot of money locked in the protocol...too bad.    
 */
library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours;

    /**
     * @notice Checks the latest round data from the Chainlink Price Feed
     * @dev Reverts if the price is stale (older than TIMEOUT) or if the data is invalid
     * @param priceFeed The address of the Chainlink AggregatorV3Interface contract
     * @return roundId The round ID
     * @return answer The price (int256)
     * @return startedAt Timestamp of when the round started
     * @return updatedAt Timestamp of when the round was updated
     * @return answeredInRound The round ID in which the answer was computed
     */
    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed) public view returns (uint80, int256, uint256, uint256, uint80) {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();

        if (updatedAt == 0 || answeredInRound < roundId) revert OracleLib__StalePrice();

        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) revert OracleLib__StalePrice();

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }


    /**
     * @notice Returns the configured staleness threshold for the price feed
     * @return The timeout in seconds
     */
    function getTimeout(AggregatorV3Interface /* chainlinkFeed */) public pure returns (uint256) {
        return TIMEOUT;
    }
}