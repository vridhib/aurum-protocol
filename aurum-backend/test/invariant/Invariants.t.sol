// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployAUSD} from "../../script/DeployAUSD.s.sol";
import {AurumEngine} from "../../src/AurumEngine.sol";
import {AurumUSD} from "../../src/AurumUSD.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Handler} from "./Handler.t.sol";
import {OracleLib, AggregatorV3Interface} from "../../src/libraries/OracleLib.sol";


contract InvariantsTest is StdInvariant, Test {
    DeployAUSD deployer;
    AurumEngine aue;
    AurumUSD ausd;
    HelperConfig config;
    Handler handler;

    address[] internal collateralTokens;
    uint256 internal previousCumulativeIndex;

    using OracleLib for AggregatorV3Interface;


    function setUp() external {
        deployer = new DeployAUSD();
        (ausd, aue, config) = deployer.run();

        HelperConfig.NetworkConfig memory networkConfig = config.getActiveNetworkConfig();
        address goldUsdPriceFeed = networkConfig.collaterals[0].priceFeed;
        address ethUsdPriceFeed = networkConfig.collaterals[1].priceFeed;
        address aurumGold = networkConfig.collaterals[0].token;
        address weth = networkConfig.collaterals[1].token;

        address[] memory tokens = new address[](2);
        tokens[0] = aurumGold;
        tokens[1] = weth;
        address[] memory feeds = new address[](2);
        feeds[0] = goldUsdPriceFeed;
        feeds[1] = ethUsdPriceFeed;
        
        collateralTokens = tokens;
        
        handler = new Handler(aue, ausd, tokens, feeds);
        targetContract(address(handler));
    }


    // Invariant 1: The protocol must always be overcollateralized
    function invariant_protocolMustBeOvercollateralized() external view {
        (uint256 totalCollateralValue, ) = aue.getGlobalMetrics();
        uint256 totalActualDebt = 0;
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint256 normDebt = aue.getCollateralInfo(token).totalNormalizedDebt;
            totalActualDebt += (normDebt * aue.s_cumulativeIndex()) / 1e18;
        }

        console.log("Total Collateral Value:", totalCollateralValue);
        console.log("Total Actual Debt:", totalActualDebt);
        assert(totalCollateralValue >= totalActualDebt);
    }


    // Invariant 2: The cumulative index never decreases
    function invariant_cumulativeIndexNonDecreasing() external {
        uint256 currentIndex = aue.s_cumulativeIndex();
        assert(currentIndex >= previousCumulativeIndex);
        previousCumulativeIndex = currentIndex;
    }

    // Invariant 3: User actual debt = Σ normalized * index / 1e18
    function invariant_userActualDebtMatchesNormalized() external view {
        address[] memory users;
        uint256 currentIndex = aue.s_cumulativeIndex();
        for (uint256 i = 0; i < users.length; i++) {
            address user = handler.usersWithCollateralDeposited(i);
            uint256 expectedDebt = 0;
            for (uint256 j = 0; j < collateralTokens.length; j++) {
                uint256 norm = aue.getUserAccountData(user).debtAllocations[j];
                expectedDebt += (norm * currentIndex) / 1e18;
            }
            uint256 actualDebt = aue.getUserAccountData(user).totalDebt;
            assertEq(expectedDebt, actualDebt);
        }
    }


    // Invariant 4: Getter functions should never revert
    function invariant_gettersShouldNotRevert() external {
        address user = makeAddr("user");
        address token = collateralTokens[0];

        aue.getUsdValue(token, 1e18);
        aue.getTokenAmountFromUsd(token, 1e18);
        aue.getCollateralInfo(token);
        aue.getUserAccountData(user);
    }
}