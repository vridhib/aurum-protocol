// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


/**
 * @title AurumUSD
 * @notice ERC20 stablecoin for the Aurum Protocol, pegged to the USD.
 * @dev    Minting and burning are restricted to the contract owner (the AurumEngine contract),
 *         which enforces overcollateralization and all other economic stability mechanisms.
 */
contract AurumUSD is ERC20Burnable, Ownable {
    error AurumUSD__MustBeMoreThanZero();
    error AurumUSD__BurnAmountExceedsBalance();
    error AurumUSD__NotZeroAddress();

    /// @dev The deployer becomes the initial owner. The ownership is transferred to the AurumEngine contract after deployment.
    constructor() ERC20("Aurum USD", "AUSD") Ownable(msg.sender) {}

    /// @notice Mints new AUSD tokens to a specified address.
    /// @return success boolean indicating whether the operation was a success.
    function mint(address _to, uint256 _amount) external onlyOwner returns(bool) {
        if (_to == address(0)) {
            revert AurumUSD__NotZeroAddress();
        }
        if (_amount <= 0) {
             revert AurumUSD__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }

    /// @notice Burns AUSD tokens from the caller's balance.
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert AurumUSD__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert AurumUSD__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    /// @notice Override ERC20Burnable.burnFrom, so only the owner can burn from another account.
    /// @dev    The engine does not use `burnFrom`. This override exists solely to prevent unauthorized burns.
    function burnFrom(address account, uint256 value) public override onlyOwner {
        super.burnFrom(account, value);
    }
}