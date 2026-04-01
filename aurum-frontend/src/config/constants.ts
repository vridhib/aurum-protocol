import { getAddress } from "viem";

export const AURUM_ENGINE_ADDRESS = getAddress("0x57dd5e001cD51689cDA9F38Ca49D841923cD5012");
export const AUR_GOLD_ADDRESS = getAddress("0x7769F56edC2a1882a51cec1d3c96F31482b5A241");
export const AURUM_AUSD_ADDRESS = getAddress("0x9C707127B1c8ab786E23474BCa253948Bae1B452");
export const AUR_FAUCET_ADDRESS = getAddress("0x25067322310e834498b1638423383b3e5603dd30");

export const ONE = 10n ** 18n;       // 1e18
export const THRESHOLD = 80n;        // LIQUIDATION_THRESHOLD
export const PRECISION = 100n;       // LIQUIDATION_PRECISION