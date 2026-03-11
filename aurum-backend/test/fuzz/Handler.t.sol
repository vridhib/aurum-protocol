// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

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

    address[] public usersWithCollateralDeposited;
    
    uint256 public constant MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public constant MIN_PRICE = 100e8; 
    uint256 public constant MAX_PRICE = 100000e8;

    constructor(AurumEngine _auEngine, AurumUSD _ausd, address _goldToken, address _priceFeed) {
        aue = _auEngine;
        ausd = _ausd;
        goldToken = _goldToken;
        goldPriceFeed = _priceFeed;
    }

    function depositCollateral(uint256 amountCollateral) public {
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        ERC20Mock(goldToken).mint(msg.sender, amountCollateral);
        ERC20Mock(goldToken).approve(address(aue), amountCollateral);
        aue.depositCollateral(amountCollateral);
        vm.stopPrank();

        usersWithCollateralDeposited.push(msg.sender);
    }

    function mintAUSD(uint256 amountAUSDToMint, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) return;

        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        uint256 collateralValueInUsd = aue.getAccountCollateralValueInUsd(sender);
        uint256 totalAUSDMinted = aue.getAUSDMinted(sender);

        // Calculate max amount based on 80% LTV
        uint256 maxUserAUSD = (collateralValueInUsd * 80) / 100;
        
        if (maxUserAUSD <= totalAUSDMinted) return;
        
        uint256 availableUserMint = maxUserAUSD - totalAUSDMinted;
        
        // Calculate max supply based on the global supply cap
        uint256 totalAUSDSupply = ausd.totalSupply();
        uint256 maxSupply = aue.getMaxAUSDSupply();
        
        uint256 availableGlobalMint = maxSupply - totalAUSDSupply;
        
        // Take the minimum of the two limits
        uint256 actualLimit = availableUserMint < availableGlobalMint ? availableUserMint : availableGlobalMint;
        
        if (actualLimit == 0) return;

        amountAUSDToMint = bound(amountAUSDToMint, 0, actualLimit);
        
        if (amountAUSDToMint == 0) return;

        vm.startPrank(sender);
        
        try aue.mintAUSD(amountAUSDToMint) {} catch {}
        
        vm.stopPrank();
    }


    function redeemCollateral(uint256 amountCollateral) public {
        uint256 maxCollateral = aue.getAmountCollateral(msg.sender);
        amountCollateral = bound(amountCollateral, 0, maxCollateral);
        
        if (amountCollateral == 0) return;

        vm.prank(msg.sender);
        try aue.redeemCollateral(amountCollateral) {} catch {}
    }


    function burnAUSD(uint256 amountAUSDToBurn) public {
        uint256 maxAUSD = ausd.balanceOf(msg.sender);
        amountAUSDToBurn = bound(amountAUSDToBurn, 0, maxAUSD);
        
        if (amountAUSDToBurn == 0) return;

        vm.startPrank(msg.sender);
        ausd.approve(address(aue), amountAUSDToBurn);
        aue.burnAUSD(amountAUSDToBurn);
        vm.stopPrank();
    }


    function liquidate(uint256 userSeed, uint256 debtToCover) public {
        if (usersWithCollateralDeposited.length == 0) return;

        address userToLiquidate = usersWithCollateralDeposited[userSeed % usersWithCollateralDeposited.length];
        
        uint256 collateralValueInUsd = aue.getAccountCollateralValueInUsd(msg.sender);
        if (collateralValueInUsd > 0) {
             try aue.mintAUSD(collateralValueInUsd / 2) {} catch {}
        }

        vm.startPrank(msg.sender);
        debtToCover = bound(debtToCover, 0, type(uint256).max); 
        try aue.liquidate(userToLiquidate, debtToCover) {} catch {}
        vm.stopPrank();
    }


    function updateCollateralPrice(uint256 priceChangeSeed) public {
        (, int256 currentPrice, , , ) = MockV3Aggregator(goldPriceFeed).latestRoundData();

        // Handle negative prices
        if (currentPrice <= 0) {
            currentPrice = 1e8;
        }

        // Simulate volatility swings of 2%
        uint256 minPrice = uint256(currentPrice) * 98 / 100; // -2%
        uint256 maxPrice = uint256(currentPrice) * 102 / 100; // +2%

        // Prevent the price from dropping to $0 or going infinity due to math wrapping
        uint256 HARD_FLOOR_PRICE = 100e8; 
        uint256 HARD_CEILING_PRICE = 1000000e8;

        // Adjust bounds if they hit the hard limits
        if (minPrice < HARD_FLOOR_PRICE) {
            minPrice = HARD_FLOOR_PRICE;
        }
        if (maxPrice > HARD_CEILING_PRICE) {
            maxPrice = HARD_CEILING_PRICE;
        }
        if (minPrice > maxPrice) {
            minPrice = maxPrice;
        }

        int256 newPrice = int256(bound(priceChangeSeed, minPrice, maxPrice));
        
        MockV3Aggregator(goldPriceFeed).updateAnswer(newPrice);
    }
}