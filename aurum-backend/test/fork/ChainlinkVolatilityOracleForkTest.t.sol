// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test, console2} from "forge-std/Test.sol";
import {ChainlinkVolatilityOracle} from "../../src/oracles/ChainlinkVolatilityOracle.sol";
import {OracleLib} from "../../src/libraries/OracleLib.sol";

contract ChainlinkVolatilityOracleForkTest is Test {
    // Real Sepolia ETH‑USD 24hr Realized Volatility feed address
    address constant FEED_ADDRESS = 0x31D04174D0e1643963b38d87f26b0675Bb7dC96e;

    function setUp() public {
        // Spin up a local fork of Sepolia
        vm.createSelectFork("sepolia");
    }

    function testWrapperReturnsFreshVolatilityOnFork() public {
        ChainlinkVolatilityOracle oracle = new ChainlinkVolatilityOracle(FEED_ADDRESS);

        // The real feed is stale on Sepolia, so mock a fresh answer
        // A value of 45600 with 5 decimals = 45.6% annualized
        vm.mockCall(
            FEED_ADDRESS,
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(
                uint80(1),          // roundId
                int256(45600),      // answer (45.6% with 5 decimals)
                block.timestamp,    // startedAt  
                block.timestamp,    // updatedAt 
                uint80(1)           // answeredInRound
            )
        );

        // Call the wrapper: it should return 0.456e18
        uint256 volatility = oracle.getAnnualizedVolatility();
        assertEq(volatility, 0.456e18);
    }
}