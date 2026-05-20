// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";


/**
 * @title  AurumGold
 * @notice ERC20 token representing one troy ounce of physical gold held in a 
 *         custodian vault.
 * @dev    The custodian mints tokens when gold is deposited into the vault 
 *         and burns them when gold is withdrawn. Transfers can be paused by 
 *         a pauser role in case of an emergency. 
 */
contract AurumGold is ERC20, ERC20Burnable, AccessControl, Pausable {
    error AurumGold__NeedsMoreThanZero();
    error AurumGold__InsufficientBalance();

    bytes32 public constant CUSTODIAN_ROLE = keccak256("CUSTODIAN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Total troy ounces of gold backing the token supply (1 AUR = 1 troy ounce).
    uint256 private s_totalGoldOunces;

    event GoldDeposited(address indexed to, uint256 ouncesDeposited, uint256 tokensMinted);
    event GoldWithdrawn(address indexed to, uint256 ouncesWithdrawn, uint256 tokensBurned);
    event GoldLoss(address indexed reporter, uint256 ouncesLost);


    constructor() ERC20("Aurum Gold", "AUR") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CUSTODIAN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    /**
     * @notice Mint AUR tokens when physical gold is deposited into the vault.
     * @param  to Recipient of the newly minted AUR tokens.
     * @param  ounces Number of troy ounces deposited (1 AUR = 1 troy ounce).
     * @dev    Only a custodian role may mint new AUR tokens.
     */
    function mintFromGoldDeposit(address to, uint256 ounces) external onlyRole(CUSTODIAN_ROLE) {
        if (ounces == 0) revert AurumGold__NeedsMoreThanZero();
        s_totalGoldOunces += ounces;
        emit GoldDeposited(to, ounces, ounces);
        _mint(to, ounces);
    }

    /**
     * @notice Burn AUR tokens when gold is withdrawn from the vault.
     * @param  ounces Number of troy ounces to withdraw (1 AUR = 1 troy ounce).
     * @dev    Only a custodian role may burn AUR tokens.
     */
    function burnForGoldWithdrawal(uint256 ounces) external onlyRole(CUSTODIAN_ROLE) {
        if (ounces == 0) revert AurumGold__NeedsMoreThanZero();
        if (balanceOf(msg.sender) < ounces) revert AurumGold__InsufficientBalance();
        s_totalGoldOunces -= ounces;
        emit GoldWithdrawn(msg.sender, ounces, ounces);
        _burn(msg.sender, ounces);
    }

    /**
      * @notice Override ERC20Burnable.burn so only the custodian can burn tokens.
      * @param  value The amount of AUR tokens to burn in an emergency.
      * @dev    Intended for emergency use only (vault loss, quality downgrade, or 
      *         migration). Normal gold redemptions should use `burnForGoldWithdrawal` 
      *         to keep the gold-ounces counter in sync. If this burn is due to a 
      *         physical gold loss, the custodian must also call `reportGoldLoss` to
      *         keep the reserve counter in sync.
     */
    function burn(uint256 value) public override onlyRole(CUSTODIAN_ROLE) {
        super.burn(value);
    }

    /**
     * @notice Override ERC20Burnable.burnFrom so only the custodian can burn from 
     *         another account.
     * @param  account The account holding AUR tokens that need to be burned.
     * @param  value The amount of AUR tokens to burn in an emergency.
     * @dev    Intended for emergency use only (compromised accounts, sanctions 
     *         compliance, or token recovery from dead addresses). Normal gold redemptions 
     *         should use `burnForGoldWithdrawal`. If this burn is due to a physical 
     *         gold loss, the custodian must also call `reportGoldLoss` to keep the reserve
     *         counter in sync.
     */
    function burnFrom(address account, uint256 value) public override onlyRole(CUSTODIAN_ROLE) {
        super.burnFrom(account, value);
    }

    /**
     * @notice Reports a physical gold loss and adjusts the on‑chain reserve counter.
     * @param  ounces The amount of physical gold ounces stolen from the vault.
     * @dev    Only the custodian can call this. The corresponding AUR tokens must have 
     *         already been burned (via `burn`, `burnFrom`, or `burnForGoldWithdrawal`) to 
     *         keep the total supply in sync with the new counter.
     */
    function reportGoldLoss(uint256 ounces) external onlyRole(CUSTODIAN_ROLE) {
        if (ounces == 0) revert AurumGold__NeedsMoreThanZero();
        s_totalGoldOunces -= ounces;
        emit GoldLoss(msg.sender, ounces);
    }

    /// @notice Pause all token transfers.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause token transfers.
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @notice Total troy ounces of gold backing the token supply.
    function getTotalGoldOunces() external view returns (uint256) {
        return s_totalGoldOunces;
    }

    /// @notice Check that the token supply matches the total gold ounces recorded exactly.
    function isReserveBalanced() external view returns (bool) {
        return totalSupply() == s_totalGoldOunces;
    }

    /// @dev Enforce pause on all token transfers, minting, and burning.
    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        super._update(from, to, value);
    }
}