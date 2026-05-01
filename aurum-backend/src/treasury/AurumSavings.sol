// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


/**
 * @title AurumSavings
 * @notice A savings contract where AUSD holders can deposit to earn passive yield.
 * @dev Yield is generated from protocol fees (interest on borrowing and liquidation 
 *      bonuses) and distributed proportionally to depositors using a scaled‑share 
 *      accrual model. The savings rate (APY) can only be updated by the treasury 
 *      address.
 */
contract AurumSavings {
    error AurumSavings__InsufficientShares();
    error AurumSavings__OnlyTreasuryCanSetSavingsRate();
    error AurumSavings__MustBeGreaterThanZero();
    error AurumSavings__SavingsRateTooHigh();

    using SafeERC20 for IERC20;

    uint256 private constant PRECISION = 1e18;
    uint256 private constant ONE_YEAR = 365 days;
    uint256 private constant MAX_SAVINGS_CAP = 0.20e18; // 20%

    uint256 private s_savingsRate = 0.03e18;            // 3% APY
    uint256 private s_totalShares;
    uint256 private s_accruedPerShare = 1e18;
    uint256 private s_lastUpdate;
    mapping(address user => uint256 shares) private s_userShares;

    IERC20 private immutable i_ausd;
    address private immutable i_treasury;

    event Deposited(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 amount, uint256 shares);
    event SavingsRateUpdated(uint256 oldRate, uint256 newRate);


    /// @dev Accrues yield since the last update before executing any deposit or withdrawal. 
    /// @dev If no shares exist or no time has passed, the accrual update is skipped.
    modifier updateAccrual() {
        if (block.timestamp > s_lastUpdate) {
            uint256 yield = (i_ausd.balanceOf(address(this)) * s_savingsRate * (block.timestamp - s_lastUpdate)) / (ONE_YEAR * PRECISION);
            if (yield > 0 && s_totalShares > 0) {
                s_accruedPerShare += (yield * PRECISION) / s_totalShares;
            }
            s_lastUpdate = block.timestamp;
        }
        _;
    }

    constructor(address ausd, address treasury) {
        i_ausd = IERC20(ausd);
        i_treasury = treasury;
        s_lastUpdate = block.timestamp;
    }

    /**
     * @notice Updates the annual percentage yield for savings depositors.
     * @dev Can only be called by the treasury address. The new rate must be no more than 20% (0.20e18).
     * @param newRate The new savings rate, scaled by 1e18.
     */
    function setSavingsRate(uint256 newRate) external {
        if (msg.sender != i_treasury) revert AurumSavings__OnlyTreasuryCanSetSavingsRate();
        if (newRate > MAX_SAVINGS_CAP) revert AurumSavings__SavingsRateTooHigh();

        emit SavingsRateUpdated(s_savingsRate, newRate);
        s_savingsRate = newRate;
    }

    /**
     * @notice Deposits AUSD into the savings contract, minting shares for the caller.
     * @dev Yield is automatically accrued before minting. Shares are calculated based on the current `accruedPerShare`.
     * @param amount The amount of AUSD to deposit. Must be greater than zero.
     */
    function deposit(uint256 amount) external updateAccrual {
        if (amount == 0) revert AurumSavings__MustBeGreaterThanZero();

        uint256 shares = (amount * PRECISION) / s_accruedPerShare;
        s_userShares[msg.sender] += shares;
        s_totalShares += shares;
        emit Deposited(msg.sender, amount, shares);

        i_ausd.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Withdraws AUSD from the savings contract by burning shares.
     * @dev Yield is automatically accrued before withdrawal. The user receives principal + accumulated yield.
     * @param shares The number of shares to burn. Must be less than or equal to the caller’s share balance.
     */
    function withdraw(uint256 shares) external updateAccrual {
        if (shares == 0 || shares > s_userShares[msg.sender]) revert AurumSavings__InsufficientShares();

        uint256 amount = (shares * s_accruedPerShare) / PRECISION;
        s_userShares[msg.sender] -= shares;
        s_totalShares -= shares;
        emit Withdrawn(msg.sender, amount, shares);

        i_ausd.safeTransfer(msg.sender, amount);
    }

    /// @notice Returns the number of shares owned by a specific user.
    function getUserShares(address user) external view returns (uint256) {
        return s_userShares[user];
    }

    /// @notice Returns the current savings rate (APY), scaled by 1e18.
    function getSavingsRate() external view returns (uint256) { 
        return s_savingsRate; 
    }

    /// @notice Returns the current accrued value per share (scaled by 1e18).
    /// @dev To compute the value of a user's deposit: `(shares * accruedPerShare) / 1e18`.
    function getAccruedPerShare() external view returns (uint256) { 
        return s_accruedPerShare; 
    }

    /// @notice Returns the total number of shares in circulation.
    function getTotalShares() external view returns (uint256) {
        return s_totalShares;
    }

    /// @notice Returns the address of the AUSD token used in this contract.
    function getAUSD() external view returns (address) { 
        return address(i_ausd); 
    }

    /// @notice Returns the treasury address that can update the savings rate.
    function getTreasury() external view returns (address) { 
        return i_treasury; 
    }
}