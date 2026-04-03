import { Abi, decodeErrorResult, formatEther } from "viem";
import aurumEngineJson from "@/abis/AurumEngine.json";
import { ONE, THRESHOLD, PRECISION, MAX_UINT256 } from "@/config/constants";


// Gets user friendly error messages
export function getUserFriendlyErrorMessage(error: unknown): string {
    if (error instanceof Error && error.message.includes("User rejected")) {
        return "Transaction was rejected in your wallet.";
    }

    try {
        const cause = (error as any).cause;
        if (cause?.data) {
            const decoded = decodeErrorResult({
                abi: aurumEngineJson.abi as Abi,
                data: cause.data,
            });
            switch (decoded.errorName) {
                case "AurumEngine__ExceedsMaxSupply":
                    return "Cannot mint more than the maximum supply of AUSD.";
                default:
                    return `Contract error: ${decoded.errorName}`;
            }
        }
    } catch (e) { }
    return error instanceof Error ? error.message : "An unknown error occurred.";
}


/**
 * Computes the health factor after a proposed change.
 * Formula: (collateral * price * THRESHOLD) / (minted * PRECISION * ONE)
 * Returns a value where >= ONE means healthy.
 */
export function calculateProjectedHealthFactor(collateralWei: bigint, mintedWei: bigint, pricePerAurWei: bigint): bigint {
    // If debt is 0, return max uint256 value
    if (mintedWei === 0n) return MAX_UINT256;
    // Otherwise, calculate health factor in wei
    const usdValue = (collateralWei * pricePerAurWei) / ONE;
    const adjusted = (usdValue * THRESHOLD) / PRECISION;
    const projectedHealthFactor = (adjusted * ONE) / mintedWei;
    return projectedHealthFactor;
}


export function formatHealthFactorForDisplay(healthFactorWei: bigint | undefined): string {
    // If undefined, return loading string
    if (healthFactorWei == undefined) return "Loading...";
    // When debt == 0, the AurumEngine contract's _healthFactor returns type(uint256).max
    // If debt is 0, return infinity string
    const MAX_UINT256 = 2n ** 256n - 1n;
    if (healthFactorWei === MAX_UINT256) return "∞";
    // Otherwise return formatted number health string
    const healthFactorNumber = Number(formatEther(healthFactorWei));
    return healthFactorNumber.toFixed(2);
}


export function getHealthColor(healthWei: bigint | undefined): string {
    // If undefined, return gray
    if (healthWei === undefined) return "text-gray-400";
    // Otherwise return green, yellow, and red based on health factor range
    // Convert to number (wei -> decimal)
    const health = Number(formatEther(healthWei));
    if (health >= 1.5) return "text-green-400";
    if (health >= 1.0) return "text-yellow-400";
    return "text-red-400";
}


export function shortenAddress(address: string) {
    if (!address) return "";
    return `${address.slice(0, 6)}...${address.slice(-4)}`;
}