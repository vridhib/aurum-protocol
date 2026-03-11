// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


/**
 * @title AurumUSD
 * @author Vridhi Brahmbhatt
 * Collateral: Exogenous (Gold)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 * 
 * This is the contract meant to be governed by AurumEngine. This contract is just the ERC20 implementation of the Aurum Stablecoin System.
 */
contract AurumUSD is ERC20Burnable, Ownable {
    error AurumUSD__MustBeMoreThanZero();
    error AurumUSD__BurnAmountExceedsBalance();
    error AurumUSD__NotZeroAddress();


    /**
     * @dev Sets the deployer as the initial owner. Ownership is expected to be transferred to the AurumEngine upon deployment.
     */
    constructor() ERC20("Aurum USD", "AUSD") Ownable(msg.sender) {}


    /**
     * @notice Burns AUSD tokens from the caller's balance.
     * @param _amount The amount of AUSD to burn.
     */
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


    /**
     * @notice Mints new AUSD tokens to a specified address
     * @param _to The address to receive the minted AUSD
     * @param _amount The amount of AUSD to mint
     * @return A boolean indicating success
     */
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
}