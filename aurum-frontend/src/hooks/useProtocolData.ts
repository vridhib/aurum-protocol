import { parseEther } from "viem";
import { useReadContract } from "wagmi";
import aurumEngineJson from "@/abis/AurumEngine.json";
import { useCallback } from "react";
import { AURUM_ENGINE_ADDRESS } from "@/config/constants";

export function useProtocolData(): {
    refetch: () => void
    isLoading: boolean
    pricePerAur: bigint | undefined
} {
    // Read: Current AUR Price
    const { data: pricePerAur, isLoading: isPricePerAurLoading, refetch: refetchPricePerAur } = useReadContract({
        address: AURUM_ENGINE_ADDRESS,
        abi: aurumEngineJson.abi,
        functionName: "getUsdValue",
        args: [parseEther("1")],
    }) as {
        data: bigint | undefined;
        refetch: () => void
        isLoading: boolean
    };

    // Combined loading state (for future additions)
    const isLoading = isPricePerAurLoading;

    // Combined refetch (for future additions)
    const refetch = useCallback(() => {
        refetchPricePerAur();
    }, [refetchPricePerAur]);

    // Return everything, including loading flag and possibly undefined data
    return {
        refetch,
        isLoading,
        pricePerAur
    }
}