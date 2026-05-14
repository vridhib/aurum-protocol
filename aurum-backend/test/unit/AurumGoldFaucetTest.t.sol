// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test, console} from "forge-std/Test.sol";
import {AurumGoldFaucet} from "../../src/faucet/AurumGoldFaucet.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployAUSD} from "../../script/DeployAUSD.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


contract AurumGoldFaucetTest is Test {
    DeployAUSD deployer;
    HelperConfig config;
    address aurumGold;
    AurumGoldFaucet faucet;
    
    uint256 fundAmount = 100_000e18;   // 100,000 AUR
    uint256 claimAmount = 10e18;       // 10 AUR
    address owner = makeAddr("owner");
    address user = makeAddr("user");

    function setUp() public {
        deployer = new DeployAUSD();
        (,, config) = deployer.run();
        HelperConfig.NetworkConfig memory networkConfig = config.getActiveNetworkConfig();
        aurumGold = networkConfig.collaterals[0].token;

        faucet = new AurumGoldFaucet(aurumGold);
        faucet.transferOwnership(owner); 

        vm.startPrank(owner);
        ERC20Mock(aurumGold).mint(owner, fundAmount);
        ERC20Mock(aurumGold).approve(address(faucet), fundAmount);
        faucet.fund(fundAmount);
        vm.stopPrank();
    }


    /********************************************************/
    /*******************One-time Claim Logic*****************/
    /********************************************************/
    function testClaim() public {
        vm.prank(user);
        faucet.claim();
        assertEq(ERC20Mock(aurumGold).balanceOf(user), claimAmount);
        assertTrue(faucet.s_hasClaimed(user));
    }

    function testRevertIfAlreadyClaimed() public {
        vm.prank(user);
        faucet.claim();

        vm.prank(user);
        vm.expectRevert(AurumGoldFaucet.AurumGoldFaucet__AlreadyClaimed.selector);
        faucet.claim();
    }

    function testResetClaimAndClaimAgain() public {
        vm.prank(user);
        faucet.claim();

        vm.prank(owner);
        vm.expectEmit(address(faucet));
        emit AurumGoldFaucet.ClaimReset(user);
        faucet.resetClaimStatus(user);

        vm.prank(user);
        faucet.claim();
        assertEq(ERC20Mock(aurumGold).balanceOf(user), claimAmount * 2);
    }

    function testOnlyOwnerCanResetClaimStatus() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        faucet.resetClaimStatus(user);
    }


    /********************************************************/
    /********************Set Claim Amount********************/
    /********************************************************/
    function testOwnerCannotSetClaimAmountToZero() public {
        vm.prank(owner);
        vm.expectRevert(AurumGoldFaucet.AurumGoldFaucet__NeedsMoreThanZero.selector);
        faucet.setClaimAmount(0 ether);
    }


    /********************************************************/
    /***********************Withdrawals**********************/
    /********************************************************/
    function testOnlyOwnerCanWithdraw() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        faucet.withdraw(100e18);

        vm.prank(owner);
        faucet.withdraw(100e18);
    }

    function testOwnerCannotWithdrawZero() public {
        vm.prank(owner);
        vm.expectRevert(AurumGoldFaucet.AurumGoldFaucet__NeedsMoreThanZero.selector);
        faucet.withdraw(0);
    }


    /********************************************************/
    /************************Funding************************/
    /********************************************************/
    function testOnlyOwnerCanFund() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        faucet.fund(claimAmount);
    }

    function testOwnerCannotFundWithZero() public {
        vm.prank(owner);
        vm.expectRevert(AurumGoldFaucet.AurumGoldFaucet__NeedsMoreThanZero.selector);
        faucet.fund(0);
    }

    /********************************************************/
    /*********************Balance/Supply*********************/
    /********************************************************/
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

    function testFaucetHasEnoughTokens() public view {
        assertGe(ERC20Mock(aurumGold).balanceOf(address(faucet)), fundAmount);
    }

    // Test that the claim amount should never exceed faucet balance
    function testClaimAmountWithinBalance(uint256 times) public {
        times = bound(times, 1, 900); // 900 claims * 100 = 90,000 < 100,000
        for (uint256 i = 0; i < times; i++) {
            address randUser = address(uint160(i + 1000));
            vm.prank(randUser);
            faucet.claim();
        }
        assertLe(ERC20Mock(aurumGold).balanceOf(address(faucet)), fundAmount - times * claimAmount);
    }
}