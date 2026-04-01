import { Abi, decodeErrorResult } from "viem";
import aurumEngineJson from "@/abis/AurumEngine.json";
import { ONE, THRESHOLD, PRECISION } from "@/config/constants";

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
    if (mintedWei === 0n) return ONE * 100n;
    const usdValue = (collateralWei * pricePerAurWei) / ONE;
    const adjusted = (usdValue * THRESHOLD) / PRECISION;
    const projectedHealthFactor = (adjusted * ONE) / mintedWei;
    console.log("projectedHealthFactor: ", projectedHealthFactor);
    return projectedHealthFactor;
}