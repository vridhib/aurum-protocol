// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";


/**
 * @title AurumGold
 * @author Vridhi Brahmbhatt
 * @notice This ERC20 token, representing Gold (AUR), is used as collateral in the Aurum Protocol
 * @dev This contract represents a tokenized Real World Asset (RWA).
 *      For this project, the Owner (deployer) can mint tokens to simulate the deposit of physical gold.
 *      However, in a production setting, minting would be strictly controlled by a custodian vault.
 */
contract AurumGold is ERC20, Ownable, ERC20Burnable {
    /**
     * @notice Initializes the Aurum Gold token with a name and symbol.
     * @dev Sets the deployer as the initial owner, allowing them to mint tokens.
     */
    constructor() ERC20("Aurum Gold", "AUR") Ownable(msg.sender) {}


    /**
     * @notice Mints new AUR tokens to a specified address
     * @dev Only the contract owner (the deployer) can call this function. This is used to distribute tokens on Ethereum Sepolia. 
     *      However, in a production environment, minting would be restricted to the custodian's deposit of physical gold.
     * @param to The address to receive the minted AUR tokens
     * @param amount The amount of AUR tokens to mint
     */
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}