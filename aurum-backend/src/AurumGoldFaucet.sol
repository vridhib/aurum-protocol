// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


/**
 * @title AurumGoldFaucet
 * @author Vridhi Brahmbhatt
 * @notice This provides a testnet faucet for AUR tokens, allowing users to claim a fixed amount once per day.
 * @dev Users can call `claim()` to receive `claimAmount` AUR tokens, subject to a cooldown period.
 *      The contract owner can adjust the claim amount and cooldown, and can fund the faucet with AUR tokens.
 *      This faucet is intended for Ethereum Sepolia testnet use only.
 */
contract AurumGoldFaucet is Ownable {
    error AurumGoldFaucet__CooldownPeriodHasNotPassed();
    error AurumGoldFaucet__NeedsMoreThanZero();

    IERC20 public token;
    uint256 public claimAmount = 10 ether;              // Tokens per claim
    uint256 public cooldown = 1 days;                   // Wait time between claims

    mapping(address => uint256) public lastClaimTime;

    event Claimed(address indexed user, uint256 amount);


    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert AurumGoldFaucet__NeedsMoreThanZero();
        _;
    }


    /// @param _token The address of the AUR token contract
    constructor(address _token) Ownable(msg.sender) {
        token = IERC20(_token);
    }


    /**
     * @notice Allows a user to claim AUR tokens once per cooldown period
     * @dev Reverts if the user has already claimed within the cooldown period
     */
    function claim() external {
        if ((lastClaimTime[msg.sender] != 0) && (block.timestamp < lastClaimTime[msg.sender] + cooldown)) {
            revert AurumGoldFaucet__CooldownPeriodHasNotPassed();
        }

        lastClaimTime[msg.sender] = block.timestamp;
        token.transfer(msg.sender, claimAmount);
        emit Claimed(msg.sender, claimAmount);
    }


    /// @notice The owner can adjust the claim amount if needed
    function setClaimAmount(uint256 _claimAmount) external onlyOwner moreThanZero(_claimAmount) {
        claimAmount = _claimAmount;
    }


    /// @notice The owner can adjust the cooldown period between claims
    function setCooldown(uint256 _cooldown) external onlyOwner moreThanZero(_cooldown){
        cooldown = _cooldown;
    }


    /// @notice If needed, the owner can withdraw any remaining AUR tokens
    function withdraw(uint256 amount) external onlyOwner moreThanZero(amount) {
        token.transfer(owner(), amount);
    }


    /// @notice The owner funds the faucet with AUR tokens. The owner must first approve this contract to spend tokens.
    function fund(uint256 amount) external onlyOwner moreThanZero(amount) {
        token.transferFrom(owner(), address(this), amount);
    }
}