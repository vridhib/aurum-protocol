// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {console2} from "forge-std/Test.sol";
import {BaseTest} from "../../shared/BaseTest.t.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";
import {AurumEngine} from "../../../src/AurumEngine.sol";

contract DepositTests is BaseTest {
    // Test that depositCollateral() reverts if the ERC20 transferFrom returns false
    function testDepositCollateralRevertsIfTransferFails() public {
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);

        // Prepare the data for the mock call
        bytes memory data = abi.encodeWithSignature("transferFrom(address,address,uint256)", user, address(aue), amountCollateral);
        // Mock the call: when AurumEngine calls transferFrom on aurumGold with this specific data, force it to return false
        vm.mockCall(aurumGold, data, abi.encode(false));

        vm.expectRevert(AurumEngine.AurumEngine__TransferFailed.selector);
        aue.depositCollateral(aurumGold, amountCollateral);
    }

    // Test that depositCollateral() reverts if the user deposits 0 collateral
    function testRevertsIfUserDepositsZeroCollateral() public {
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        vm.expectRevert(AurumEngine.AurumEngine__NeedsMoreThanZero.selector);
        aue.depositCollateral(aurumGold, 0);
        vm.stopPrank();
    }

    // Test that depositCollateral() reverts if the user deposits an unsupported token
    function testCannotDepositUnsupportedToken() public {
        ERC20Mock wrongGoldToken = new ERC20Mock();
        vm.expectRevert(abi.encodeWithSelector(AurumEngine.AurumEngine__TokenNotAllowed.selector, wrongGoldToken));
        aue.depositCollateral(address(wrongGoldToken), amountCollateral);
    }

    // Test that depositCollateral() allows user to deposit collateral and updates account info
    function testUserCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        AurumEngine.UserAccountData memory userAccountInfo = aue.getUserAccountData(user);

        uint256 expectedTotalAUSDMinted = 0;
        uint256 actualTotalAUSDMinted = userAccountInfo.totalDebt;
        uint256 expectedDepositValue = aurAmount * uint256(goldPrice) + wethAmount * uint256(wethPrice);
        uint256 actualDepositValue = userAccountInfo.totalCollateralValueInUsd;

        assertEq(expectedTotalAUSDMinted, actualTotalAUSDMinted);
        assertEq(expectedDepositValue, actualDepositValue);
    }

    // Test that depositCollateral() allows deposits of different collaterals
    function testDepositTwoCollaterals() public depositedCollateral {
        AurumEngine.UserAccountData memory userAccountInfo = aue.getUserAccountData(user);
        uint256 aurBalance = userAccountInfo.collateralAmounts[0];
        uint256 wethBalance = userAccountInfo.collateralAmounts[1];

        assertEq(aurBalance, aurAmount);
        assertEq(wethBalance, wethAmount);
    }

    // Test that depositCollateral() using inactive token reverts
    function testDepositInactiveTokenReverts() public {
        vm.prank(aue.owner());
        aue.setCollateralInfo(weth, address(0), address(0), 0, 0, false);

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(aue), amountCollateral);
        vm.expectRevert(abi.encodeWithSelector(AurumEngine.AurumEngine__TokenNotAllowed.selector, weth));
        aue.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
    }
}