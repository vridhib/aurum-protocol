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
        (address goldPriceFeed, address wethPriceFeed, address goldToken, address weth, ) = config.activeNetworkConfig();

        address[] memory tokens = new address[](2);
        tokens[0] = goldToken;
        tokens[1] = weth;
        address[] memory feeds = new address[](2);
        feeds[0] = goldPriceFeed;
        feeds[1] = wethPriceFeed;
        
        collateralTokens = tokens;
        
        handler = new Handler(aue, ausd, tokens, feeds);
        targetContract(address(handler));
    }


    // Invariant 1: The protocol must always be overcollateralized
    function invariant_protocolMustBeOvercollateralized() external view {
        uint256 totalCollateralValue = aue.getTotalProtocolCollateralValue();
        uint256 totalActualDebt = 0;
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint256 normDebt = aue.getCollateralTotalDebt(token);
            totalActualDebt += (normDebt * aue.getCumulativeIndex()) / 1e18;
        }

        console.log("Total Collateral Value:", totalCollateralValue);
        console.log("Total Actual Debt:", totalActualDebt);
        assert(totalCollateralValue >= totalActualDebt);
    }


    // Invariant 2: The cumulative index never decreases
    function invariant_cumulativeIndexNonDecreasing() external {
        uint256 currentIndex = aue.getCumulativeIndex();
        assert(currentIndex >= previousCumulativeIndex);
        previousCumulativeIndex = currentIndex;
    }

    // Invariant 3: User actual debt = Σ normalized * index / 1e18
    function invariant_userActualDebtMatchesNormalized() external view {
        address[] memory users;
        uint256 currentIndex = aue.getCumulativeIndex();
        for (uint256 i = 0; i < users.length; i++) {
            address user = handler.usersWithCollateralDeposited(i);
            uint256 expectedDebt = 0;
            for (uint256 j = 0; j < collateralTokens.length; j++) {
                uint256 norm = aue.getUserDebtAllocation(user, collateralTokens[j]);
                expectedDebt += (norm * currentIndex) / 1e18;
            }
            uint256 actualDebt = aue.getCurrentUserDebt(user);
            assertEq(expectedDebt, actualDebt);
        }
    }


    // Invariant 4: Getter functions should never revert
    function invariant_gettersShouldNotRevert() external {
        address user = makeAddr("user");
        address token = collateralTokens[0];

        aue.getUsdValue(token, 1e18);
        aue.getCurrentUserDebt(user);
        aue.getCumulativeIndex();
        aue.getTreasury();
        aue.getAUSD();
        aue.getCollateralTotalDebt(token);
        aue.getCollateralTokenPriceFeed(token);
        aue.getAccountInformation(user);
        aue.getAccountCollateralValueInUsd(user);
        aue.getTotalProtocolCollateralValue();
    }
}