// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {ChainlinkVolatilityOracle} from "../../../src/oracles/ChainlinkVolatilityOracle.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";
import {OracleLib} from "../../../src/libraries/OracleLib.sol";

contract ChainlinkVolatilityOracleTest is Test {
    ChainlinkVolatilityOracle oracle;
    MockV3Aggregator feed;

    function setUp() public {
        feed = new MockV3Aggregator(5, int256(45600)); // 45.6%
        oracle = new ChainlinkVolatilityOracle(address(feed));
    }

    function testConversionMath() public view {
        uint256 vol = oracle.getAnnualizedVolatility();
        assertEq(vol, 0.456e18);
    }

    function testRevertsWhenStale() public {
        vm.warp(block.timestamp + 30 days + 1 seconds);
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        oracle.getAnnualizedVolatility();
    }
}