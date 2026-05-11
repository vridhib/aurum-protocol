// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


/**
 * @title AurumGoldFaucet
 * @notice Testnet faucet that allows each address to claim `s_claimAmount` AUR tokens once.
 * @dev The owner can reset a user's claim status if needed, and can adjust the claim amount.
 */
contract AurumGoldFaucet is Ownable {
    error AurumGoldFaucet__AlreadyClaimed();
    error AurumGoldFaucet__NeedsMoreThanZero();

    IERC20 public immutable i_token;
    uint256 public s_claimAmount = 10e18;

    mapping(address => bool) public s_hasClaimed;

    event Claimed(address indexed user, uint256 amount);
    event ClaimReset(address indexed user);

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert AurumGoldFaucet__NeedsMoreThanZero();
        _;
    }

    constructor(address token) Ownable(msg.sender) {
        i_token = IERC20(token);
    }

    /// @notice Users can claim AUR tokens. Each address can only claim once.
    function claim() external {
        if ((s_hasClaimed[msg.sender])) revert AurumGoldFaucet__AlreadyClaimed();
        
        s_hasClaimed[msg.sender] = true;
        emit Claimed(msg.sender, s_claimAmount);
        i_token.transfer(msg.sender, s_claimAmount);
    }

    /// @notice The owner can reset a user's claim status, allowing them to claim again if needed.
    function resetClaimStatus(address user) external onlyOwner {
        s_hasClaimed[user] = false;
        emit ClaimReset(user);
    }

    /// @notice The owner can adjust the amount of AUR given per claim. Must be greater than zero.
    function setClaimAmount(uint256 claimAmount) external onlyOwner moreThanZero(claimAmount) {
        s_claimAmount = claimAmount;
    }

    /// @notice The owner can initially fund and replenish the faucet with AUR tokens.
    function fund(uint256 amount) external onlyOwner moreThanZero(amount) {
        i_token.transferFrom(owner(), address(this), amount);
    }

    /// @notice If needed, the owner can withdraw any remaining AUR tokens.
    function withdraw(uint256 amount) external onlyOwner moreThanZero(amount) {
        i_token.transfer(owner(), amount);
    }
}