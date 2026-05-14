// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";


/**
 * @title AurumGold
 * @notice ERC20 token representing one troy ounce of physical gold held in a custodian vault.
 * @dev The custodian mints tokens when gold is deposited and burns them when gold is withdraw. 
 *      Transfers can be paused by the pauser role in case of an emergency. 
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


    constructor() ERC20("Aurum Gold", "AUR") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CUSTODIAN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    /**
     * @notice Mint AUR tokens when physical gold is deposited into the vault.
     * @param to Recipient of the newly minted AUR tokens.
     * @param ounces Number of troy ounces deposited (1 AUR = 1 troy ounce).
     */
    function mintFromGoldDeposit(address to, uint256 ounces) external onlyRole(CUSTODIAN_ROLE) {
        if (ounces == 0) revert AurumGold__NeedsMoreThanZero();
        s_totalGoldOunces += ounces;
        emit GoldDeposited(to, ounces, ounces);
        _mint(to, ounces);
    }

    /**
     * @notice Burn AUR tokens when gold is withdrawn from the vault.
     * @param ounces Number of troy ounces to withdraw (1 AUR = 1 troy ounce).
     */
    function burnForGoldWithdrawal(uint256 ounces) external onlyRole(CUSTODIAN_ROLE) {
        if (ounces == 0) revert AurumGold__NeedsMoreThanZero();
        if (balanceOf(msg.sender) < ounces) revert AurumGold__InsufficientBalance();
        s_totalGoldOunces -= ounces;
        emit GoldWithdrawn(msg.sender, ounces, ounces);
        _burn(msg.sender, ounces);
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