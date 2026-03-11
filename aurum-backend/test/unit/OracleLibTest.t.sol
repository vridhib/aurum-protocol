// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {OracleLib, AggregatorV3Interface} from "../../src/libraries/OracleLib.sol";


contract OracleLibTest is StdCheats, Test {
    using OracleLib for AggregatorV3Interface;

    MockV3Aggregator public aggregator;
    uint8 public constant DECIMALS = 8;
    int256 public constant INITAL_PRICE = 2000 ether;


    function setUp() public {
        aggregator = new MockV3Aggregator(DECIMALS, INITAL_PRICE);
    }


    // Test the stale check reverts when the data is outdated (falls outside the timeout)
    function testPriceRevertsOnStaleCheck() public {
        vm.warp(block.timestamp + 4 hours + 1 seconds);
        vm.roll(block.number + 1);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
    }


    // Test the stale check does not revert when the data is fresh (within the timeout)
    function testStaleCheckWorksWhenPriceIsFresh() public view {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
        (uint80 expectedRoundId, int256 expectedAnswer, uint256 expectedStartedAt, uint256 expectedUpdatedAt, uint80 expectedAnsweredInRound) = aggregator.latestRoundData();

        assertEq(roundId, expectedRoundId);
        assertEq(answer, expectedAnswer);
        assertEq(startedAt, expectedStartedAt);
        assertEq(updatedAt, expectedUpdatedAt);
        assertEq(answeredInRound, expectedAnsweredInRound);
    }


    // Test a boundary case (exactly at the timeout)
    function testStaleCheckPassesAtExactly3Hours() public {
        // Warp time forward by exactly 3 hours
        vm.warp(block.timestamp + 3 hours);
        
        // Should NOT revert
        AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
    }


    // Test a boundary case (1 second past timeout)
    function testStaleCheckFailsAt3HoursAnd1Second() public {
        vm.warp(block.timestamp + 3 hours + 1 seconds);
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
    }


    // Test that the price reverts on bad answers in round data
    function testPriceRevertsOnBadAnsweredInRound() public {
        uint80 _roundId = 0;
        int256 _answer = 0;
        uint256 _timestamp = 0;
        uint256 _startedAt = 0;
        aggregator.updateRoundData(_roundId, _answer, _timestamp, _startedAt);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
    }


    // Test that getTimeout() returns 3 hours
    function testGetTimeout() public view {
        uint256 expectedTimeout = 3 hours;
        assertEq(OracleLib.getTimeout(AggregatorV3Interface(address(aggregator))), expectedTimeout);
    }
}