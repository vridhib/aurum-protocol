// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AurumUSD} from "../../src/AurumUSD.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";


contract AurumTest is StdCheats, Test {
    AurumUSD ausd;

    function setUp() public {
        ausd = new AurumUSD();
    }

    /**************************************************************************/
    /********************************Mint Tests********************************/
    /**************************************************************************/
    function testMustMintMoreThanZero() public {
        vm.prank(ausd.owner());
        vm.expectRevert(AurumUSD.AurumUSD__MustBeMoreThanZero.selector);
        ausd.mint(address(this), 0);
    }

    function testCantMintToZeroAddress() public {
        vm.startPrank(ausd.owner());
        vm.expectRevert(AurumUSD.AurumUSD__NotZeroAddress.selector);
        ausd.mint(address(0), 100);
        vm.stopPrank();
    }


    /**************************************************************************/
    /********************************Burn Tests********************************/
    /**************************************************************************/
    function testMustBurnMoreThanZero() public {
        vm.startPrank(ausd.owner());
        ausd.mint(address(this), 100);
        vm.expectRevert(AurumUSD.AurumUSD__MustBeMoreThanZero.selector);
        ausd.burn(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanYouHave() public {
        vm.startPrank(ausd.owner());
        ausd.mint(address(this), 100);
        vm.expectRevert(AurumUSD.AurumUSD__BurnAmountExceedsBalance.selector);
        ausd.burn(101);
        vm.stopPrank();
    }
}