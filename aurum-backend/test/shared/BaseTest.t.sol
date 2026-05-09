// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test, console2} from "forge-std/Test.sol";
import {DeployAUSD} from "../../script/DeployAUSD.s.sol";
import {AurumUSD} from "../../src/AurumUSD.sol";
import {AurumEngine} from "../../src/AurumEngine.sol";
import {InterestRateModel} from "../../src/interest/InterestRateModel.sol";
import {AurumTreasury} from "../../src/treasury/AurumTreasury.sol";
import {AurumSavings} from "../../src/treasury/AurumSavings.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract BaseTest is Test {
    DeployAUSD internal deployer;
    AurumUSD internal ausd;
    AurumEngine internal aue;
    InterestRateModel internal interestRateModel;
    AurumTreasury internal treasury;
    HelperConfig internal config;
    address internal goldUsdPriceFeed;
    address internal ethUsdPriceFeed;
    address internal goldVolatilityFeed;
    address internal ethVolatilityFeed;
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
    uint256 internal largeAUSDAmount = 40000 ether;
    uint256 internal debtToCover;
    uint256 internal partialCollateralToRedeem = 1 ether;

    uint256 internal constant STARTING_ERC20_BALANCE = 100 ether;
    uint256 internal constant LIQUIDATION_THRESHOLD = 80;
    uint256 internal constant LIQUIDATION_PRECISION = 100;
    uint256 internal constant MIN_HEALTH_FACTOR = 1e18;
    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant PROTOCOL_FEE_PRECISION = 100;
    uint256 internal constant ONE_AUSD = 1e18;
    uint256 internal constant ONE_AUR = 1e18;
    uint256 internal constant ONE_WETH = 1e18;
    uint256 internal constant ONE_YEAR = 365 days;

    function setUp() public virtual {
        deployer = new DeployAUSD();
        (ausd, aue, config) = deployer.run();
        interestRateModel = InterestRateModel(aue.i_interestRateModel());
        treasury = AurumTreasury(aue.i_treasury());

        HelperConfig.NetworkConfig memory networkConfig = config.getActiveNetworkConfig();
        goldUsdPriceFeed = networkConfig.collaterals[0].priceFeed;
        ethUsdPriceFeed = networkConfig.collaterals[1].priceFeed;
        goldVolatilityFeed = networkConfig.collaterals[0].volatilityFeed;
        ethVolatilityFeed = networkConfig.collaterals[1].volatilityFeed;
        aurumGold = networkConfig.collaterals[0].token;
        weth = networkConfig.collaterals[1].token;

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



    function getMaxSafeMint() internal view returns (uint256) {
        uint256 goldUsd = aurAmount * uint256(goldPrice);
        uint256 wethUsd = wethAmount * uint256(wethPrice);
        uint256 goldLtv = aue.getCollateralInfo(aurumGold).ltv;
        uint256 wethLtv = aue.getCollateralInfo(weth).ltv;

        return (goldUsd * goldLtv + wethUsd * wethLtv) / LIQUIDATION_PRECISION;
    }

    // Helper to generate fresh price feed data (using current block.timestamp)
    function _getFreshPriceData(int256 price) internal view returns (bytes memory) {
        return abi.encode(
            uint80(1),               // roundId
            price,                   // answer (e.g., goldPrice * 1e8)
            block.timestamp,         // startedAt
            block.timestamp,         // updatedAt (fresh)
            uint80(1)                // answeredInRound
        );
    }

    // Helper to mock all price feeds used by the engine with fresh timestamps
    function _bypassStalePriceChecks() internal {
        bytes memory goldMock = _getFreshPriceData(int256(goldPrice * 1e8));
        bytes memory ethMock = _getFreshPriceData(int256(wethPrice * 1e8));

        vm.mockCall(goldUsdPriceFeed, abi.encodeWithSignature("latestRoundData()"), goldMock);
        vm.mockCall(ethUsdPriceFeed, abi.encodeWithSignature("latestRoundData()"), ethMock);
    }

    // Helper to set up a user account with specified collateral and AUSD amounts
    function _setUpUserAccount(uint256 amountOfAur, uint256 amountOfWeth, uint256 mintAmount) internal {
        vm.startPrank(user);
        if (amountOfAur > 0) {
            ERC20Mock(aurumGold).mint(user, amountOfAur);
            ERC20Mock(aurumGold).approve(address(aue), amountOfAur);
            aue.depositCollateral(aurumGold, amountOfAur);
        }
        if (amountOfWeth > 0) {
            ERC20Mock(weth).mint(user, amountOfWeth);
            ERC20Mock(weth).approve(address(aue), amountOfWeth);
            aue.depositCollateral(weth, amountOfWeth);
        }
        if (amountOfAur > 0 || amountOfWeth > 0) aue.mintAUSD(mintAmount);
        vm.stopPrank();
    }
}