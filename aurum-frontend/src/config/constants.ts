import { getAddress } from "viem";

export const AURUM_ENGINE_ADDRESS = getAddress("0x471c1d6f2c8d9883d051f296429bcadb4eb4dc11");
export const AUR_GOLD_ADDRESS = getAddress("0x7769F56edC2a1882a51cec1d3c96F31482b5A241");
export const AURUM_AUSD_ADDRESS = getAddress("0x3828120d97913be56ded3522a9d0926cd79d9fb2");
export const AUR_FAUCET_ADDRESS = getAddress("0x25067322310e834498b1638423383b3e5603dd30");

export const ONE = 10n ** 18n;       // 1e18
export const THRESHOLD = 80n;        // LIQUIDATION_THRESHOLD
export const PRECISION = 100n;       // LIQUIDATION_PRECISION