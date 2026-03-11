// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {AurumGoldFaucet} from "../../src/AurumGoldFaucet.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployAUSD} from "../../script/DeployAUSD.s.sol";
import {DeployAurumGoldFaucet} from "../../script/DeployAurumGoldFaucet.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


contract AurumGoldFaucetTest is Test {
    DeployAUSD protocolDeployer;
    DeployAurumGoldFaucet faucetDeployer;
    HelperConfig config;
    address aurumGold;
    AurumGoldFaucet public faucet;
    
    uint256 fundAmount = 100_000 ether;     //100,000 AUR
    uint256 claimAmount = 10 ether;         // 10 AUR
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");


    function setUp() public {
        protocolDeployer = new DeployAUSD();
        (,, config) = protocolDeployer.run();
        (, aurumGold,) = config.activeNetworkConfig(); 

        faucet = new AurumGoldFaucet(aurumGold);
        faucet.transferOwnership(owner); 

        vm.startPrank(owner);
        ERC20Mock(aurumGold).mint(owner, fundAmount);
        ERC20Mock(aurumGold).approve(address(faucet), fundAmount);
        faucet.fund(fundAmount);
        vm.stopPrank();
    }

    // Test that users can claim AUR from the faucet for the first time
    function testClaim() public {
        vm.prank(user);
        faucet.claim();
        assertEq(ERC20Mock(aurumGold).balanceOf(user), claimAmount);
    }

    // Test that users cannot claim AUR tokens from the faucet in succession before the cooldown period has passed 
    function testCannotClaimTwiceBeforeCooldown() public {
        vm.prank(user);
        faucet.claim();
        vm.prank(user);
        vm.expectRevert(AurumGoldFaucet.AurumGoldFaucet__CooldownPeriodHasNotPassed.selector);
        faucet.claim();
    }

    // Test that users can claim AUR tokens after the cooldown period
    function testCanClaimAfterCooldown() public {
        vm.prank(user);
        faucet.claim();
        vm.warp(block.timestamp + 1 days);
        vm.prank(user);
        faucet.claim();
        assertEq(ERC20Mock(aurumGold).balanceOf(user), claimAmount * 2);
    }

    // Test that only the owner can set the faucet's claim amount
    function testOnlyOwnerCanSetClaimAmount() public {
        vm.prank(user);
        vm.expectRevert();
        faucet.setClaimAmount(200 ether);
        vm.prank(owner);
        faucet.setClaimAmount(200 ether);
        assertEq(faucet.claimAmount(), 200 ether);
    }

    // Test that the owner cannot set the claim amount to 0
    function testOwnerCannotSetClaimAmountToZero() public {
        vm.prank(owner);
        vm.expectRevert(AurumGoldFaucet.AurumGoldFaucet__NeedsMoreThanZero.selector);
        faucet.setClaimAmount(0 ether);
    }

    // Test that only the owner can set the faucet's cooldown period
    function testOnlyOwnerCanSetCooldown() public {
        vm.prank(user);
        vm.expectRevert();
        faucet.setCooldown(2 days);

        vm.prank(owner);
        faucet.setCooldown(2 days);
        assertEq(faucet.cooldown(), 2 days);
    }

    // Test that the owner cannot set the cooldown period to 0
    function testOwnerCannotSetCooldownToZero() public {
        vm.prank(owner);
        vm.expectRevert(AurumGoldFaucet.AurumGoldFaucet__NeedsMoreThanZero.selector);
        faucet.setCooldown(0 days);
    }

    // Test that only the owner can withdraw AUR tokens from the faucet
    function testOnlyOwnerCanWithdraw() public {
        vm.prank(user);
        vm.expectRevert();
        faucet.withdraw(100 ether);

        vm.prank(owner);
        faucet.withdraw(100 ether);
    }

    // Test that the owner cannot withdraw 0 AUR
    function testOwnerCannotWithdrawZeroAUR() public {
        vm.prank(owner);
        vm.expectRevert(AurumGoldFaucet.AurumGoldFaucet__NeedsMoreThanZero.selector);
        faucet.withdraw(0 ether);
    }

    // Test that only the owner can fund 
    function testOnlyOwnerCanFund() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        faucet.fund(claimAmount);
    }

    // Test that the owner cannot fund with 0 AUR
    function testOwnerCannotFundWithZeroAUR() public {
        vm.prank(owner);
        vm.expectRevert(AurumGoldFaucet.AurumGoldFaucet__NeedsMoreThanZero.selector);
        faucet.fund(0 ether);
    }

    // Test that the faucet reverts if the faucet is out of AUR
    function testFaucetRevertsIfNotEnoughTokens() public {
        vm.prank(owner);
        faucet.withdraw(fundAmount);

        vm.prank(user);
        bytes4 selector = bytes4(keccak256("ERC20InsufficientBalance(address,uint256,uint256)"));
        vm.expectRevert(
            abi.encodeWithSelector(selector, address(faucet), 0, claimAmount)
        );
        faucet.claim();
    }

    // Test that the faucet has enough AUR tokens
    function testFaucetHasEnoughTokens() public view {
        assertGe(ERC20Mock(aurumGold).balanceOf(address(faucet)), fundAmount);
    }

    // Test that the claim amount should never exceed faucet balance
    function testClaimAmountWithinBalance(uint256 times) public {
        times = bound(times, 1, 900); // 900 claims * 100 = 90,000 < 100,000
        for (uint256 i = 0; i < times; i++) {
            address randUser = address(uint160(i + 1000));
            vm.warp(block.timestamp + 1 days * i);
            vm.prank(randUser);
            faucet.claim();
        }
        assertLe(ERC20Mock(aurumGold).balanceOf(address(faucet)), ERC20Mock(aurumGold).totalSupply());
    }
}