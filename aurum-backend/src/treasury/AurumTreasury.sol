// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title AurumTreasury
 * @notice Collects protocol fees (interest and liquidation bonuses) and allows the owner
 *         to distribute yield to the AurumSavings contract.
 * @dev The treasury receives AUSD directly minted by the AurumEngine. Only the engine
 *      can increase reserves and only the owner can distribute yield.
 */
contract AurumTreasury is Ownable {
    error AurumTreasury__InsufficientReserves();
    error AurumTreasury__SavingsAlreadySet();

    using SafeERC20 for IERC20;

    IERC20 private immutable i_ausd;
    address private s_aurumSavings;

    event YieldDistributed(uint256 amount);
    event SavingsAddressSet(address savings);

    /// @dev Sets the AUSD token and the AurumSavings contract addresses.
    constructor(address ausd) Ownable(msg.sender) {
        i_ausd = IERC20(ausd);
    }

    function setSavingsAddress(address savings) external onlyOwner {
        if (s_aurumSavings != address(0)) revert AurumTreasury__SavingsAlreadySet();
        s_aurumSavings = savings;
        emit SavingsAddressSet(savings);
    }

    /**
     * @notice Sends a portion of reserves to the AurumSavings contract for yield distribution.
     * @dev Can only be called by the contract owner. The amount must not exceed the treasury's AUSD balance.
     * @param amount The amount of AUSD to transfer to the savings contract.
     */
    function distributeYield(uint256 amount) external onlyOwner {
        if (amount == 0 || amount > i_ausd.balanceOf(address(this))) {
            revert AurumTreasury__InsufficientReserves();
        }
        emit YieldDistributed(amount);
        i_ausd.safeTransfer(s_aurumSavings, amount);
    }

    /// @notice Returns the address of the savings contract
    function getSavings() external view returns (address) {
        return s_aurumSavings;
    }
}