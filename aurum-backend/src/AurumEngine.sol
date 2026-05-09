// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {AurumUSD} from "./AurumUSD.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
import {InterestRateModel} from "./interest/InterestRateModel.sol";
import {IVolatilityOracle} from "./oracles/IVolatilityOracle.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {AutomationCompatible} from "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title AurumEngine
 * @notice Core engine for the Aurum Protocol. Handles deposits, withdrawals, minting, burning, liquidations, and Chainlink Automation.
 * @dev The protocol maintains a dollar peg through overcollateralization with gold and WETH as exogenous collateral
 */
contract AurumEngine is ReentrancyGuard, Ownable, AutomationCompatible, Pausable {
    /*----------Errors----------*/
    error AurumEngine__TokenNotAllowed(address token);
    error AurumEngine__NeedsMoreThanZero();
    error AurumEngine__TransferFailed();
    error AurumEngine__BreaksHealthFactor(uint256 healthFactor);
    error AurumEngine__HealthFactorOkay();
    error AurumEngine__HealthFactorNotImproved();
    error AurumEngine__MintFailed();
    error AurumEngine__UserHasNoDebt();
    error AurumEngine__NoCollateralDeposited();
    error AurumEngine__NoCollateralAvailableForDebt();
    error AurumEngine__LiquidationNotProfitable();
    error AurumEngine__IneligibleForForceClose();
    error AurumEngine__PauseConditionNotMet();

    using OracleLib for AggregatorV3Interface;

    /*----------Type Declarations----------*/
    /// @notice A type that aggregates critical account info together
    struct UserAccountData {
        uint256 totalCollateralValueInUsd;  
        uint256 totalDebt;                  
        uint256 healthFactor;               
        uint256 lastIndex;                  
        address[] activeCollateralTokens;   // Non-zero deposits
        uint256[] collateralAmounts;        
        uint256[] debtAllocations;          
    }

    /// @notice A type that aggregates critical collateral token info together
    struct CollateralInfo {
        address priceFeed;                  
        address volatilityFeed;             
        uint256 baselineVolatility;
        uint256 baseLtv;                    // 0.15e18 for gold, 0.60e18 for WETH
        uint256 minLtv;                     // Floor LTV when volatility spikes
        uint256 ltv;                        
        uint256 debtCeiling;                
        uint256 totalNormalizedDebt;        
        bool isActive;                      
        uint256 minCloseFactor;
        uint256 maxCloseFactor;
    }

    /*----------Constants----------*/
    uint256 public constant ADDITIONAL_FEED_PRECISION = 1e10;          // 8 -> 18 decimals for price feeds
    uint256 public constant PRECISION = 1e18;
    uint256 public constant LIQUIDATION_AND_FEE_PRECISION = 100;       // Percentage divisor
    uint256 private constant TEN_PERCENT = 0.10e18;

    uint256 public constant VOLATILITY_REDUCTION_FACTOR = 5;           // For every 10% volatility increase, reduce LTV by 5%
    uint256 public constant CLOSE_FACTOR_BOOST_PER_STEP = 0.05e18;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant MIN_DUST_THRESHOLD = 100e18;               // If user debt < 100e18 allow 100% liquidation
    uint256 public constant MAX_FORCE_CLOSE_COLLATERAL_VALUE = 100e18; // $100
    uint256 public constant FORCE_CLOSE_HF_THRESHOLD = 0.50e18;        // HF <= 0.50e18          
    uint256 public constant MIN_LIQUIDATION_PROFIT = 5e18;             // Min $5 profit for a keeper; would be $50-$100 for mainnet
    uint256 public constant LIQUIDATION_BONUS = 5;                     // % liquidator bonus
    uint256 public constant PROTOCOL_LIQUIDATION_FEE = 5;              // % of liquidation bonus to treasury
    uint256 public constant PROTOCOL_RESERVE_PERCENT = 10;             // % of interest to treasury
    uint256 public constant INDEX_UPDATE_INTERVAL = 1 hours;
    uint256 public constant LTV_UPDATE_INTERVAL = 1 days;

    /*----------Storage Variables----------*/
    mapping(address => mapping(address => uint256)) private s_collateralDeposited;
    mapping(address => CollateralInfo) private s_collateralInfo;
    mapping(address => mapping(address => uint256)) private s_userDebtAllocation;
    mapping(address => uint256) private s_userLastIndex;               // last cumulative index on mint/burn
    address[] public s_collateralList;                                 // AUR + WETH

    uint256 public s_cumulativeIndex = 1e18;
    uint256 public s_indexLastUpdate;
    uint256 public s_ltvLastUpdate;

    address public immutable i_treasury;
    InterestRateModel public immutable i_interestRateModel;
    AurumUSD public immutable i_ausd;

    /*----------Events----------*/
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, uint256 amount);
    event Liquidated(address indexed user, address indexed liquidator, uint256 debtToCover, uint256 totalCollateralToRedeem, uint256 protocolShare);
    event MintAUSD(address indexed user, uint256 amount);
    event DebtCeilingHit(address indexed token, uint256 totalNormalizedDebt, uint256 allocatedDebt);
    event DebtAllocated(address user, address token, uint256 allocatedDebt);
    event DebtDeallocated(address user, address token, uint256 debtReduction);
    event BurnAUSD(address indexed user, uint256 amount);
    event ForceClosed(address indexed user, uint256 debtAbsorbed, uint256 collateralSeized);

    /*----------Modifiers----------*/
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert AurumEngine__NeedsMoreThanZero();
        _;
    }

    modifier isAllowedToken(address token) {
        if (!s_collateralInfo[token].isActive) {
            revert AurumEngine__TokenNotAllowed(token);
        }
        _;
    }


    /*----------Functions----------*/
    constructor(
        address[] memory tokenAddresses, 
        address[] memory priceFeedAddresses, 
        address[] memory volatilityFeedAddresses,
        uint256[] memory baselineVolatilities,
        uint256[] memory baseLtvs,
        uint256[] memory minLtvs,
        uint256[] memory debtCeilings,
        uint256[] memory minCloseFactors,
        uint256[] memory maxCloseFactors,
        address ausdAddress,
        address interestRateModelAddress,
        address treasuryAddress
    ) 
        Ownable(msg.sender) 
    {
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_collateralInfo[tokenAddresses[i]] = CollateralInfo({
                priceFeed: priceFeedAddresses[i],
                volatilityFeed: volatilityFeedAddresses[i],
                baselineVolatility: baselineVolatilities[i],
                baseLtv: baseLtvs[i],
                minLtv: minLtvs[i],
                ltv: baseLtvs[i], // initialize as base LTV, adjusted later based on volatility                 
                debtCeiling: debtCeilings[i], 
                totalNormalizedDebt: 0,
                isActive: true,
                minCloseFactor: minCloseFactors[i],
                maxCloseFactor: maxCloseFactors[i]
            });
            s_collateralList.push(tokenAddresses[i]);
        }
        i_ausd = AurumUSD(ausdAddress);
        i_interestRateModel = InterestRateModel(interestRateModelAddress);
        i_treasury = treasuryAddress;
        s_indexLastUpdate = block.timestamp;
        s_ltvLastUpdate = block.timestamp;
    }

    /// @notice Pause all state-changing operations. Only callable by the owner when the protocol's collateralization ratio falls below 110%.
    function pause() external onlyOwner {
        if (!_canPause()) revert AurumEngine__PauseConditionNotMet();
        _pause();
    }

    /// @notice Unpause the protocol. Only callable by the owner.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Chainlink Automation compatible function to check if index or LTV updates are needed. Returns encoded booleans indicating which updates are needed.
    function checkUpkeep(bytes calldata /*checkData*/) external view override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint256 totalNormalizedDebt = 0;
        for (uint256 i = 0; i < s_collateralList.length; i++) {
            totalNormalizedDebt += s_collateralInfo[s_collateralList[i]].totalNormalizedDebt;
        }
        if (totalNormalizedDebt == 0) return (false, "");

        bool indexUpdateNeeded = (block.timestamp - s_indexLastUpdate) >= INDEX_UPDATE_INTERVAL;
        bool ltvUpdateNeeded = (block.timestamp - s_ltvLastUpdate) >= LTV_UPDATE_INTERVAL;

        upkeepNeeded = indexUpdateNeeded || ltvUpdateNeeded;
        performData = abi.encode(indexUpdateNeeded, ltvUpdateNeeded);
    }

    /// @notice Updates the cumulative index and/or LTVs if their respective update intervals have passed.
    function performUpkeep(bytes calldata performData) external override whenNotPaused {
        (bool indexUpdateNeeded, bool ltvUpdateNeeded) = abi.decode(performData, (bool, bool));
        if (indexUpdateNeeded) _updateIndex();
        if (ltvUpdateNeeded) _updateLTVs();
    }


    /// @notice Forcefully close an underwater position by seizing all remaining collateral and clearing the user's debt using treasury funds.
    /// @dev The position must either have collateral <= $100 or health factor <= 0.50 to be eligible.
    function forceClose(address user) external nonReentrant whenNotPaused {
        uint256 totalCollateralValue = _getUserCollateralValue(user);
        uint256 hf = _healthFactor(user);
        uint256 debt = _getUserActualDebt(user);
        
        // Must be underwater in 1 of the 2 "stuck" scenarios
        if (debt == 0) revert AurumEngine__UserHasNoDebt();
        if (hf >= MIN_HEALTH_FACTOR) revert AurumEngine__HealthFactorOkay();
        if ((totalCollateralValue > MAX_FORCE_CLOSE_COLLATERAL_VALUE) && (hf > FORCE_CLOSE_HF_THRESHOLD)) {
            revert AurumEngine__IneligibleForForceClose(); 
        }
    
        if (totalCollateralValue > 0) { 
            for (uint256 i = 0; i < s_collateralList.length; i++) {
                address token = s_collateralList[i];
                uint256 amount = s_collateralDeposited[user][token];
                if (amount > 0) {
                    s_collateralDeposited[user][token] = 0;
                    IERC20(token).transfer(i_treasury, amount);
                }
            }
        }

        for (uint256 i = 0; i < s_collateralList.length; i++) {
            address token = s_collateralList[i];
            uint256 allocatedDebt = s_userDebtAllocation[user][token];
            if (allocatedDebt > 0) {
                s_userDebtAllocation[user][token] = 0;
                s_collateralInfo[token].totalNormalizedDebt -= allocatedDebt;
            }
        }
        s_userLastIndex[user] = s_cumulativeIndex;

        i_ausd.transferFrom(i_treasury, address(this), debt);
        i_ausd.burn(debt);
        emit ForceClosed(user, debt, totalCollateralValue);
    }

    /// @notice Update volatility feed, LTV, debt ceiling, and active status for a collateral token. Pass 0 or address(0) to leave a value unchanged.
    function setCollateralInfo(
        address collateralToken,
        address volatilityFeed,
        uint256 newLtv, 
        uint256 newDebtCeiling, 
        bool isActive
    ) external onlyOwner 
    {
        CollateralInfo storage info = s_collateralInfo[collateralToken];
        if (volatilityFeed != address(0)) info.volatilityFeed = volatilityFeed;
        if (newLtv != 0) info.ltv = newLtv;
        if (newDebtCeiling != 0) info.debtCeiling = newDebtCeiling;
        info.isActive = isActive;
    }


    /// @notice Deposit `amountCollateral` of `collateralToken` and mint `amountAUSDToMint` AUSD in one transaction.
    /// @dev Must maintain a health factor >= 1 after execution and must not exceed debt ceilings for any collateral type.
    function depositCollateralAndMintAUSD(address collateralToken, uint256 amountCollateral, uint256 amountAUSDToMint)        external 
    {
        depositCollateral(collateralToken, amountCollateral);
        mintAUSD(amountAUSDToMint);
    }


    /// @notice Burn `amountAUSDToBurn` AUSD and redeem `amountCollateral` of `collateralToken` in one transaction. 
    /// @dev Must maintain a health factor >= 1 after execution.
    function redeemCollateralAndBurnAUSD(address collateralToken, uint256 amountCollateral, uint256 amountAUSDToBurn)        external
    {
        burnAUSD(amountAUSDToBurn);
        redeemCollateral(collateralToken, amountCollateral);
    }


    /// @notice Deposit `amountCollateral` of `collateralToken` into the protocol.
    function depositCollateral(address collateralToken, uint256 amountCollateral) public moreThanZero(amountCollateral)        isAllowedToken(collateralToken) nonReentrant whenNotPaused
    {
        s_collateralDeposited[msg.sender][collateralToken] += amountCollateral;
        emit CollateralDeposited(msg.sender, collateralToken, amountCollateral);
        bool success = IERC20(collateralToken).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) revert AurumEngine__TransferFailed();
    }


    /// @notice Redeem `amountCollateral` of `collateralToken` from the protocol. 
    /// @dev Must maintain a health factor >= 1 after redemption.
    function redeemCollateral(address collateralToken, uint256 amountCollateral) public moreThanZero(amountCollateral) isAllowedToken(collateralToken) nonReentrant whenNotPaused
    {
        _redeemCollateral(collateralToken, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }


    /// @notice Mint `amountAUSDToMint` AUSD using the caller’s deposited collateral.
    /// @dev Must not break the user health factor and must not exceed debt ceilings for any collateral type.
    function mintAUSD(uint256 amountAUSDToMint) public moreThanZero(amountAUSDToMint) nonReentrant whenNotPaused {
        _updateIndex();
        s_userLastIndex[msg.sender] = s_cumulativeIndex;

        (address[] memory collateralTokens, uint256[] memory usdValues, uint256 totalUsdValue, uint256 length) = _getUserCollateralBreakdown(msg.sender);
        if (length == 0) revert AurumEngine__NoCollateralDeposited();

        uint256 normalizedMintAmount = (amountAUSDToMint * PRECISION) / s_cumulativeIndex;

        (bool[] memory willHitDebtCeiling, uint256 totalValidValue) = _computeAllocationsAndCheckCeilings(collateralTokens, usdValues, totalUsdValue, length, normalizedMintAmount);

        _allocateDebt(collateralTokens, usdValues, totalUsdValue, totalValidValue, willHitDebtCeiling, length, normalizedMintAmount);
        
        _revertIfHealthFactorIsBroken(msg.sender);
        emit MintAUSD(msg.sender, amountAUSDToMint);
        bool minted = i_ausd.mint(msg.sender, amountAUSDToMint);
        if (!minted) revert AurumEngine__MintFailed();
    }

    // TO-DO: add rebalanceDebt() for advanced users

    /// @notice Burn `amount` AUSD and reduce the caller’s debt proportionally.
    function burnAUSD(uint256 amount) public moreThanZero(amount) whenNotPaused {
        _burnAUSD(amount, msg.sender, msg.sender);
    }

    /// @notice Liquidate an underwater position, seizing up to the dynamic close factor of the debt.
    /// @dev The caller receives the debt they covered plus a 5% bonus in collateral, and the protocol takes a 5% fee.
    function liquidate(address collateralToken, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        isAllowedToken(collateralToken)
        nonReentrant
        whenNotPaused
    {
        _updateIndex();

        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) revert AurumEngine__HealthFactorOkay();

        uint256 currentDebt = _getUserActualDebt(user);
        uint256 closeFactor = _closeFactor(user, collateralToken);
        uint256 maxDebtToCover = (currentDebt * closeFactor) / PRECISION;

        if (debtToCover > maxDebtToCover) debtToCover = maxDebtToCover;
        if (maxDebtToCover < MIN_DUST_THRESHOLD) debtToCover = currentDebt; // if dust pay off 100%
        
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateralToken, debtToCover);

        uint256 liquidatorBonus = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_AND_FEE_PRECISION;
        uint256 profitUsd = _usdValue(collateralToken, liquidatorBonus);
        if (profitUsd < MIN_LIQUIDATION_PROFIT) revert AurumEngine__LiquidationNotProfitable();

        uint256 protocolShare = (tokenAmountFromDebtCovered * PROTOCOL_LIQUIDATION_FEE) / LIQUIDATION_AND_FEE_PRECISION;
        uint256 liquidatorShare = tokenAmountFromDebtCovered + liquidatorBonus;
        uint256 totalCollateralToRedeem = liquidatorShare + protocolShare;

        _redeemCollateral(collateralToken, liquidatorShare, user, msg.sender);
        _redeemCollateral(collateralToken, protocolShare, user, i_treasury);
        _burnAUSD(debtToCover, user, msg.sender);
        emit Liquidated(user, msg.sender, debtToCover, totalCollateralToRedeem, protocolShare);
    }

    /**************************************************************************/
    /*******************Private & Internal View Functions**********************/
    /**************************************************************************/
    function _updateIndex() private {
        if (block.timestamp == s_indexLastUpdate) return;
        (uint256 totalCollateralValue, uint256 totalActualDebt) = _getGlobalMetrics();
        if (totalActualDebt == 0 || totalCollateralValue == 0) {
            s_indexLastUpdate = block.timestamp;
            return;
        }

        uint256 utilization = (totalActualDebt * PRECISION) / totalCollateralValue;
        if (utilization > PRECISION) utilization = PRECISION; // safety
        uint256 borrowRatePerSecond = i_interestRateModel.getBorrowRate(utilization);
        uint256 timeElapsed = block.timestamp - s_indexLastUpdate;
        // newIndex = oldIndex * (1 + rate * time)
        s_cumulativeIndex = s_cumulativeIndex * (PRECISION + borrowRatePerSecond * timeElapsed) / PRECISION;
        s_indexLastUpdate = block.timestamp;
    }

    function _updateLTVs() private {
        for (uint256 i = 0; i < s_collateralList.length; i++) {
            CollateralInfo storage info = s_collateralInfo[s_collateralList[i]];

            uint256 volatility = IVolatilityOracle(info.volatilityFeed).getAnnualizedVolatility(); // 18 decimals
            uint256 excess = volatility > info.baselineVolatility ? volatility - info.baselineVolatility : 0;
            uint256 reduction = (excess * VOLATILITY_REDUCTION_FACTOR) / TEN_PERCENT;

            uint256 newLtv = info.baseLtv >= reduction ? info.baseLtv - reduction : 0;
            if (newLtv < info.minLtv) newLtv = info.minLtv; 
            if (newLtv > info.baseLtv) newLtv = info.baseLtv;
            info.ltv = newLtv;
        }
        s_ltvLastUpdate = block.timestamp;
    }


    /// @dev Internal burn function used primarily for liquidate (and also user burns)
    function _burnAUSD(uint256 amountAUSDToBurn, address onBehalfOf, address ausdFrom) private {
        _updateIndex();

        uint256 totalNormalized;
        for (uint256 i = 0; i < s_collateralList.length; i++) {
            totalNormalized += s_userDebtAllocation[onBehalfOf][s_collateralList[i]];
        }
        if (totalNormalized == 0) revert AurumEngine__UserHasNoDebt();

        uint256 actualDebt = (totalNormalized * s_cumulativeIndex) / PRECISION;
        uint256 principal = (totalNormalized * s_userLastIndex[onBehalfOf]) / PRECISION;
        uint256 interestAccrued = actualDebt - principal;
        uint256 protocolFee = (interestAccrued * PROTOCOL_RESERVE_PERCENT) / LIQUIDATION_AND_FEE_PRECISION;

        if (amountAUSDToBurn > actualDebt) amountAUSDToBurn = actualDebt;
        uint256 reductionFactor = (amountAUSDToBurn * PRECISION) / actualDebt;
        uint256 totalNormTarget = (totalNormalized * reductionFactor) / PRECISION;
        uint256 remainingNorm = totalNormTarget;

        for (uint256 i = 0; i < s_collateralList.length; i++) {
            address token = s_collateralList[i];
            uint256 allocatedNorm = s_userDebtAllocation[onBehalfOf][token];
            if (allocatedNorm == 0) continue;

            uint256 reductionNorm;
            if (i == s_collateralList.length - 1) {
                reductionNorm = remainingNorm; // dust protection
            } else {
                reductionNorm = (allocatedNorm * reductionFactor) / PRECISION;
            }
            if (reductionNorm > allocatedNorm) reductionNorm = allocatedNorm;

            s_userDebtAllocation[onBehalfOf][token] -= reductionNorm;
            s_collateralInfo[token].totalNormalizedDebt -= reductionNorm;
            remainingNorm -= reductionNorm;
            emit DebtDeallocated(onBehalfOf, token, reductionNorm);
        }
        s_userLastIndex[onBehalfOf] = s_cumulativeIndex;
        emit BurnAUSD(onBehalfOf, amountAUSDToBurn);

        bool success = i_ausd.transferFrom(ausdFrom, address(this), amountAUSDToBurn);
        if (!success) revert AurumEngine__TransferFailed();
        i_ausd.burn(amountAUSDToBurn);
        if (protocolFee > 0) i_ausd.mint(i_treasury, protocolFee);
    }


    /// @dev Internal redeem function used primarily for liquidate (and also user redemptions)
    function _redeemCollateral(address collateralToken, uint256 amountCollateral, address from, address to) private {
        s_collateralDeposited[from][collateralToken] -= amountCollateral;
        emit CollateralRedeemed(from, to, amountCollateral);
        bool success = IERC20(collateralToken).transfer(to, amountCollateral);
        if (!success) revert AurumEngine__TransferFailed();
    }

    /// @dev Builds arrays of active collateral tokens and their USD values for minting.
    function _getUserCollateralBreakdown(address user) private view 
    returns (
        address[] memory collateralTokens, 
        uint256[] memory usdValues, 
        uint256 totalUsdValue, 
        uint256 activeCount
    ) {
        uint256 maxLen = s_collateralList.length;
        collateralTokens = new address[](maxLen);
        usdValues = new uint256[](maxLen);
        totalUsdValue = 0;
        activeCount = 0;
        for (uint256 i = 0; i < maxLen; i++) {
            address token = s_collateralList[i];
            uint256 amount = s_collateralDeposited[user][token];
            if (amount > 0 && s_collateralInfo[token].isActive) {
                uint256 value = _usdValue(token, amount);
                collateralTokens[activeCount] = token;
                usdValues[activeCount] = value;
                totalUsdValue += value;
                activeCount++;
            }
        }
    }

    function _computeAllocationsAndCheckCeilings(
        address[] memory collateralTokens, 
        uint256[] memory usdValues, 
        uint256 totalUsdValue, 
        uint256 length, 
        uint256 normalizedMint
    ) 
        private 
        returns (bool[] memory willHitDebtCeiling, uint256 totalValidValue) 
    {
        willHitDebtCeiling = new bool[](length);
        uint256 currentIndex = s_cumulativeIndex;

        for (uint256 i = 0; i < length; i++) {
            address token = collateralTokens[i];
            uint256 weight = (usdValues[i] * PRECISION) / totalUsdValue;
            uint256 allocatedNorm = (normalizedMint * weight) / PRECISION;

            uint256 actualIncrease = (allocatedNorm * currentIndex) / PRECISION;
            uint256 currentGlobalActualDebt = (s_collateralInfo[token].totalNormalizedDebt * currentIndex) / PRECISION;

            if (currentGlobalActualDebt + actualIncrease > s_collateralInfo[token].debtCeiling) {
                willHitDebtCeiling[i] = true;
                emit DebtCeilingHit(token, currentGlobalActualDebt, actualIncrease);
            } else {
                totalValidValue += usdValues[i];
            }
        }
    }

    function _allocateDebt(
        address[] memory collateralTokens, 
        uint256[] memory usdValues, 
        uint256 totalUsdValue, 
        uint256 totalValidValue, 
        bool[] memory willHitDebtCeiling, 
        uint256 length, 
        uint256 normalizedMint) 
        private 
    {
        if (totalValidValue == 0) revert AurumEngine__NoCollateralAvailableForDebt();
        
        // Odd case: some collaterals hit debt ceilings
        if (totalValidValue < totalUsdValue) {
            uint256 remaining = normalizedMint;
            address lastValidCollateral = address(0);

            for (uint256 i = 0; i < length; i++) {
                if (willHitDebtCeiling[i]) continue;

                address token = collateralTokens[i];
                uint256 weight = (usdValues[i] * PRECISION) / totalValidValue;
                uint256 allocatedDebt = (normalizedMint * weight) / PRECISION;

                remaining -= allocatedDebt;
                lastValidCollateral = token;

                s_userDebtAllocation[msg.sender][token] += allocatedDebt;
                s_collateralInfo[token].totalNormalizedDebt += allocatedDebt;
                emit DebtAllocated(msg.sender, token, allocatedDebt);
            }

            // Assign remaining dust (from rounding) to `lastValidCollateral`
            if (remaining > 0 && lastValidCollateral != address(0)) {
                s_userDebtAllocation[msg.sender][lastValidCollateral] += remaining;
                s_collateralInfo[lastValidCollateral].totalNormalizedDebt += remaining;
                emit DebtAllocated(msg.sender, lastValidCollateral, remaining);
            }
        } 
        // Normal case: no debt ceilings are hit
        else {
            uint256 remaining = normalizedMint;
            for (uint256 i = 0; i < length; i++) {
                address token = collateralTokens[i];
                uint256 weight = (usdValues[i] * PRECISION) / totalUsdValue;
                uint256 allocatedDebt = (normalizedMint * weight) / PRECISION;

                // Account for dust/rounding truncation
                if (i == length - 1) allocatedDebt = remaining;
                else remaining -= allocatedDebt;
        
                s_userDebtAllocation[msg.sender][token] += allocatedDebt;
                s_collateralInfo[token].totalNormalizedDebt += allocatedDebt;
                emit DebtAllocated(msg.sender, token, allocatedDebt);
            }
        }
    }

    function _usdValue(address collateralToken, uint256 amount) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_collateralInfo[collateralToken].priceFeed);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function _healthFactor(address user) private view returns (uint256) {
        uint256 totalActualDebt = _getUserActualDebt(user);
        if (totalActualDebt == 0) return type(uint256).max;

        uint256 totalAdjustedCollateral = 0;
        for (uint256 i = 0; i < s_collateralList.length; i++) {
            address token = s_collateralList[i];
            uint256 amount = s_collateralDeposited[user][token];
            if (amount == 0) continue;
            uint256 usdValue = _usdValue(token, amount);
            uint256 ltv = s_collateralInfo[token].ltv;
            totalAdjustedCollateral += (usdValue * ltv) / LIQUIDATION_AND_FEE_PRECISION;
        }
        return (totalAdjustedCollateral * PRECISION) / totalActualDebt;
    }


    /// @dev This is only called within liquidate() (which already checks and reverts if user's HF >= 1e18) to calculate the dynamic close factor
    function _closeFactor(address user, address collateralToken) private view returns (uint256) {
        uint256 userHf = _healthFactor(user);

        CollateralInfo memory info = s_collateralInfo[collateralToken];
        uint256 volatility = IVolatilityOracle(info.volatilityFeed).getAnnualizedVolatility();
        uint256 excess = volatility > info.baselineVolatility ? volatility - info.baselineVolatility : 0;
        uint256 volatilityBoost = (excess * CLOSE_FACTOR_BOOST_PER_STEP) / TEN_PERCENT;
        uint256 effectiveMaxCloseFactor = info.maxCloseFactor + volatilityBoost;
        if (effectiveMaxCloseFactor > PRECISION) effectiveMaxCloseFactor = PRECISION;

        uint256 deficit = MIN_HEALTH_FACTOR - userHf;
        uint256 closeFactor = info.minCloseFactor + ((effectiveMaxCloseFactor - info.minCloseFactor) * deficit) / PRECISION;
        return closeFactor;
    }

    function _revertIfHealthFactorIsBroken(address user) private view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) revert AurumEngine__BreaksHealthFactor(userHealthFactor);
    }

    function _getUserActualDebt(address user) private view returns (uint256) {
        uint256 totalNorm;
        for (uint256 i = 0; i < s_collateralList.length; i++) {
            totalNorm += s_userDebtAllocation[user][s_collateralList[i]];
        }
        return (totalNorm * s_cumulativeIndex) / PRECISION;
    }

    function _getUserCollateralValue(address user) private view returns (uint256) {
        uint256 totalCollateralValueInUsd;
        for (uint256 i = 0; i < s_collateralList.length; i++) {
            address token = s_collateralList[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _usdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function _getGlobalMetrics() private view returns (uint256 totalCollateralValueInUsd, uint256 totalActualDebt) {
        uint256 totalNorm; 
        for (uint256 i = 0; i < s_collateralList.length; i++) {
            address token = s_collateralList[i];
            uint256 balance = IERC20(token).balanceOf(address(this));
            totalCollateralValueInUsd += _usdValue(token, balance);
            totalNorm += s_collateralInfo[token].totalNormalizedDebt;
        }
        totalActualDebt = (totalNorm * s_cumulativeIndex) / PRECISION;
        return (totalCollateralValueInUsd, totalActualDebt);
    }

    function _canPause() private view returns (bool) {
        (uint256 totalCollateralValue, uint256 totalActualDebt) = _getGlobalMetrics();
        if (totalActualDebt == 0) return false;
        return (totalCollateralValue * PRECISION) / totalActualDebt < (PRECISION + TEN_PERCENT);
    }


    /**************************************************************************/
    /*********************Public & External View Functions*********************/
    /**************************************************************************/
    /// @notice Returns the amount of collateral tokens for a given USD value.
    function getTokenAmountFromUsd(address collateralToken, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_collateralInfo[collateralToken].priceFeed);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    /// @notice Returns the USD value for a given amount of collateral tokens.
    function getUsdValue(address collateralToken, uint256 amount) external view returns (uint256) {
        return _usdValue(collateralToken, amount);
    }

    /// @notice Returns the protocol's total collateral value in USD and total actual debt.
    function getGlobalMetrics() external view returns (uint256 totalCollateralValueInUsd, uint256 actualDebt) {
        (totalCollateralValueInUsd, actualDebt) = _getGlobalMetrics();
    }

    /// @notice Returns the liquidation profit for a given user and debtToCover (reverts if user is healthy).
    function getLiquidationProfit(address collateralToken, address user, uint256 debtToCover) external view returns (uint256 profitUsd, uint256 bonusCollateral) {
        if (_healthFactor(user) >= MIN_HEALTH_FACTOR) revert AurumEngine__HealthFactorOkay();

        uint256 currentDebt = _getUserActualDebt(user);
        uint256 closeFactor = _closeFactor(user, collateralToken);
        uint256 maxDebtToCover = (debtToCover * closeFactor) / PRECISION;
        if (debtToCover > maxDebtToCover) debtToCover = maxDebtToCover;
        if (maxDebtToCover < MIN_DUST_THRESHOLD) debtToCover = currentDebt;
        
        uint256 tokenAmount = getTokenAmountFromUsd(collateralToken, debtToCover);
        bonusCollateral = (tokenAmount * LIQUIDATION_BONUS) / LIQUIDATION_AND_FEE_PRECISION;
        profitUsd = _usdValue(collateralToken, bonusCollateral);
    }

    /// @notice Full collateral token info snapshot: price feed, LTV, debt ceiling, total normalized debt, and active flag.
    function getCollateralInfo(address collateralToken) external view returns (CollateralInfo memory) {
        return s_collateralInfo[collateralToken];
    }

    /// @notice Full user snapshot: active collaterals, amounts, debt allocations, total debt, collateral, HF, and last index.
    function getUserAccountData(address user) external view returns (UserAccountData memory data) {
        uint256 totalNorm;
        uint256 activeCount;
        for (uint256 i = 0; i < s_collateralList.length; i++) {
            address token = s_collateralList[i];
            uint256 amount = s_collateralDeposited[user][token];
            if (amount > 0 && s_collateralInfo[token].isActive) {
                activeCount++;
            }
            totalNorm += s_userDebtAllocation[user][token];
        }
        data.activeCollateralTokens = new address[](activeCount);
        data.collateralAmounts    = new uint256[](activeCount);
        data.debtAllocations      = new uint256[](activeCount);

        uint256 index;
        for (uint256 i = 0; i < s_collateralList.length; i++) {
            address token = s_collateralList[i];
            uint256 amount = s_collateralDeposited[user][token];
            if (amount > 0 && s_collateralInfo[token].isActive) {
                data.activeCollateralTokens[index] = token;
                data.collateralAmounts[index] = amount;
                data.debtAllocations[index] = s_userDebtAllocation[user][token];
                index++;
            }
        }
        data.totalDebt = (totalNorm * s_cumulativeIndex) / PRECISION;
        data.totalCollateralValueInUsd = _getUserCollateralValue(user);
        data.healthFactor = _healthFactor(user);
        data.lastIndex = s_userLastIndex[user];
    }

    /// @notice Returns whether a protocol meets the pause condition (collateralization ratio < 1.10)
    function canPause() external view returns (bool) {
        return _canPause();
    }
}