import { getAddress } from "viem";

export const AURUM_ENGINE_ADDRESS = getAddress("0xEfd201CB0A2C380F039d947d023A31CB183F5AfF");
export const AUR_GOLD_ADDRESS = getAddress("0x71D1b43E1Da3F341194F43f7A3785f98b436e8f3");
export const WETH_ADDRESS = getAddress("0xdd13E55209Fd76AfE204dBda4007C227904f0a81");
export const AURUM_AUSD_ADDRESS = getAddress("0x852412CB7b7f251EaB49b8f561551F87697e2Ff9");
export const AUR_FAUCET_ADDRESS = getAddress("0x924c4F255F7Db3639d07fbF447e1E46f29A6565b");
export const AURUM_SAVINGS_ADDRESS = getAddress("0x0e05cc67bea7fbcde6f2e459d24a661d88f39ca5");

export const COLLATERAL_TOKENS = [
    { address: AUR_GOLD_ADDRESS, symbol: "AUR" },
    { address: WETH_ADDRESS, symbol: "WETH"}
];

export const PRECISION = 10n ** 18n;                   // matches engine's PRECISION (1e18)
export const THRESHOLD = 80n;                          // LIQUIDATION_THRESHOLD
export const PERCENTAGE_PRECISION = 100n;              // matches engine's LIQUIDATION_AND_FEE_PRECISION
export const MAX_UINT256 = 2n ** 256n - 1n;            // type(uint256).max
export const PRICE_FEED_PRECISION = 1_000_000_0000n;   // matches engine's ADDITIONAL_FEED_PRECISION