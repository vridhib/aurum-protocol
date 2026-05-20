// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {AurumTreasury} from "../../../src/treasury/AurumTreasury.sol";
import {AurumSavings} from "../../../src/treasury/AurumSavings.sol";
import {AurumUSD} from "../../../src/AurumUSD.sol";
import {BaseTest} from "../../shared/BaseTest.t.sol";

contract AurumTreasuryTest is BaseTest {
    address owner = makeAddr("owner");
    AurumSavings savings;
    address engine = makeAddr("engine");
    uint256 constant INITIAL_SUPPLY = 1_000_000e18;
    uint256 yieldAmount = 1000e18;

    function setUp() public override {
        vm.startPrank(owner);
        ausd = new AurumUSD();
        ausd.mint(owner, INITIAL_SUPPLY);
        engine = makeAddr("engine");
        treasury = new AurumTreasury(address(ausd));
        savings = new AurumSavings(address(ausd), address(treasury));
        ausd.transfer(address(treasury), INITIAL_SUPPLY);
        vm.stopPrank();
    }

    modifier initializeAddresses {
        vm.prank(owner);
        treasury.initializeAddresses(address(savings), engine);
        _;
    }

    // ------------ setSavings() Tests ------------
    function testOwnerCanInitializeAddresses() public {
        vm.prank(owner);
        treasury.initializeAddresses(address(savings), engine);
        assertEq(treasury.getSavings(), address(savings));
    }

    function testRevertIfNonOwnerCallsInitializeAddresses() public {
        vm.prank(user);
        vm.expectRevert();
        treasury.initializeAddresses(address(savings), engine);
    }

    function testRevertIfOwnerCallsInitializeAddressesTwice() public {
        vm.startPrank(owner);
        treasury.initializeAddresses(address(savings), engine);

        vm.expectRevert(AurumTreasury.AurumTreasury__AlreadyInitialized.selector);
        treasury.initializeAddresses(address(savings), engine);
        vm.stopPrank();
    }

    // ------------ distributeYield() Tests ------------
    function testRevertIfNonOwnerDistributesYield() public initializeAddresses {
        vm.prank(user);
        vm.expectRevert();
        treasury.distributeYield(yieldAmount);
    }

    function testOwnerCanDistributeYield() public initializeAddresses {
        vm.prank(owner);
        treasury.distributeYield(yieldAmount);

        assertEq(ausd.balanceOf(address(savings)), yieldAmount);
        assertEq(ausd.balanceOf(address(treasury)), INITIAL_SUPPLY - yieldAmount);
    }

    function testDistributeYieldInsufficientReserves() public initializeAddresses {
        vm.prank(owner);
        vm.expectRevert(AurumTreasury.AurumTreasury__InsufficientReserves.selector);
        treasury.distributeYield(INITIAL_SUPPLY + 1);
    }
}