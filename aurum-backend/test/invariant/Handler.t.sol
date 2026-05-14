// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test, console} from "forge-std/Test.sol";
import {AurumEngine} from "../../src/AurumEngine.sol";
import {AurumUSD} from "../../src/AurumUSD.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";


contract Handler is Test {
    AurumEngine public aue;
    AurumUSD public ausd;
    address public goldToken;
    address public goldPriceFeed;

    address[] public collateralTokens;
    mapping(address => address) public tokenPriceFeeds; 

    address[] public usersWithCollateralDeposited;
    
    uint256 public constant MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public constant MIN_PRICE = 100e8; 
    uint256 public constant MAX_PRICE = 100000e8;

    constructor(
        AurumEngine _ausdEngine, 
        AurumUSD _ausd, 
        address[] memory _collateralTokens, 
        address[] memory _tokenPriceFeeds
    ) 
    {
        require(_collateralTokens.length == _tokenPriceFeeds.length);
        for (uint256 i = 0; i < _collateralTokens.length; i++) {
            collateralTokens.push(_collateralTokens[i]);
            tokenPriceFeeds[_collateralTokens[i]] = _tokenPriceFeeds[i];
        }
        aue = _ausdEngine;
        ausd = _ausd;
    }

    // Helpers:
    function _getUserTotalBorrowingPower(address user) internal view returns (uint256) {
        uint256 totalPower;
        AurumEngine.UserAccountData memory userData = aue.getUserAccountData(user);
        
        for (uint256 i = 0; i < userData.activeCollateralTokens.length; i++) {
            uint256 deposited = userData.collateralAmounts[i];
            if (deposited == 0) continue;

            address token = userData.activeCollateralTokens[i];
            uint256 usdValue = aue.getUsdValue(token, deposited);
            uint256 ltv = aue.getCollateralInfo(token).ltv;
            totalPower += (usdValue * ltv) / 100;
        }
        return totalPower;
    }

    function getUserCount() external view returns (uint256) {
        return usersWithCollateralDeposited.length;
    }



    function depositCollateral(uint256 tokenSeed, uint256 amountCollateral) public {
        address token = collateralTokens[tokenSeed % collateralTokens.length];
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        // Fund the user
        vm.startPrank(msg.sender);
        ERC20Mock(token).mint(msg.sender, amountCollateral);
        ERC20Mock(token).approve(address(aue), amountCollateral);
        aue.depositCollateral(token, amountCollateral);
        vm.stopPrank();

        // Track unique users
        bool found;
        for (uint256 i = 0; i < usersWithCollateralDeposited.length; i++) {
            if (usersWithCollateralDeposited[i] == msg.sender) {
                found = true;
                break;
            }
        }
        if (!found) usersWithCollateralDeposited.push(msg.sender);
    }

    function mintAUSD(uint256 amountAUSDToMint, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) return;
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];

        // Calculate the user's borrowing power and current debt to determine how much they can mint
        uint256 borrowingPower = _getUserTotalBorrowingPower(sender);
        uint256 currentDebt = aue.getUserAccountData(sender).totalDebt;
        if (borrowingPower <= currentDebt) return;

        uint256 maxUserMintAmount = borrowingPower - currentDebt;
        // Calculate max supply based on the global supply cap and take the minimum of the two limits
        uint256 totalAusdSupply = ausd.totalSupply();
        uint256 maxAusdSupply = type(uint128).max;
        uint256 availableGlobal = maxAusdSupply > totalAusdSupply ? maxAusdSupply - totalAusdSupply : 0;

        uint256 actualLimit = maxUserMintAmount < availableGlobal ? maxUserMintAmount : availableGlobal;
        if (actualLimit == 0) return;

        amountAUSDToMint = bound(amountAUSDToMint, 0, actualLimit);
        if (amountAUSDToMint == 0) return;

        vm.startPrank(sender);
        try aue.mintAUSD(amountAUSDToMint) {} catch {}
        vm.stopPrank();
    }


    function redeemCollateral(uint256 tokenSeed, uint256 amountCollateral) public {
        address token = collateralTokens[tokenSeed % collateralTokens.length];

        AurumEngine.UserAccountData memory userData = aue.getUserAccountData(msg.sender);

        uint256 index = type(uint256).max;
        for (uint256 i = 0; i < userData.activeCollateralTokens.length; i++) {
            if (userData.activeCollateralTokens[i] == token) {
                index = i;
                break;
            }
        }
        if (index == type(uint256).max) return;

        uint256 maxCollateral = userData.collateralAmounts[index];
        amountCollateral = bound(amountCollateral, 0, maxCollateral);
        if (amountCollateral == 0) return;

        vm.prank(msg.sender);
        try aue.redeemCollateral(token, amountCollateral) {} catch {}
    }


    function burnAUSD(uint256 amountAUSDToBurn) public {
        uint256 maxAUSD = ausd.balanceOf(msg.sender);
        amountAUSDToBurn = bound(amountAUSDToBurn, 0, maxAUSD);
        if (amountAUSDToBurn == 0) return;

        vm.startPrank(msg.sender);
        ausd.approve(address(aue), amountAUSDToBurn);
        try aue.burnAUSD(amountAUSDToBurn) {} catch {}
        vm.stopPrank();
    }


    function liquidate(uint256 tokenSeed, uint256 userSeed, uint256 debtToCover) public {
        address token = collateralTokens[tokenSeed % collateralTokens.length]; // collateralTokens[0] or collateralTokens[1]
        if (usersWithCollateralDeposited.length == 0) return;

        address userToLiquidate = usersWithCollateralDeposited[userSeed % usersWithCollateralDeposited.length];
        
        // Make sure liquidator has enough AUSD to pay the debt
        uint256 liquidatorBalance = ausd.balanceOf(msg.sender);
        if (liquidatorBalance < debtToCover) {
            uint256 borrowingPower = _getUserTotalBorrowingPower(msg.sender);

            if (borrowingPower > 0) {
                vm.prank(msg.sender);
                try aue.mintAUSD(borrowingPower / 2) {} catch {}
            }
        }

        debtToCover = bound(debtToCover, 0, type(uint256).max); 
        vm.prank(msg.sender);
        try aue.liquidate(token, userToLiquidate, debtToCover) {} catch {}
    }


    function updateCollateralPrices(uint256 priceChangeSeed) public {
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            address feed = tokenPriceFeeds[token];
            (, int256 currentPrice, , , ) = MockV3Aggregator(feed).latestRoundData();
            if (currentPrice <= 0) currentPrice = 1e8;

            uint256 minPrice = uint256(currentPrice) * 98 / 100;
            uint256 maxPrice = uint256(currentPrice) * 102 / 100;
            if (minPrice < MIN_PRICE) minPrice = MIN_PRICE;
            if (maxPrice > MAX_PRICE) maxPrice = MAX_PRICE;
            if (minPrice > maxPrice) minPrice = maxPrice;

            uint256 newPrice = bound(priceChangeSeed + i, minPrice, maxPrice);
            MockV3Aggregator(feed).updateAnswer(int256(newPrice));
        }
    }

    function triggerInterestAccrual() public {
        aue.performUpkeep(abi.encode(true, false));
    }
}