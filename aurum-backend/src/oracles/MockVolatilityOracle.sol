// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IVolatilityOracle} from "./IVolatilityOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockVolatilityOracle is IVolatilityOracle, Ownable {
    uint256 private s_volatility;

    constructor(uint256 initialVolatility) Ownable(msg.sender) {
        s_volatility = initialVolatility;
    }

    function setVolatility(uint256 newVolatility) external onlyOwner {
        s_volatility = newVolatility;
    }

    function getAnnualizedVolatility() external view override returns (uint256) {
        return s_volatility;
    }
}