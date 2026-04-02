// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AurumUSD} from "./AurumUSD.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";


/**
 * @title AurumEngine
 * @author Vridhi Brahmbhatt
 * 
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg.
 * This stablecoin has the following properties:
 *  - Exogenous Collateral
 *  - Dollar Pegged
 *  - Algorithmically Stable
 * 
 * The Aurum Protocol should always be "overcollateralized". At no point, should the value of all the collateral (AUR) <= the dollar backed value of all the AUSD.
 * 
 * @notice This contract is the core of the Aurum Protocol. It handles all the logic for minting and redeeming AUSD, as well as depositing and withdrawing collateral.
 */
contract AurumEngine is ReentrancyGuard {
    /*----------Errors----------*/
    error AurumEngine__NeedsMoreThanZero();
    error AurumEngine__TransferFailed();
    error AurumEngine__BreaksHealthFactor(uint256 healthFactor);
    error AurumEngine__HealthFactorOkay();
    error AurumEngine__HealthFactorNotImproved();
    error AurumEngine__MintFailed();
    error AurumEngine__ExceedsMaxSupply();

    using OracleLib for AggregatorV3Interface;

    /*----------Type Declarations----------*/
    /// @notice A type that aggregates critical account info together
    struct AccountInfo {
        uint256 healthFactor;
        uint256 totalAUSDMinted;
        uint256 collateralValueInUsd;
    }

    /*----------State Variables----------*/
    // Precision Constants
    /// @notice Used to adjust the precision of Chainlink prices from 8 decimals to 18 decimals
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;    
    /// @notice The standard precision used for AUSD calculations
    uint256 private constant PRECISION = 1e18;       

    // Economic Constants
    /// @notice The percentage (80%) of collateral value counted as "safe" for backing debt
    /// @dev 80% implies users must be 125% collateralized (100 / 80 = 1.25)
    uint256 private constant LIQUIDATION_THRESHOLD = 80;          
    
    /// @notice Precision divisor for percentage calculations
    uint256 private constant LIQUIDATION_PRECISION = 100;          
    
    /// @notice The minimum health factor (1e18). Falling below this makes a user liquidatable
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;     

    /// @notice If debt is below this amount, the close factor is ignored to allow full liquidation (cleaning dust)
    uint256 private constant MIN_DUST_THRESHOLD = 1e18;       
    
    /// @notice A bonus percentage given to liquidators to incentivize clearing bad debt
    /// @dev Set to 5% (lower than standard 10%) because gold is less volatile
    uint256 private constant LIQUIDATION_BONUS = 5;                
    
    /// @notice The percentage of the liquidation bonus taken by the protocol as revenue/insurance
    uint256 private constant PROTOCOL_FEE = 5;                     
    
    /// @notice A hard limit on the total supply of AUSD to prevent infinite minting risks associated with RWAs
    uint256 private constant MAX_AUSD_SUPPLY = 1000000 * 1e18;      
    
    /// @notice A liquidation limit of 50% of debt to prevent total user wipeouts on small dips
    uint256 private constant LIQUIDATION_CLOSE_FACTOR = 50;


    // Storage Variables
    /// @notice The Chainlink XAU/USD price feed address
    address private s_priceFeed;                                                       
    
    /// @notice A mapping of user addresses to deposited collateral amounts (AUR tokens)
    mapping(address user => uint256 amountCollateral) private s_collateralDeposited;    
    
    /// @notice A mapping of user addresses to the amount of AUSD debt they have minted
    mapping(address user => uint256 amountAUSDMinted) private s_AUSDMinted;               
    
    /// @notice The ERC20 address of the Gold token (AUR) used as collateral
    address private s_collateralToken;                                                 
    
    /// @notice The AUSD token address
    AurumUSD private immutable i_ausd; 


    /*----------Events----------*/
    event CollateralDeposited(address indexed user, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, uint256 amount);
    event Liquidated(address indexed user, address indexed liquidator, uint256 debtToCover, uint256 totalCollateralToRedeem, uint256 protocolShare);
    event MintAUSD(address indexed user, uint256 amount);
    event BurnAUSD(address indexed user, uint256 amount);

    /*----------Modifiers----------*/
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert AurumEngine__NeedsMoreThanZero();
        _;
    }


    /*----------Functions----------*/
    constructor(address tokenAddress, address priceFeedAddress, address auAddress) {
        s_priceFeed = priceFeedAddress;
        s_collateralToken = tokenAddress;
        i_ausd = AurumUSD(auAddress);
    }


    /**
     * @param amountCollateral The amount of collateral to deposit
     * @param amountAUSDToMint The amount of AUSD to mint
     * @notice This function will deposit your collateral and mint the AUSD tokens in one transaction
     */
    function depositCollateralAndMintAUSD(uint256 amountCollateral, uint256 amountAUSDToMint) external {
        depositCollateral(amountCollateral);
        mintAUSD(amountAUSDToMint);
    }


    /**
     * @param amountCollateral The amount of collateral to redeem
     * @param amountAUSDToBurn The amount of AUSD to burn
     * @notice This function burns AUSD and redeems underlying collateral in one transaction
     */
    function redeemCollateralAndBurnAUSD(uint256 amountCollateral, uint256 amountAUSDToBurn) external {
        burnAUSD(amountAUSDToBurn);
        redeemCollateral(amountCollateral);
    }


    /**
     * @param amountCollateral The amount of collateral to deposit
     * @notice This function will deposit a user's collateral into the protocol
     */
    function depositCollateral(uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant {
        bool success = IERC20(s_collateralToken).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) revert AurumEngine__TransferFailed();
        s_collateralDeposited[msg.sender] += amountCollateral;
        emit CollateralDeposited(msg.sender, amountCollateral);
    }


    /**
     * @param amountCollateral The amount of collateral to redeem
     * @notice To redeem collateral, the health factor must be at least 1 AFTER collateral is pulled
     */
    function redeemCollateral(uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(msg.sender, msg.sender, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }


    /**
     * @param amountAUSDToMint The number of AUSD tokens to mint
     * @notice To mint AUSD, the user must have enough collateral to cover the minimum collateralization ratio of 125%
     */
    function mintAUSD(uint256 amountAUSDToMint) public moreThanZero(amountAUSDToMint) nonReentrant {
        if (i_ausd.totalSupply() + amountAUSDToMint > MAX_AUSD_SUPPLY) revert AurumEngine__ExceedsMaxSupply();
        
        s_AUSDMinted[msg.sender] += amountAUSDToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        emit MintAUSD(msg.sender, amountAUSDToMint);

        bool minted = i_ausd.mint(msg.sender, amountAUSDToMint);
        if(!minted) revert AurumEngine__MintFailed();
    }


    /**
     * @param amount The amount of AUSD to burn
     * @notice This burns a given amount of AUSD
     */
    function burnAUSD(uint256 amount) public moreThanZero(amount) {
        _burnAUSD(amount, msg.sender, msg.sender);
    }


    /**
     * @param user The user who has broken the health factor. Their health factor should be below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of AUSD to burn to improve the user's health factor
     * @notice You can partially liquidate another user
     * @notice You will get a liquidation bonus for taking the user's funds
     * @notice This function assumes the protocol will be roughly 125% overcollateralized in order for this to work.
     * @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentivize the liquidators.
     *         For example, if there was a "black swan" event causing a sharp drop in the price of gold, before anyone could be liquidated.
     */
    function liquidate(address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant {
        // Check health factor of user
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) revert AurumEngine__HealthFactorOkay();

        // Prevent user from being 100% liquidated over small dips
        uint256 currentDebt = s_AUSDMinted[user];
        uint256 maxDebtToCover = (currentDebt * LIQUIDATION_CLOSE_FACTOR) / 100;
        if (debtToCover > maxDebtToCover) {
            debtToCover = maxDebtToCover;
        }

        // If the result is tiny (dust), just let liquidator pay off all of user's debt
        if (maxDebtToCover < MIN_DUST_THRESHOLD) {
            debtToCover = currentDebt; // Pay 100%
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(debtToCover);

        // Calculate the protocol's and liquidator's share
        uint256 protocolShare = (tokenAmountFromDebtCovered * PROTOCOL_FEE) / LIQUIDATION_PRECISION;
        uint256 liquidatorBonus = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 liquidatorShare = tokenAmountFromDebtCovered + liquidatorBonus;

        uint256 totalCollateralToRedeem = liquidatorShare + protocolShare;

        // Redeem collateral for liquidator and protocol
        _redeemCollateral(user, msg.sender, liquidatorShare);
        _redeemCollateral(user, address(this), protocolShare);

        // Burn AUSD
        _burnAUSD(debtToCover, user, msg.sender);

        emit Liquidated(user, msg.sender, debtToCover, totalCollateralToRedeem, protocolShare);
    }


    /************************************************************************************************/
    /********************************Private & Internal View Functions*******************************/
    /************************************************************************************************/
    // Burns AUSD
    function _burnAUSD(uint256 amountAUSDToBurn, address onBehalfOf, address auFrom) private {
        s_AUSDMinted[onBehalfOf] -= amountAUSDToBurn;
        emit BurnAUSD(onBehalfOf, amountAUSDToBurn);
        
        bool success = i_ausd.transferFrom(auFrom, address(this), amountAUSDToBurn);
        if (!success) revert AurumEngine__TransferFailed();
        i_ausd.burn(amountAUSDToBurn);
    }


    // Redeems collateral
    function _redeemCollateral(address from, address to, uint256 amountCollateral) private {
        s_collateralDeposited[from] -= amountCollateral;
        emit CollateralRedeemed(from, to, amountCollateral);
        bool success = IERC20(s_collateralToken).transfer(to, amountCollateral);
        if (!success) revert AurumEngine__TransferFailed();
    }


    // Gets the user's minted AUSD and the value of the backing collateral
    function _getAccountInformation(address user) private view returns(uint256 totalAUSDMinted, uint256 collateralValueInUsd) {
        totalAUSDMinted = s_AUSDMinted[user];
        collateralValueInUsd = _usdValue(s_collateralDeposited[user]);
    }


    // Gets the USD value for an amount of collateral tokens 
    function _usdValue(uint256 amount) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION; 
    }


    // Returns how close to liquidation a user is
    // If a user goes below 1, then that user becomes a candidate for liquidation
    function _healthFactor(address user) private view returns(uint256) {
        (uint256 totalAUSDMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        if (totalAUSDMinted == 0) return type(uint256).max;

        return (collateralAdjustedForThreshold * PRECISION) / totalAUSDMinted;
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
     * @param usdAmountInWei The USD amount in wei
     * @return The amount of collateral tokens given a USD value
     */
    function getTokenAmountFromUsd(uint256 usdAmountInWei) public view returns(uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    /**
     * @param user The user to query for account information
     * @return The total quantity of collateral tokens for a given user
     */
    function getAmountCollateral(address user) external view returns (uint256) {
        return s_collateralDeposited[user];
    }

    /**
     * @param user The user to query for account information
     * @return The health factor value for a user
     */
    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    /**
     * @param amount The amount of collateral tokens
     * @return The USD value of a given amount of collateral tokens
     */
    function getUsdValue(uint256 amount) external view returns (uint256) {
        return _usdValue(amount);
    }

    /**
     * @param user The user to query for account information
     * @return The total collateral value in USD for a given user
     */
    function getAccountCollateralValueInUsd(address user) external view returns (uint256) {
        (, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return collateralValueInUsd;
    }

    /**
     * @param user The user to query for account information
     * @return The amount of AUSD tokens a given user has minted
     */
    function getAUSDMinted(address user) external view returns (uint256) {
        return s_AUSDMinted[user];
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

    /// @return The price feed address for the protocol
    function getCollateralTokenPriceFeed() external view returns (address) {
        return s_priceFeed;
    }

    /// @return The address of the AurumUSD contract
    function getAUSD() external view returns (address) {
        return address(i_ausd);
    }

    /// @return The standard precision used for AUSD calculations
    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    /// @return The additional feed precision used to adjust the precision of Chainlink prices from 8 decimals to 18 decimals
    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    /// @return The percentage of collateral value counted as "safe" for backing debt
    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }
    
    /// @return The percentage given to liquidators to incentivize clearing bad debt
    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    /// @return The precision divisor for liquidation percentage calculations
    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    /// @return The protocol's minimum required health factor
    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    /// @return The percentage of the liquidation bonus taken by the protocol as revenue
    function getProtocolFee() external pure returns (uint256) {
        return PROTOCOL_FEE;
    }

    /// @return A given debt amount where the close factor is ignored to allow full liquidation (cleaning dust)
    function getMinDustThreshold() external pure returns (uint256) {
        return MIN_DUST_THRESHOLD;
    }

    /// @return A liquidation limit to prevent total user wipeouts on small dips
    function getLiquidationCloseFactor() external pure returns (uint256) {
        return LIQUIDATION_CLOSE_FACTOR;
    }

    /// @return The maximum supply of AUSD allowed to be in circulation
    function getMaxAUSDSupply() external pure returns (uint256) {
        return MAX_AUSD_SUPPLY;
    }
}