import { Abi, decodeErrorResult, formatEther } from "viem";
import aurumEngineJson from "@/abis/AurumEngine.json";
import { PRECISION, THRESHOLD, PERCENTAGE_PRECISION, MAX_UINT256 } from "@/config/constants";


/**
 * Converts an unknown error object into a user‑friendly error message.
 * Handles wallet rejections and known contract revert reasons.
 * @param error The error thrown by a contract write or transaction.
 * @returns A human‑readable error message.
 */
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
 * Formula: (collateral * price * THRESHOLD) / (minted * PRECISION * PRECISION)
 * @returns a value where >= PRECISION means healthy.
 */
export function calculateProjectedHealthFactor(collateralWei: bigint, mintedWei: bigint, pricePerAurWei: bigint): bigint {
    // If debt is 0, return max uint256 value
    if (mintedWei === 0n) return MAX_UINT256;
    // Otherwise, calculate health factor in wei
    //const usdValue = (collateralWei * pricePerAurWei) / PRECISION;
    const usdValue = collateralWei;
    const adjusted = (usdValue * THRESHOLD) / PERCENTAGE_PRECISION;
    const projectedHealthFactor = (adjusted * PRECISION) / mintedWei;
    return projectedHealthFactor;
}


// Formats the health factor for display purposes
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


// Formats AUSD value (18-decimal bigint) to a fixed-precision string
export function formatStablecoin(value: bigint, decimals = 4): string {
  const divisor = 10n ** (18n - BigInt(decimals));
  const rounded = (value + divisor / 2n) / divisor;  // round half up
  const str = rounded.toString();
  if (decimals === 0) return str;

  const padded = str.padStart(decimals + 1, "0");
  const intPart = padded.slice(0, padded.length - decimals);
  const fracPart = padded.slice(padded.length - decimals);
  return `${intPart}.${fracPart}`;
}


// Format ether value (1e18) to USD with two decimals
export function formatUsd(value: bigint, decimals = 2): string {
  const num = Number(formatEther(value));
  return `$${num.toLocaleString(undefined, { minimumFractionDigits: decimals, maximumFractionDigits: decimals })}`;
}


// Format a number as a percentage string
export function formatPercent(value: number, decimals = 1): string {
  return `${(value * 100).toFixed(decimals)}%`;
}


// Format ether value (1e18) to a percentage string
export function formatEtherAsPercent(value: bigint): string {
  return `${Number(formatEther(value)) * 100}%`;
}


// Gets the health color class according to the health factor range
export function getHealthColor(healthWei: bigint | undefined): string {
    // If undefined, return gray
    if (healthWei === undefined) return "text-gray-400";
    // Otherwise return green, yellow, and red based on health factor range
    // Convert to number (wei -> decimal)
    const health = Number(formatEther(healthWei));
    if (health >= 1.5) return "text-green-600";
    if (health >= 1.0) return "text-yellow-600";
    return "text-red-600";
}


// Shortens the address 
export function shortenAddress(address: string) {
    if (!address) return "";
    return `${address.slice(0, 6)}...${address.slice(-4)}`;
}