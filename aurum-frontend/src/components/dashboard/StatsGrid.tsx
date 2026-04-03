import { formatEther } from "viem";
import { StatCard } from "./StatCard";
import { formatHealthFactorForDisplay } from "@/utils/helperFunctions";

export function StatsGrid({ collateral, minted, healthFactor, isLoading }: { collateral: bigint, minted: bigint, healthFactor: bigint, isLoading: boolean }) {
    return (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <StatCard
                title="Collateral Deposited"
                value={isLoading ? "Loading..." : `${formatEther(collateral || 0n)} AUR`}
            />
            <StatCard
                title="AUSD Minted"
                value={isLoading ? "Loading..." : `${formatEther(minted || 0n)} AUSD`}
            />
            <StatCard
                title="Health Factor"
                value={isLoading ? "Loading..." : formatHealthFactorForDisplay(healthFactor)}
            />
        </div>
    );
}




