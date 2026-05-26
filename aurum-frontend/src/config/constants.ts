import { getAddress } from "viem";


export const AURUM_ENGINE_ADDRESS = getAddress("0xfc243b4040002d4a9fc3ec412af04eaa2f0da525");
export const AUR_GOLD_ADDRESS = getAddress("0xa07ad08f298c7e8a2b432f7d25b86fe7e101902b");
export const WETH_ADDRESS = getAddress("0xdd13E55209Fd76AfE204dBda4007C227904f0a81");
export const AURUM_AUSD_ADDRESS = getAddress("0xde76cf5c4f6d0b6687f0ebf460cdf9468744c8c7");
export const AUR_FAUCET_ADDRESS = getAddress("0x3ff3edfc64d8be337c051492824aa8ce823cfad1");
export const AURUM_SAVINGS_ADDRESS = getAddress("0xafc5ec7e1a35b85f91f540284ddb253832528180");
export const AURUM_INTEREST_RATE_MODEL = getAddress("0x3d719281d30b4a1e6a7053f62e18477612f730df");
export const AURUM_TREASURY_ADDRESS = getAddress("0x8d95b5282b7f94ce5d4dc5bdc946d8ef180f4297");

export const COLLATERAL_TOKENS = [
    { address: AUR_GOLD_ADDRESS, symbol: "AUR" },
    { address: WETH_ADDRESS, symbol: "WETH"}
];

export const PRECISION = 10n ** 18n;                   // matches engine's PRECISION (1e18)
export const THRESHOLD = 80n;                          // LIQUIDATION_THRESHOLD
export const PERCENTAGE_PRECISION = 100n;              // matches engine's LIQUIDATION_AND_FEE_PRECISION
export const MAX_UINT256 = 2n ** 256n - 1n;            // type(uint256).max
export const PRICE_FEED_PRECISION = 1_000_000_0000n;   // matches engine's ADDITIONAL_FEED_PRECISION