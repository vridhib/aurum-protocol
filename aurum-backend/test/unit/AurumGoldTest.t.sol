// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test, console2} from "forge-std/Test.sol";
import {AurumGold} from "../../src/AurumGold.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract AurumGoldTest is Test {
    AurumGold public token;

    address deployer = makeAddr("deployer"); 
    address custodian = makeAddr("custodian");
    address pauser = makeAddr("pauser");
    address user = makeAddr("user");
    address attacker = makeAddr("attacker");

    uint256 mintOunces = 10e18;   // 10 ounces (1 AUR = 1 ounce)
    uint256 burnOunces = 5e18;    // 5 ounces

    bytes32 CUSTODIAN_ROLE;
    bytes32 PAUSER_ROLE;

    function setUp() public {
        vm.prank(deployer);
        token = new AurumGold();

        CUSTODIAN_ROLE = token.CUSTODIAN_ROLE();
        PAUSER_ROLE = token.PAUSER_ROLE();

        vm.startPrank(deployer);
        token.grantRole(CUSTODIAN_ROLE, custodian);
        token.grantRole(PAUSER_ROLE, pauser);
        vm.stopPrank();
    }

    /********************************************************/
    /***********************Constructor**********************/
    /********************************************************/
    function testConstructor() public view {
        assertEq(token.name(), "Aurum Gold");
        assertEq(token.symbol(), "AUR");
        assertEq(token.totalSupply(), 0);
        // Deployer holds all 3 roles initially
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), deployer));
        assertTrue(token.hasRole(CUSTODIAN_ROLE, deployer));
        assertTrue(token.hasRole(PAUSER_ROLE, deployer));
    }


    /********************************************************/
    /*************************Minting************************/
    /********************************************************/
    function testMintFromGoldDepositSucceeds() public {
        uint256 initialOunces = token.getTotalGoldOunces();

        vm.prank(custodian);
        vm.expectEmit(address(token));
        emit AurumGold.GoldDeposited(user, mintOunces, mintOunces);
        token.mintFromGoldDeposit(user, mintOunces);

        assertEq(token.balanceOf(user), mintOunces);
        assertEq(token.totalSupply(), mintOunces);
        assertEq(token.getTotalGoldOunces(), initialOunces + mintOunces);
    }

    function testMintRevertsIfNotCustodian() public {
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                CUSTODIAN_ROLE
            )
        );
        token.mintFromGoldDeposit(user, mintOunces);
    }

    function testMintRevertsIfZeroOunces() public {
        vm.prank(custodian);
        vm.expectRevert(AurumGold.AurumGold__NeedsMoreThanZero.selector);
        token.mintFromGoldDeposit(user, 0);
    }

    /********************************************************/
    /*************************Burning************************/
    /********************************************************/
    function testBurnForGoldWithdrawalSucceeds() public {
        vm.prank(custodian);
        token.mintFromGoldDeposit(custodian, mintOunces);
        uint256 initialOunces = token.getTotalGoldOunces();

        vm.prank(custodian);
        vm.expectEmit(address(token));
        emit AurumGold.GoldWithdrawn(custodian, burnOunces, burnOunces);
        token.burnForGoldWithdrawal(burnOunces);

        assertEq(token.balanceOf(custodian), mintOunces - burnOunces);
        assertEq(token.totalSupply(), mintOunces - burnOunces);
        assertEq(token.getTotalGoldOunces(), initialOunces - burnOunces);
    }

    function testBurnRevertsIfNotCustodian() public {
        vm.prank(custodian);
        token.mintFromGoldDeposit(attacker, mintOunces);

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                CUSTODIAN_ROLE
            )
        );
        token.burnForGoldWithdrawal(burnOunces);
    }

    function testBurnRevertsIfInsufficientBalance() public {
        vm.prank(custodian);
        token.mintFromGoldDeposit(custodian, mintOunces);

        vm.prank(custodian);
        vm.expectRevert(AurumGold.AurumGold__InsufficientBalance.selector);
        token.burnForGoldWithdrawal(mintOunces + 1);
    }

    function testBurnRevertsIfZero() public {
        vm.prank(custodian);
        vm.expectRevert(AurumGold.AurumGold__NeedsMoreThanZero.selector);
        token.burnForGoldWithdrawal(0);
    }


    /********************************************************/
    /*********************Pause & Unpause********************/
    /********************************************************/
    function testPauseAndUnpause() public {
        vm.prank(pauser);
        token.pause();
        assertTrue(token.paused());

        vm.prank(pauser);
        token.unpause();
        assertFalse(token.paused());
    }

    function testOnlyPauserCanPause() public {
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                PAUSER_ROLE
            )
        );
        token.pause();
    }

    function testMintRevertsWhenPaused() public {
        vm.prank(pauser);
        token.pause();

        vm.prank(custodian);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.mintFromGoldDeposit(user, mintOunces);
    }

    function testBurnRevertsWhenPaused() public {
        vm.prank(custodian);
        token.mintFromGoldDeposit(custodian, mintOunces);

        vm.prank(pauser);
        token.pause();

        vm.prank(custodian);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.burnForGoldWithdrawal(burnOunces);
    }

    function testTransferRevertsWhenPaused() public {
        vm.prank(custodian);
        token.mintFromGoldDeposit(user, mintOunces);

        vm.prank(pauser);
        token.pause();

        vm.prank(user);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.transfer(attacker, 1e18);
    }

    /********************************************************/
    /***********************Transfers************************/
    /********************************************************/
    function testTransferSucceeds() public {
        vm.prank(custodian);
        token.mintFromGoldDeposit(user, mintOunces);

        uint256 transferAmount = 5e18;
        vm.prank(user);
        token.transfer(attacker, transferAmount);

        assertEq(token.balanceOf(user), mintOunces - transferAmount);
        assertEq(token.balanceOf(attacker), transferAmount);
    }

    function testApproveAndTransferFrom() public {
        vm.prank(custodian);
        token.mintFromGoldDeposit(user, mintOunces);

        uint256 approveAmount = 5e18;
        vm.prank(user);
        token.approve(attacker, approveAmount);

        uint256 transferAmount = 3e18;
        vm.prank(attacker);
        token.transferFrom(user, attacker, transferAmount);

        assertEq(token.balanceOf(user), mintOunces - transferAmount);
        assertEq(token.balanceOf(attacker), transferAmount);
        assertEq(token.allowance(user, attacker), approveAmount - transferAmount);
    }

    /********************************************************/
    /********************Reserve Tracking********************/
    /********************************************************/
    function testReserveBalanced() public {
        vm.startPrank(custodian);
        token.mintFromGoldDeposit(user, mintOunces);
        token.mintFromGoldDeposit(user, 5e18);
        vm.stopPrank();
        assertTrue(token.isReserveBalanced());
    }
}