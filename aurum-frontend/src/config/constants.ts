import { getAddress } from "viem";

export const AURUM_ENGINE_ADDRESS = getAddress("0xF3526E0A9E149B418da4A2Bb31DEd7ca4760Cb83");
export const AUR_GOLD_ADDRESS = getAddress("0xdA33E052c5719A608734a2063404CBDF97cce794");
export const WETH_ADDRESS = getAddress("0xdd13E55209Fd76AfE204dBda4007C227904f0a81");
export const AURUM_AUSD_ADDRESS = getAddress("0x32B3A6D9cc3dbe4039e206569DeDcd080974CE67");
export const AUR_FAUCET_ADDRESS = getAddress("0xBaC86235E6FF65F3e1029B0C2BA5891BC3C9d193");
export const AURUM_SAVINGS_ADDRESS = getAddress("0xfA42D5583B57424487d6aBa17138e67CF79330f8");
export const AURUM_INTEREST_RATE_MODEL = getAddress("0x9a690e4694F721dDf69e50f7EB7f6A53b0ae2094");

export const COLLATERAL_TOKENS = [
    { address: AUR_GOLD_ADDRESS, symbol: "AUR" },
    { address: WETH_ADDRESS, symbol: "WETH"}
];

export const PRECISION = 10n ** 18n;                   // matches engine's PRECISION (1e18)
export const THRESHOLD = 80n;                          // LIQUIDATION_THRESHOLD
export const PERCENTAGE_PRECISION = 100n;              // matches engine's LIQUIDATION_AND_FEE_PRECISION
export const MAX_UINT256 = 2n ** 256n - 1n;            // type(uint256).max
export const PRICE_FEED_PRECISION = 1_000_000_0000n;   // matches engine's ADDITIONAL_FEED_PRECISION