// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {MockVolatilityOracle} from "../../../src/oracles/MockVolatilityOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockVolatilityOracleTest is Test {
    MockVolatilityOracle oracle;
    address owner = makeAddr("owner");
    address attacker = makeAddr("attacker");

    function setUp() public {
        vm.prank(owner);
        oracle = new MockVolatilityOracle(0.15e18);
    }

    function testConstructorSetsInitialVolatility() public view {
        assertEq(oracle.getAnnualizedVolatility(), 0.15e18);
    }

    function testSetVolatilityUpdatesValue() public {
        vm.prank(owner);
        oracle.setVolatility(0.25e18);
        assertEq(oracle.getAnnualizedVolatility(), 0.25e18);
    }

    function testSetVolatilityRevertsIfNotOwner() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        oracle.setVolatility(0.25e18);
    }
}