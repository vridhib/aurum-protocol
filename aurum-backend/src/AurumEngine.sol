// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {AurumUSD} from "./AurumUSD.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
import {InterestRateModel} from "./interest/InterestRateModel.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {AutomationCompatible} from "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AurumEngine
 * @author
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg.
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
    error AurumEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
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

    using OracleLib for AggregatorV3Interface;

    /*----------Type Declarations----------*/
    /// @notice A type that aggregates critical account info together
    struct AccountInfo {
        uint256 healthFactor;          // Current user health factor
        uint256 totalAUSDMinted;       // Total amount of minted AUSD
        uint256 collateralValueInUsd;  // Total USD value of deposited collateral
    }

    /// @notice A type that aggregates critical collateral token info together
    struct CollateralInfo {
        address priceFeed;            // Chainlink price feed address
        uint256 ltv;                  // Liquidation threshold
        uint256 debtCeiling;          // Max total AUSD mintable against this collateral
        uint256 totalNormalizedDebt;            // Current total AUSD minted against this collateral
        bool isActive;                // Can users deposit/mint against it?
    }

    /*----------State Variables----------*/
    // Precision Constants
    /// @notice Used to adjust the precision of Chainlink prices from 8 decimals to 18 decimals
    uint256 public constant ADDITIONAL_FEED_PRECISION = 1e10;
    /// @notice The standard precision used for AUSD calculations
    uint256 public constant PRECISION = 1e18;

    // Economic Constants
    /// @notice The percentage (80%) of collateral value counted as "safe" for backing debt
    /// @dev 80% implies users must be 125% collateralized (100 / 80 = 1.25)
    uint256 public constant LIQUIDATION_THRESHOLD = 80;   // To be scrapped with a future feature

    uint256 public constant DEFAULT_LTV = 80; // 80% (still using LIQUIDATION_PRECISION = 100)
    uint256 public constant DEFAULT_DEBT_CEILING = 50_000_000 * 1e18; // 50M AUSD per collateral

    /// @notice Precision divisor for percentage calculations
    uint256 public constant LIQUIDATION_PRECISION = 100;

    /// @notice The minimum health factor (1e18). Falling below this makes a user liquidatable
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;

    /// @notice If debt is below this amount, the close factor is ignored to allow full liquidation (cleaning dust)
    uint256 public constant MIN_DUST_THRESHOLD = 1e18;

    /// @notice A bonus percentage given to liquidators to incentivize clearing bad debt
    /// @dev Set to 5% (lower than standard 10%) because gold is less volatile
    uint256 public constant LIQUIDATION_BONUS = 5;

    /// @notice The percentage of the liquidation bonus taken by the protocol as revenue/insurance
    uint256 public constant PROTOCOL_FEE = 5;

    /// @notice A liquidation limit of 50% of debt to prevent total user wipeouts on small dips
    uint256 public constant LIQUIDATION_CLOSE_FACTOR = 50;

    /// @notice Protocol reserve cut of interest
    uint256 public constant PROTOCOL_RESERVE_PERCENT = 10;

    uint256 public constant PROTOCOL_FEE_PRECISION = 100;

    // Storage Variables
    /// @notice A mapping of user addresses to a mapping of deposited collateral amounts
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited;

    /// @notice A mapping of collateral tokens to their info (price feed, ltv, debt ceiling, etc.)
    mapping(address collateral => CollateralInfo info) private s_collateralInfo;

    /// @notice A mapping of users to a mapping of the debt allocations for certain collateral tokens
    mapping(address user => mapping(address backingCollateral => uint256 normalizedDebt)) private s_userDebtAllocation;

    /// @notice Last cumulative index when user last minted or repaid
    mapping(address => uint256) private s_userLastIndex;

    /// @notice The ERC20 address array of supported tokens (AUR + WETH)
    address[] private s_collateralList;

    /// @notice The interest rate model contract
    InterestRateModel private s_interestRateModel;

    /// @notice Global cumulative index
    uint256 private s_cumulativeIndex = 1e18;

    /// @notice Keeps track of the last time the index was updated
    uint256 private s_lastUpdateTimestamp;

    /// @notice Treasury address that collects protocol fees from interest
    address private s_treasury;

    /// @notice The AUSD token address
    AurumUSD private immutable i_ausd;



    /*----------Events----------*/
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, uint256 amount);
    event Liquidated(address indexed user, address indexed liquidator, uint256 debtToCover, uint256 totalCollateralToRedeem, uint256 protocolShare);
    event MintAUSD(address indexed user, uint256 amount);
    event DebtCeilingHit(address indexed token, uint256 totalNormalizedDebt, uint256 allocatedDebt);
    event DebtAllocated(address user, address token, uint256 allocatedDebt);
    event DebtDeallocated(address user, address token, uint256 debtReduction);
    event BurnAUSD(address indexed user, uint256 amount);

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
        address ausdAddress,
        address interestRateModelAddress,
        address treasuryAddress
    ) 
        Ownable(msg.sender) 
    {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert AurumEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_collateralInfo[tokenAddresses[i]] = CollateralInfo({
                priceFeed: priceFeedAddresses[i],
                ltv: DEFAULT_LTV,                  
                debtCeiling: DEFAULT_DEBT_CEILING, 
                totalNormalizedDebt: 0,
                isActive: true
            });
            s_collateralList.push(tokenAddresses[i]);
        }
        i_ausd = AurumUSD(ausdAddress);
        s_interestRateModel = InterestRateModel(interestRateModelAddress);
        s_treasury = treasuryAddress;
        s_lastUpdateTimestamp = block.timestamp;
    }

    function updateIndex() external {
        _updateIndex();
    }

    /**
     * @param collateralToken The collateral token address
     * @param newLtv The new LTV value
     * @param newDebtCeiling The new debt ceiling
     * @param isActive The new active flag value
     * @notice Allows the owner to update the LTV, debt ceiling, and active flags for a collateral token
     */
    function setCollateralInfo(
        address collateralToken, 
        uint256 newLtv, 
        uint256 newDebtCeiling, 
        bool isActive
    ) external onlyOwner 
    {
        s_collateralInfo[collateralToken] = CollateralInfo({
            priceFeed: s_collateralInfo[collateralToken].priceFeed,
            ltv: newLtv,                  
            debtCeiling: newDebtCeiling, 
            totalNormalizedDebt: s_collateralInfo[collateralToken].totalNormalizedDebt,
            isActive: isActive
        });
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

        // Prevent user from being 100% liquidated over small dips
        uint256 currentDebt = getCurrentUserDebt(user);
        uint256 maxDebtToCover = (currentDebt * LIQUIDATION_CLOSE_FACTOR) / 100;
        if (debtToCover > maxDebtToCover) {
            debtToCover = maxDebtToCover;
        }

        // If the result is tiny (dust), just let liquidator pay off all of user's debt
        if (maxDebtToCover < MIN_DUST_THRESHOLD) {
            debtToCover = currentDebt; // Pay 100%
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateralToken, debtToCover);

        // Calculate the protocol's and liquidator's share
        uint256 protocolShare = (tokenAmountFromDebtCovered * PROTOCOL_FEE) / LIQUIDATION_PRECISION;
        uint256 liquidatorBonus = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 liquidatorShare = tokenAmountFromDebtCovered + liquidatorBonus;

        uint256 totalCollateralToRedeem = liquidatorShare + protocolShare;

        // Redeem collateral for liquidator and protocol
        _redeemCollateral(collateralToken, liquidatorShare, user, msg.sender);
        _redeemCollateral(collateralToken, protocolShare, user, address(this));

        // Burn AUSD
        _burnAUSD(debtToCover, user, msg.sender);

        emit Liquidated(user, msg.sender, debtToCover, totalCollateralToRedeem, protocolShare);
    }

    /************************************************************************************************/
    /********************************Private & Internal View Functions*******************************/
    /************************************************************************************************/
    function _updateIndex() internal {
        if (block.timestamp == s_lastUpdateTimestamp) return;

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
            s_lastUpdateTimestamp = block.timestamp;
            return;
        }

        uint256 utilization = (totalActualDebt * PRECISION) / totalCollateralValue;
        if (utilization > PRECISION) utilization = PRECISION; // safety

        uint256 borrowRatePerSecond = s_interestRateModel.getBorrowRate(utilization);
        uint256 timeElapsed = block.timestamp - s_lastUpdateTimestamp;

        // newIndex = oldIndex * (1 + rate * time)
        s_cumulativeIndex = s_cumulativeIndex * (PRECISION + borrowRatePerSecond * timeElapsed) / PRECISION;
        s_lastUpdateTimestamp = block.timestamp;
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
        uint256 protocolFee = (interestAccrued * PROTOCOL_RESERVE_PERCENT) / PROTOCOL_FEE_PRECISION;

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
        if (protocolFee > 0) i_ausd.mint(s_treasury, protocolFee);
    }

    /// @dev Internal redeem function used primarily for liquidate (and also user redemptions)
    function _redeemCollateral(address collateralToken, uint256 amountCollateral, address from, address to) private {
        s_collateralDeposited[from][collateralToken] -= amountCollateral;
        emit CollateralRedeemed(from, to, amountCollateral);
        bool success = IERC20(collateralToken).transfer(to, amountCollateral);
        if (!success) revert AurumEngine__TransferFailed();
    }

    // Gets the user's minted AUSD and the value of the backing collateral and the health factor
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalAUSDMinted, uint256 collateralValueInUsd)
    {
        totalAUSDMinted = getCurrentUserDebt(user);
        collateralValueInUsd = getAccountCollateralValueInUsd(user);
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
        uint256 totalActualDebt = getCurrentUserDebt(user);
        if (totalActualDebt == 0) return type(uint256).max;
        // If totalActualDebt > 0, calculate HF
        uint256 totalAdjustedCollateral = 0;
        for (uint256 i = 0; i < s_collateralList.length; i++) {
            address token = s_collateralList[i];
            uint256 amount = s_collateralDeposited[user][token];
            if (amount == 0) continue;
            uint256 usdValue = _usdValue(token, amount);
            uint256 ltv = s_collateralInfo[token].ltv;
            totalAdjustedCollateral += (usdValue * ltv) / LIQUIDATION_PRECISION;
        }
        return (totalAdjustedCollateral * PRECISION) / totalActualDebt;
    }

    // Check the health factor and revert if it is below MIN_HEALTH_FACTOR
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) revert AurumEngine__BreaksHealthFactor(userHealthFactor);
    }

    /************************************************************************************************/
    /********************************Public & External View Functions********************************/
    /************************************************************************************************/
    /**
     * @notice Called by Chainlink nodes to determine if an upkeep is needed
     * @param checkData optional data passed in when upkeep was registered
     * @return upkeepNeeded true if conditions are met to call performUpkeep
     * @return performData encoded data to pass to performUpkeep
     */
    function checkUpkeep(bytes calldata checkData) public view override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        // Always return false if no debt exists
        uint256 totalNormalizedDebt = 0;
        for (uint256 i = 0; i < s_collateralList.length; i++) {
            totalNormalizedDebt += s_collateralInfo[s_collateralList[i]].totalNormalizedDebt;
        }
        if (totalNormalizedDebt == 0) return (false, "0");

        // Return false if no time has passed since last update
        if (block.timestamp <= s_lastUpdateTimestamp) return (false, "0");

        // Check if enough time has elapsed
        uint256 minInterval = 1 hours;
        if (block.timestamp - s_lastUpdateTimestamp < minInterval) {
            return (false, "0");
        }

        // If all checks pass, upkeep is needed
        upkeepNeeded = true;
        performData = checkData;
    }

    /**
     * @notice Called by Chainlink nodes when `checkUpkeep` returns true
     * @param performData data passed from `checkUpkeep`
     */
    function performUpkeep(bytes calldata performData) external override {
        (bool upkeepNeeded, ) = checkUpkeep(performData);
        if (!upkeepNeeded) return;
        _updateIndex();
    }



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
     * @param user The user to query for account information
     * @return totalCollateralValueInUsd The total collateral value in USD for a given user
     */
    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralList.length; i++) {
            address token = s_collateralList[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _usdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getTotalProtocolCollateralValue() public view returns (uint256 total) {
        for (uint256 i = 0; i < s_collateralList.length; i++) {
            address token = s_collateralList[i];
            uint256 balance = IERC20(token).balanceOf(address(this));
            total += _usdValue(token, balance);
        }
        return total;
    }

    /**
     * @param collateralToken The address of the collateral token
     * @param user The user to query for account information
     * @return The total quantity of collateral tokens for a given user
     */
    function getUserCollateralAmount(address collateralToken, address user) external view returns (uint256) {
        return s_collateralDeposited[user][collateralToken];
    }

    /**
     * @param user The user to query for account information
     * @return The health factor value for a user
     */
    function getUserHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    /**
     * @param collateralToken The address of the collateral token
     * @param amount The amount of collateral tokens
     * @return The USD value of a given amount of collateral tokens
     */
    function getUsdValue(address collateralToken, uint256 amount) external view returns (uint256) {
        return _usdValue(collateralToken, amount);
    }

    /**
     * @param user The user to query for aggregated account information
     * @return All account info (health factor, minted AUSD, and collateral value) for a user
     */
    function getAccountInformation(address user) external view returns (AccountInfo memory) {
        uint256 healthFactor = _healthFactor(user);
        (uint256 totalAUSDMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);

        return AccountInfo({
            healthFactor: healthFactor, 
            totalAUSDMinted: totalAUSDMinted, 
            collateralValueInUsd: collateralValueInUsd
        });
    }

    /**
     * @param user The user to query for account information
     * @return actualDebt The amount of AUSD tokens a given user has minted + accrued interest fees
     */
    function getCurrentUserDebt(address user) public view returns (uint256 actualDebt) {
        uint256 totalNorm;
        for (uint256 i = 0; i < s_collateralList.length; i++) {
            totalNorm += s_userDebtAllocation[user][s_collateralList[i]];
        }
        actualDebt = (totalNorm * s_cumulativeIndex) / PRECISION;
    }


    function getCollateralTokenPriceFeed(address collateralToken) external view returns (address) {
        return s_collateralInfo[collateralToken].priceFeed;
    }

    function getCollateralTokenLtv(address collateralToken) external view returns (uint256) {
        return s_collateralInfo[collateralToken].ltv;
    }

    function getCollateralList() external view returns (address[] memory) {
        return s_collateralList;
    }

    /// @return The address of the AurumUSD contract
    function getAUSD() external view returns (address) {
        return address(i_ausd);
    }

    /**
     * @param user The user to query about
     * @param collateralToken The collateral token address
     * @return The user's debt allocation for a certain collateral token
     */
    function getUserDebtAllocation(address user, address collateralToken) external view returns (uint256) {
        return s_userDebtAllocation[user][collateralToken];
    }

    /**
     * @param collateralToken The collateral token address
     * @return The user's debt allocation for a certain collateral token
     */
    function getCollateralTotalDebt(address collateralToken) external view returns (uint256) {
        return s_collateralInfo[collateralToken].totalNormalizedDebt;
    }

    function getCumulativeIndex() external view returns (uint256) {
        return s_cumulativeIndex;
    }

    function getTreasury() external view returns (address) {
        return s_treasury;
    }

    function getUserLastIndex(address user) external view returns (uint256) {
        return s_userLastIndex[user];
    }

    function getInterestRateModel() external view returns (address) {
        return address(s_interestRateModel);
    }
}