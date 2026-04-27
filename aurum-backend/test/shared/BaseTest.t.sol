// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test, console} from "forge-std/Test.sol";
import {DeployAUSD} from "../../script/DeployAUSD.s.sol";
import {AurumUSD} from "../../src/AurumUSD.sol";
import {AurumEngine} from "../../src/AurumEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract BaseTest is Test {
    DeployAUSD internal deployer;
    AurumUSD internal ausd;
    AurumEngine internal aue;
    HelperConfig internal config;
    address internal goldUsdPriceFeed;
    address internal ethUsdPriceFeed;
    address internal aurumGold;
    address internal weth;

    address internal user = makeAddr("user");
    address internal liquidator = makeAddr("liquidator");

    int256 internal goldPrice = 5000;
    int256 internal wethPrice = 2000;
    uint256 internal amountCollateral = 100 ether;
    uint256 internal aurAmount = 60 ether;
    uint256 internal wethAmount = 40 ether;
    uint256 internal amountAUSD = 10 ether;
    uint256 internal debtToCover;
    uint256 internal partialCollateralToRedeem = 1 ether;

    uint256 internal constant STARTING_ERC20_BALANCE = 100 ether;
    uint256 internal constant LIQUIDATION_THRESHOLD = 80;
    uint256 internal constant LIQUIDATION_PRECISION = 100;
    uint256 internal constant MIN_HEALTH_FACTOR = 1e18;
    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant ONE_AUSD = 1e18;
    uint256 internal constant ONE_AUR = 1e18;
    uint256 internal constant ONE_WETH = 1e18;

    function setUp() public virtual {
        deployer = new DeployAUSD();
        (ausd, aue, config) = deployer.run();
        (goldUsdPriceFeed, ethUsdPriceFeed, aurumGold, weth,) = config.activeNetworkConfig();

        ERC20Mock(aurumGold).mint(user, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(user, STARTING_ERC20_BALANCE);

        ERC20Mock(aurumGold).mint(liquidator, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(liquidator, STARTING_ERC20_BALANCE);
    }

    // Modifiers
    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), aurAmount);
        aue.depositCollateral(aurumGold, aurAmount);

        ERC20Mock(weth).approve(address(aue), wethAmount);
        aue.depositCollateral(weth, wethAmount);
        vm.stopPrank();
        _;
    }

    modifier depositedSingleCollateral() {
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        aue.depositCollateral(aurumGold, amountCollateral);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndMintedAUSD(uint256 amountOfAusd) {
        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), aurAmount);
        ERC20Mock(weth).approve(address(aue), wethAmount);

        ausd.approve(address(aue), amountOfAusd);
        aue.depositCollateralAndMintAUSD(aurumGold, aurAmount, amountOfAusd / 2);
        aue.depositCollateralAndMintAUSD(weth, wethAmount, amountOfAusd / 2);
        vm.stopPrank();
        _;
    }

    modifier liquidated {
        uint256 collateralValueUsd = (amountCollateral * uint256(goldPrice));
        uint256 aurToMint = ((collateralValueUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION);

        vm.startPrank(user);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), aurToMint);
        aue.depositCollateralAndMintAUSD(aurumGold, amountCollateral, aurToMint);
        vm.stopPrank();

        debtToCover = aurToMint;  
        vm.startPrank(liquidator);
        ERC20Mock(aurumGold).approve(address(aue), amountCollateral);
        ausd.approve(address(aue), debtToCover);
        aue.depositCollateralAndMintAUSD(aurumGold, amountCollateral, debtToCover);

        MockV3Aggregator(goldUsdPriceFeed).updateAnswer(4950e8);
        aue.liquidate(aurumGold, user, aurToMint); 
        vm.stopPrank();
        _;
    }

    function getMaxSafeMint() internal view returns (uint256) {
        uint256 goldUsd = aurAmount * uint256(goldPrice);
        uint256 wethUsd = wethAmount * uint256(wethPrice);
        uint256 totalUsd = goldUsd + wethUsd;
        return (totalUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
    }
}