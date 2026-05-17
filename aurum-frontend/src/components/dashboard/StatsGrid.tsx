import { formatEther } from "viem";
import { StatCard } from "./StatCard";
import { formatHealthFactorForDisplay } from "@/utils/helperFunctions";


/**
 * Stats grid section for the Aurum Protocol frontend. 
 * @param collateral User's collateral amount.
 * @param minted User's minted AUSD amount.
 * @param healthFactor User's health factor.
 * @param isLoading Indicates whether the user's data is loading. 
 * @returns A stats grid UI displaying a user's collateral amount, minted amount, and health factor.
 */
export function StatsGrid({ 
    collateral, 
    minted, 
    healthFactor, 
    isLoading,
    isRefetching 
}: { 
    collateral: bigint,
    minted: bigint, 
    healthFactor: bigint, 
    isLoading: boolean, 
    isRefetching: boolean 
}) {
    // Only show loading skeleton when data is never loaded
    const showLoading = isLoading && !isRefetching;


    return (
        <div className="relative grid grid-cols-1 md:grid-cols-3 gap-6">
            {/* Optional: tiny "Updating" indicator */}
            {isRefetching && (
                <span className="absolute -top-5 right-0 text-xs text-gray-400 animate-pulse">
                    Updating…
                </span>
            )}

            <StatCard
                title="Deposited Collateral Value"
                value={showLoading ? "Loading..." : `$${formatEther(collateral || 0n)}`}
            />
            <StatCard
                title="AUSD Minted"
                value={showLoading ? "Loading..." : `${formatEther(minted || 0n)} AUSD`}
            />
            <StatCard
                title="Health Factor"
                value={showLoading ? "Loading..." : formatHealthFactorForDisplay(healthFactor)}
            />
        </div>
    );
}