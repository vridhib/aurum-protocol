// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {AurumGold} from "../../src/AurumGold.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract AurumGoldTest is Test {
    AurumGold public token;
    address owner = makeAddr("owner");
    address user = makeAddr("user");
    address attacker = makeAddr("attacker");

    uint256 mintAmount = 10 ether;
    uint256 burnAmount = 5 ether;


    function setUp() public {
        vm.prank(owner);
        token = new AurumGold();
    }


    // Test constructor
    function testConstructor() public view {
        assertEq(token.name(), "Aurum Gold");
        assertEq(token.symbol(), "AUR");
        assertEq(token.totalSupply(), 0);
        assertEq(token.owner(), owner);
    }

    // Test that owner can mint
    function testMintAsOwner() public {
        vm.prank(owner);
        token.mint(user, mintAmount);

        assertEq(token.balanceOf(user), mintAmount);
        assertEq(token.totalSupply(), mintAmount);
    }

    // Test that non-owner cannot mint and reverts with OwnableUnauthorizedAccount
    function testRevertsWhenNonOwnerMints() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        token.mint(user, mintAmount);
    }

    // Test that a user can burn their own tokens
    function testUserCanBurnTheirTokens() public {
        vm.prank(owner);
        token.mint(user, mintAmount);

        vm.prank(user);
        token.burn(burnAmount);

        assertEq(token.balanceOf(user), mintAmount - burnAmount);
        assertEq(token.totalSupply(), mintAmount - burnAmount);
    }

    // Test that a user cannot burn more than their current balance and reverts with ERC20InsufficientBalance
    function testRevertsWhenBurnExceedsBalance() public {
        vm.prank(owner);
        token.mint(user, mintAmount);

        vm.prank(user);
        bytes4 selector = bytes4(keccak256("ERC20InsufficientBalance(address,uint256,uint256)"));
        vm.expectRevert(
            abi.encodeWithSelector(selector, user, mintAmount, mintAmount + 1)
        );
        token.burn(mintAmount + 1);
    }

    // Test transfer
    function testTransferSucceeds() public {
        vm.prank(owner);
        token.mint(user, mintAmount);

        vm.prank(user);
        uint256 transferAmount = 5 ether;
        token.transfer(attacker, transferAmount);

        assertEq(token.balanceOf(user), mintAmount - transferAmount);
        assertEq(token.balanceOf(attacker), transferAmount);
    }

    // Test approve and transferFrom
    function testApproveAndTransferFrom() public {
        vm.prank(owner);
        token.mint(user, mintAmount);

        vm.prank(user);
        uint256 approveAmount = 5 ether;
        token.approve(attacker, approveAmount);

        vm.prank(attacker);
        uint256 transferAmount = 3 ether;
        token.transferFrom(user, attacker, transferAmount);

        assertEq(token.balanceOf(user), mintAmount - transferAmount);
        assertEq(token.balanceOf(attacker), transferAmount);
        assertEq(token.allowance(user, attacker), approveAmount - transferAmount);
    }
}