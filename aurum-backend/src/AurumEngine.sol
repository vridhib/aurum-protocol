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

/**
 * @title AurumEngine
 * @author
 *
 * The system is designed to be as robust and as autonomous as possible, and have the tokens maintain a 1 token == $1 peg.
 * This stablecoin has the following properties:
 *  - Exogenous Collateral
 *  - Dollar Pegged
 *  - Algorithmically Stable
 *
 * The Aurum Protocol should always be "overcollateralized". At no point, should the value of all the collateral (AUR + WETH) <= the dollar backed value of all the AUSD.
 *
 * @notice This contract is the core of the Aurum Protocol. It handles all the logic for minting and redeeming AUSD as well as depositing and withdrawing collateral.
 */
contract AurumEngine is ReentrancyGuard, Ownable, AutomationCompatible {
    /*----------Errors----------*/
    error AurumEngine__TokenNotAllowed(address token);
    error AurumEngine__NeedsMoreThanZero();
    error AurumEngine__TransferFailed();
    error AurumEngine__BreaksHealthFactor(uint256 healthFactor);
    error AurumEngine__HealthFactorOkay();
    error AurumEngine__HealthFactorNotImproved();
    error AurumEngine__MintFailed();
    error AurumEngine__NothingToBurn();
    error AurumEngine__NoCollateralDeposited();
    error AurumEngine__NoCollateralAvailableForDebt();
    error AurumEngine__LiquidationNotProfitable();
    error AurumEngine__NoDebtToAbsorb();
    error AurumEngine__IneligibleForForceClose();

    using OracleLib for AggregatorV3Interface;

    /*----------Type Declarations----------*/
    /// @notice A type that aggregates critical account info together
    struct UserAccountData {
        uint256 totalCollateralValueInUsd;  // Total USD value of deposited collateral
        uint256 totalDebt;                  // Total AUSD minted + accrued interest
        uint256 healthFactor;               // Current user health factor
        uint256 lastIndex;                  // Last cumulative index when user minted or repaid
        address[] activeCollateralTokens;   // List of collateral tokens that are active with non-zero deposits
        uint256[] collateralAmounts;        // Corresponding amounts of each collateral token deposited
        uint256[] debtAllocations;          // Normalized debt per token
    }

    /// @notice A type that aggregates critical collateral token info together
    struct CollateralInfo {
        address priceFeed;                  // Chainlink price feed address
        address volatilityFeed;             // Chainlink ETH & mock gold volatility feed addresses
        uint256 baselineVolatility;
        uint256 baseLtv;                    // 0.15e18 for gold, 0.6 for WETH
        uint256 minLtv;                     // floor LTV when volatility spikes
        uint256 ltv;                        // current dynamic LTV
        uint256 debtCeiling;                // Max total AUSD mintable against this collateral
        uint256 totalNormalizedDebt;        // Current total AUSD minted against this collateral
        bool isActive;                      // Can users deposit/mint against it?
        uint256 minCloseFactor;
        uint256 maxCloseFactor;
    }

    /*----------State Variables----------*/
    // Precision Constants
    uint256 public constant ADDITIONAL_FEED_PRECISION = 1e10;         // 8 -> 18 decimals for price feeds
    uint256 public constant PRECISION = 1e18;
    uint256 public constant LIQUIDATION_AND_FEE_PRECISION = 100;      // Percentage divisor
    uint256 private constant TEN_PERCENT = 0.10e18;
    // Economic Constants
    uint256 public constant VOLATILITY_REDUCTION_FACTOR = 5;          // For every 10% volatility increase, reduce LTV by 5%
    uint256 public constant CLOSE_FACTOR_BOOST_PER_STEP = 0.05e18;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant MIN_DUST_THRESHOLD = 100e18;              // If user debt < 100e18 allow 100% liquidation
    uint256 public constant MAX_FORCE_CLOSE_COLLATERAL_VALUE = 100e18;   // $100
    uint256 public constant FORCE_CLOSE_HF_THRESHOLD = 0.50e18;    // 50% health factor           
    uint256 public constant MIN_LIQUIDATION_PROFIT = 5e18;            // Min $5 profit for a keeper; would be 50-100 for mainnet
    uint256 public constant LIQUIDATION_BONUS = 5;                    // % liquidator bonus
    uint256 public constant PROTOCOL_LIQUIDATION_FEE = 5;             // % of liquidation bonus to treasury
    uint256 public constant PROTOCOL_RESERVE_PERCENT = 10;            // % of interest to treasury

    uint256 public constant INDEX_UPDATE_INTERVAL = 1 hours;
    uint256 public constant LTV_UPDATE_INTERVAL = 1 days;


    // Storage Variables
    mapping(address => mapping(address => uint256)) private s_collateralDeposited;
    mapping(address => CollateralInfo) private s_collateralInfo;
    mapping(address => mapping(address => uint256)) private s_userDebtAllocation;
    mapping(address => uint256) private s_userLastIndex;              // last cumulative index on mint/burn
    address[] public s_collateralList;                                // AUR + WETH

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

    /**
     * @notice Called by Chainlink nodes to determine if an upkeep is needed
     * @return upkeepNeeded true if conditions are met to call performUpkeep
     * @return performData encoded data to pass to performUpkeep
     */
    function checkUpkeep(bytes calldata /*checkData*/) public view override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint256 totalNormalizedDebt = 0;
        for (uint256 i = 0; i < s_collateralList.length; i++) {
            totalNormalizedDebt += s_collateralInfo[s_collateralList[i]].totalNormalizedDebt;
        }
        if (totalNormalizedDebt == 0) return (false, "");

        bool indexUpdateNeeded = (block.timestamp - s_indexLastUpdate) >= INDEX_UPDATE_INTERVAL;
        bool ltvUpdateNeeded = (block.timestamp - s_ltvLastUpdate) >= LTV_UPDATE_INTERVAL;

        // Upkeep if either action's interval has passed
        upkeepNeeded = indexUpdateNeeded || ltvUpdateNeeded;
        performData = abi.encode(indexUpdateNeeded, ltvUpdateNeeded);
    }

    /**
     * @notice Called by Chainlink nodes when `checkUpkeep` returns true
     * @param performData data passed from `checkUpkeep`
     */
    function performUpkeep(bytes calldata performData) external override {
        (bool indexUpdateNeeded, bool ltvUpdateNeeded) = abi.decode(performData, (bool, bool));
        if (indexUpdateNeeded) _updateIndex();
        if (ltvUpdateNeeded) _updateLTVs();
    }


    function forceClose(address user) external nonReentrant {
        uint256 totalCollateralValue = _getAccountCollateralValueInUsd(user);
        uint256 hf = _healthFactor(user);
        uint256 debt = _getCurrentUserDebt(user);
        
        // Must be underwater in 1 of the 2 "stuck" scenarios
        if (debt == 0) revert AurumEngine__NoDebtToAbsorb();
        if (hf >= MIN_HEALTH_FACTOR) revert AurumEngine__HealthFactorOkay();
        if ((totalCollateralValue > MAX_FORCE_CLOSE_COLLATERAL_VALUE) && (hf > FORCE_CLOSE_HF_THRESHOLD)) {
            revert AurumEngine__IneligibleForForceClose(); 
        }
    
        // Seize all collateral for the treasury
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
        // Clear user's debt
        for (uint256 i = 0; i < s_collateralList.length; i++) {
            address token = s_collateralList[i];
            uint256 allocatedDebt = s_userDebtAllocation[user][token];
            if (allocatedDebt > 0) {
                s_userDebtAllocation[user][token] = 0;
                s_collateralInfo[token].totalNormalizedDebt -= allocatedDebt;
            }
        }
        s_userLastIndex[user] = s_cumulativeIndex;

        // Burn the debt from treasury AUSD
        i_ausd.transferFrom(i_treasury, address(this), debt);
        i_ausd.burn(debt);
        emit ForceClosed(user, debt, totalCollateralValue);
    }

    /**
     * @param collateralToken The collateral token address
     * @param volatilityFeed The new volatility feed address for the specified collateral token
     * @param newLtv The new LTV value for the specified collateral token
     * @param newDebtCeiling The new debt ceiling for the specified collateral token
     * @param isActive The new active flag value for the specified collateral token
     * @notice Allows the owner to update the LTV, debt ceiling, and active flags for a collateral token. Enter 0 or address(0) for any parameter you don't want to update.
     */
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

    /**
     * @param collateralToken The address of the collateral token to deposit
     * @param amountCollateral The amount of collateral to deposit
     * @param amountAUSDToMint The amount of AUSD to mint
     * @notice This function will deposit your collateral and mint the AUSD tokens in one transaction
     */
    function depositCollateralAndMintAUSD(address collateralToken, uint256 amountCollateral, uint256 amountAUSDToMint)
        external 
    {
        depositCollateral(collateralToken, amountCollateral);
        mintAUSD(amountAUSDToMint);
    }

    /**
     * @param collateralToken The address of the collateral token to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountAUSDToBurn The amount of AUSD to burn
     * @notice This function burns AUSD and redeems underlying collateral in one transaction
     */
    function redeemCollateralAndBurnAUSD(address collateralToken, uint256 amountCollateral, uint256 amountAUSDToBurn)
        external
    {
        burnAUSD(amountAUSDToBurn);
        redeemCollateral(collateralToken, amountCollateral);
    }

    /**
     * @param collateralToken The address of the collateral token to deposit
     * @param amountCollateral The amount of collateral to deposit
     * @notice This function will deposit a user's collateral into the protocol
     */
    function depositCollateral(address collateralToken, uint256 amountCollateral) public
        moreThanZero(amountCollateral)
        isAllowedToken(collateralToken)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][collateralToken] += amountCollateral;
        emit CollateralDeposited(msg.sender, collateralToken, amountCollateral);
        bool success = IERC20(collateralToken).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) revert AurumEngine__TransferFailed();
    }

    /**
     * @param collateralToken The address of the collateral token to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @notice To redeem collateral, the health factor must be at least 1 AFTER collateral is pulled
     */
    function redeemCollateral(address collateralToken, uint256 amountCollateral) public 
        moreThanZero(amountCollateral)
        isAllowedToken(collateralToken)
        nonReentrant
    {
        _redeemCollateral(collateralToken, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }


    /**
     * @param amountAUSDToMint The number of AUSD tokens to mint
     * @notice To mint AUSD, the user must have enough collateral to cover the minimum collateralization ratio of 125%
     */
    function mintAUSD(uint256 amountAUSDToMint) public moreThanZero(amountAUSDToMint) nonReentrant {
        _updateIndex(); // Accrue interest first
        // Set the user's last index
        s_userLastIndex[msg.sender] = s_cumulativeIndex;

        // Get the user's collateral breakdown
        (address[] memory collateralTokens, uint256[] memory usdValues, uint256 totalUsdValue, uint256 length) = _getUserCollateralBreakdown(msg.sender);
        if (length == 0) revert AurumEngine__NoCollateralDeposited();

        // Convert mint amount to normalized debt
        uint256 normalizedMintAmount = (amountAUSDToMint * PRECISION) / s_cumulativeIndex;

        // Calculate the total valid value & check debt ceilings
        (bool[] memory willHitDebtCeiling, uint256 totalValidValue) = _computeAllocationsAndCheckCeilings(collateralTokens, usdValues, totalUsdValue, length, normalizedMintAmount);

        // Allocate normalized debt to active collaterals
        _allocateDebt(collateralTokens, usdValues, totalUsdValue, totalValidValue, willHitDebtCeiling, length, normalizedMintAmount);
        
        // Update the user's total debt and mint them AUSD
        _revertIfHealthFactorIsBroken(msg.sender);
        emit MintAUSD(msg.sender, amountAUSDToMint);
        bool minted = i_ausd.mint(msg.sender, amountAUSDToMint);
        if (!minted) revert AurumEngine__MintFailed();
    }

    // TO-DO: add rebalanceDebt() for advanced users

    /**
     * @param amount The amount of AUSD to burn
     * @notice This burns a given amount of AUSD
     */
    function burnAUSD(uint256 amount) public moreThanZero(amount) {
        _burnAUSD(amount, msg.sender, msg.sender);
    }

    /**
     * @param collateralToken The address of the collateral token to take from the user
     * @param user The user who has broken the health factor. Their health factor should be below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of AUSD to burn to improve the user's health factor
     * @notice You can partially liquidate another user
     * @notice You will get a liquidation bonus for taking the user's funds
     * @notice This function assumes the protocol will be roughly 125% overcollateralized in order for this to work.
     * @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentivize the liquidators.
     *         For example, if there was a "black swan" event causing a sharp drop in the price of gold, before anyone could be liquidated.
     */
    function liquidate(address collateralToken, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        isAllowedToken(collateralToken)
        nonReentrant
    {
        _updateIndex();
        // Check health factor of user
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) revert AurumEngine__HealthFactorOkay();

        // Calculte dynamic close factor
        uint256 currentDebt = _getCurrentUserDebt(user);
        uint256 closeFactor = _closeFactor(user, collateralToken);
        uint256 maxDebtToCover = (currentDebt * closeFactor) / PRECISION;

        if (debtToCover > maxDebtToCover) debtToCover = maxDebtToCover;
        if (maxDebtToCover < MIN_DUST_THRESHOLD) debtToCover = currentDebt; // if dust pay off 100%
        
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateralToken, debtToCover);

        // Ensure the liquidator's profit is above the threshold
        uint256 liquidatorBonus = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_AND_FEE_PRECISION;
        uint256 profitUsd = _usdValue(collateralToken, liquidatorBonus);
        if (profitUsd < MIN_LIQUIDATION_PROFIT) revert AurumEngine__LiquidationNotProfitable();

        // Calculate the protocol's and liquidator's share
        uint256 protocolShare = (tokenAmountFromDebtCovered * PROTOCOL_LIQUIDATION_FEE) / LIQUIDATION_AND_FEE_PRECISION;
        uint256 liquidatorShare = tokenAmountFromDebtCovered + liquidatorBonus;
        uint256 totalCollateralToRedeem = liquidatorShare + protocolShare;

        // Redeem collateral for liquidator and protocol
        _redeemCollateral(collateralToken, liquidatorShare, user, msg.sender);
        _redeemCollateral(collateralToken, protocolShare, user, i_treasury);

        // Burn AUSD
        _burnAUSD(debtToCover, user, msg.sender);

        emit Liquidated(user, msg.sender, debtToCover, totalCollateralToRedeem, protocolShare);
    }

    /**************************************************************************/
    /*******************Private & Internal View Functions**********************/
    /**************************************************************************/
    function _updateIndex() internal {
        if (block.timestamp == s_indexLastUpdate) return;

        // Get total actual debt = sum of all normalized debt * current index / 1e18
        // Since index may have changed, need the total normalized debt first
        uint256 totalNormalizedDebt;
        for (uint256 i = 0; i < s_collateralList.length; i++) {
            totalNormalizedDebt += s_collateralInfo[s_collateralList[i]].totalNormalizedDebt;
        }
        uint256 totalActualDebt = (totalNormalizedDebt * s_cumulativeIndex) / PRECISION;

        // Total collateral value in USD (actual, from all deposited assets)
        uint256 totalCollateralValue = getTotalProtocolCollateralValue();

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


    function _updateLTVs() internal {
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

        // Sum normalized debt across all collaterals
        uint256 totalNormalized;
        for (uint256 i = 0; i < s_collateralList.length; i++) {
            totalNormalized += s_userDebtAllocation[onBehalfOf][s_collateralList[i]];
        }
        if (totalNormalized == 0) revert AurumEngine__NothingToBurn();

        uint256 actualDebt = (totalNormalized * s_cumulativeIndex) / PRECISION;
        uint256 principal = (totalNormalized * s_userLastIndex[onBehalfOf]) / PRECISION;
        uint256 interestAccrued = actualDebt - principal;
        uint256 protocolFee = (interestAccrued * PROTOCOL_RESERVE_PERCENT) / LIQUIDATION_AND_FEE_PRECISION;

        if (amountAUSDToBurn > actualDebt) amountAUSDToBurn = actualDebt;
        uint256 reductionFactor = (amountAUSDToBurn * PRECISION) / actualDebt;
        uint256 totalNormTarget = (totalNormalized * reductionFactor) / PRECISION;
        uint256 remainingNorm = totalNormTarget;

        // Reduce each collateral’s normalized debt proportionally
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

        // Update user’s last index and emit event
        s_userLastIndex[onBehalfOf] = s_cumulativeIndex;
        emit BurnAUSD(onBehalfOf, amountAUSDToBurn);

        // Transfer and burn user's AUSD
        bool success = i_ausd.transferFrom(ausdFrom, address(this), amountAUSDToBurn);
        if (!success) revert AurumEngine__TransferFailed();
        i_ausd.burn(amountAUSDToBurn);

        // Mint protocol fee to treasury
        if (protocolFee > 0) i_ausd.mint(i_treasury, protocolFee);
    }

    /// @dev Internal redeem function used primarily for liquidate (and also user redemptions)
    function _redeemCollateral(address collateralToken, uint256 amountCollateral, address from, address to) private {
        s_collateralDeposited[from][collateralToken] -= amountCollateral;
        emit CollateralRedeemed(from, to, amountCollateral);
        bool success = IERC20(collateralToken).transfer(to, amountCollateral);
        if (!success) revert AurumEngine__TransferFailed();
    }

    // Helper function to get user's collateral breakdown
    function _getUserCollateralBreakdown(address user) private view returns (address[] memory collateralTokens, uint256[] memory usdValues, uint256 totalUsdValue, uint256 activeCount) {
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

    // Compute debt allocations and check collateral token debt ceilings
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
            // Weighted allocation of normalized debt
            uint256 weight = (usdValues[i] * PRECISION) / totalUsdValue;
            uint256 allocatedNorm = (normalizedMint * weight) / PRECISION;
            // Convert to actual debt for ceiling check
            uint256 actualIncrease = (allocatedNorm * currentIndex) / PRECISION;
            uint256 currentGlobalActualDebt = (s_collateralInfo[token].totalNormalizedDebt * currentIndex) / PRECISION;

            // Check if this allocation would exceed the debt ceiling
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

    // Gets the USD value for an amount of collateral tokens
    function _usdValue(address collateralToken, uint256 amount) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_collateralInfo[collateralToken].priceFeed);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    // Returns how close to liquidation a user is: if HF < 1, user becomes liquidation candidate
    function _healthFactor(address user) private view returns (uint256) {
        // Get the total user debt, if no user debt, return
        uint256 totalActualDebt = _getCurrentUserDebt(user);
        if (totalActualDebt == 0) return type(uint256).max;
        // If totalActualDebt > 0, calculate HF
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

        // Calculate volatility excess
        CollateralInfo memory info = s_collateralInfo[collateralToken];
        uint256 volatility = IVolatilityOracle(info.volatilityFeed).getAnnualizedVolatility();
        uint256 excess = volatility > info.baselineVolatility ? volatility - info.baselineVolatility : 0;
        uint256 volatilityBoost = (excess * CLOSE_FACTOR_BOOST_PER_STEP) / TEN_PERCENT;
        uint256 effectiveMaxCloseFactor = info.maxCloseFactor + volatilityBoost;
        if (effectiveMaxCloseFactor > PRECISION) effectiveMaxCloseFactor = PRECISION;

        // Calculate close factor
        uint256 deficit = MIN_HEALTH_FACTOR - userHf;
        uint256 closeFactor = info.minCloseFactor + ((effectiveMaxCloseFactor - info.minCloseFactor) * deficit) / PRECISION;
 
        return closeFactor;
    }

    // Check the health factor and revert if it is below MIN_HEALTH_FACTOR
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) revert AurumEngine__BreaksHealthFactor(userHealthFactor);
    }

    function _getCurrentUserDebt(address user) internal view returns (uint256 actualDebt) {
        uint256 totalNorm;
        for (uint256 i = 0; i < s_collateralList.length; i++) {
            totalNorm += s_userDebtAllocation[user][s_collateralList[i]];
        }
        actualDebt = (totalNorm * s_cumulativeIndex) / PRECISION;
    }

    function _getAccountCollateralValueInUsd(address user) internal view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralList.length; i++) {
            address token = s_collateralList[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _usdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    /**************************************************************************/
    /*********************Public & External View Functions*********************/
    /**************************************************************************/
    /**
     * @param collateralToken The address of the collateral token
     * @param usdAmountInWei The USD amount in wei
     * @return The amount of collateral tokens given a USD value
     */
    function getTokenAmountFromUsd(address collateralToken, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_collateralInfo[collateralToken].priceFeed);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    /**
     * @param collateralToken The address of the collateral token
     * @param amount The amount of collateral tokens
     * @return The USD value of a given amount of collateral tokens
     */
    function getUsdValue(address collateralToken, uint256 amount) external view returns (uint256) {
        return _usdValue(collateralToken, amount);
    }

    function getTotalProtocolCollateralValue() public view returns (uint256 total) {
        for (uint256 i = 0; i < s_collateralList.length; i++) {
            address token = s_collateralList[i];
            uint256 balance = IERC20(token).balanceOf(address(this));
            total += _usdValue(token, balance);
        }
    }


    function getLiquidationProfit(address collateralToken, address user, uint256 debtToCover) external view returns (uint256 profitUsd, uint256 bonusCollateral) {
        if (_healthFactor(user) >= MIN_HEALTH_FACTOR) revert AurumEngine__HealthFactorOkay();

        uint256 currentDebt = _getCurrentUserDebt(user);
        uint256 closeFactor = _closeFactor(user, collateralToken);
        uint256 maxDebtToCover = (debtToCover * closeFactor) / PRECISION;
        if (debtToCover > maxDebtToCover) debtToCover = maxDebtToCover;
        if (maxDebtToCover < MIN_DUST_THRESHOLD) debtToCover = currentDebt;
        
        uint256 tokenAmount = getTokenAmountFromUsd(collateralToken, debtToCover);
        bonusCollateral = (tokenAmount * LIQUIDATION_BONUS) / LIQUIDATION_AND_FEE_PRECISION;
        profitUsd = _usdValue(collateralToken, bonusCollateral);
    }

    /**
     * @param collateralToken The address of the collateral token
     * @return CollateralInfo collateral token info (price feed, ltv, debt ceiling, total normalized debt, and active flag) for a collateral token
     */
    function getCollateralInfo(address collateralToken) external view returns (CollateralInfo memory) {
        return s_collateralInfo[collateralToken];
    }

    // Complete user account snapshot
    function getUserAccountData(address user) external view returns (UserAccountData memory data) {
        uint256 totalNorm;
        uint256 activeCount;
        // First pass: count active collaterals
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
        data.totalCollateralValueInUsd = _getAccountCollateralValueInUsd(user);
        data.healthFactor = _healthFactor(user);
        data.lastIndex = s_userLastIndex[user];
    }
}