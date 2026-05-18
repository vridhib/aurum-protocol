import { parseEther } from "viem";
import { useReadContract, useReadContracts } from "wagmi";
import aurumEngineJson from "@/abis/AurumEngine.json";
import { useCallback, useMemo } from "react";
import { AURUM_ENGINE_ADDRESS, AUR_GOLD_ADDRESS, WETH_ADDRESS, COLLATERAL_TOKENS } from "@/config/constants";
import { type Abi } from "viem";


interface CollateralInfo {
    priceFeed: `0x${string}`;
    volatilityFeed: `0x${string}`;
    baselineVolatility: bigint;
    baseLtv: bigint;
    minLtv: bigint;
    ltv: bigint;
    debtCeiling: bigint;
    totalNormalizedDebt: bigint;
    isActive: boolean;
    minCloseFactor: bigint;
    maxCloseFactor: bigint;
}

export interface CollateralData {
  address: `0x${string}`;
  symbol: string;
  ltv: bigint;
  baseLtv: bigint;
  minLtv: bigint;
  baselineVolatility: bigint;
  debtCeiling: bigint;
  isActive: boolean;
}

/**
 * Fetches and aggregates all protocol‑specific data from the AurumEngine contract.
 *
 * Reads the following on‑chain data:
 * - Price (in USD) per AUR token
 *
 * @returns {Object} An object containing:
 * - `pricePerAur` (`bigint | undefined`) – Price (in USD) for 1 AUR token.
 * - `refetch` (`() => void`) – Function to manually refetch all data.
 * - `isLoading` (`boolean`) – `true` while any of the reads are still loading.
 *
 * @example
 * const { pricePerAur, refetch, isLoading } = useProtocolData();
 */
export function useProtocolData(): {
    collaterals: CollateralData[];
    refetch: () => void;
    isLoading: boolean;
    pricePerAur: bigint | undefined;
    pricePerWeth: bigint | undefined;
} {
    // // Read the collateral list
    // const { data: collateralList } = useReadContract({
    //     address: AURUM_ENGINE_ADDRESS,
    //     abi: aurumEngineJson.abi,
    //     functionName: "s_collateralList",
    //     query : { enabled: true }
    // }) as { data: `0x${string}`[] | undefined };

    // // For each token, fetch CollateralInfo
    // const { data: collateralInfos } = useReadContracts({
    //     contracts: (collateralList ?? []).map((token) => ({
    //     address: AURUM_ENGINE_ADDRESS,
    //     abi: aurumEngineJson.abi as Abi,
    //     functionName: "getCollateralInfo",
    //     args: [token],
    //     })),
    //     query: { enabled: !!collateralList?.length },
    // });

    // Fetch CollateralInfo for each known token
    const { data: collateralInfos } = useReadContracts({
        contracts: COLLATERAL_TOKENS.map((token) => ({
        address: AURUM_ENGINE_ADDRESS,
        abi: aurumEngineJson.abi as Abi,
        functionName: "getCollateralInfo",
        args: [token.address],
        })),
        query: { enabled: true },
    });

    // Parse the results
    const collaterals = useMemo(() => {
        return COLLATERAL_TOKENS.map((token, i) => {
        const info = collateralInfos?.[i];
        if (!info || info.status !== "success") return null;

        const data = info.result as CollateralInfo;
        return {
            address: token.address,
            symbol: token.symbol,
            ltv: data.ltv,
            baseLtv: data.baseLtv,
            minLtv: data.minLtv,
            baselineVolatility: data.baselineVolatility,
            debtCeiling: data.debtCeiling,
            isActive: data.isActive,
        };
        }).filter((c): c is CollateralData => c !== null);
    }, [collateralInfos]);


    // const collaterals = useMemo(() => {
    //     if (!collateralList || !collateralInfos) return [];

    //     return collateralList.map((token, i) => {
    //         const info = collateralInfos[i];
    //         // Only use successful reads
    //         if (!info || info.status !== "success") return null;

    //         const data = info.result as CollateralInfo;
    //         return {
    //             address: token,
    //             symbol: token === AUR_GOLD_ADDRESS ? "AUR" : "WETH",
    //             ltv: data.ltv,
    //             baseLtv: data.baseLtv,
    //             minLtv: data.minLtv,
    //             baselineVolatility: data.baselineVolatility,
    //             debtCeiling: data.debtCeiling,
    //             isActive: data.isActive
    //         };
    //     }).filter((c): c is CollateralData => c !== null);
    // }, [collateralList, collateralInfos]);


    // Read current AUR Price
    const { data: pricePerAur, isLoading: isPricePerAurLoading, refetch: refetchPricePerAur } = useReadContract({
        address: AURUM_ENGINE_ADDRESS,
        abi: aurumEngineJson.abi,
        functionName: "getUsdValue",
        args: [AUR_GOLD_ADDRESS, parseEther("1")],
    }) as {
        data: bigint | undefined;
        refetch: () => void
        isLoading: boolean
    };

    // Read current WETH price
    const { data: pricePerWeth, isLoading: isPricePerWethLoading, refetch: refetchPricePerWeth } = useReadContract({
        address: AURUM_ENGINE_ADDRESS,
        abi: aurumEngineJson.abi,
        functionName: "getUsdValue",
        args: [WETH_ADDRESS, parseEther("1")],
    }) as {
        data: bigint | undefined;
        refetch: () => void
        isLoading: boolean
    };

    // Combined loading state (for future additions)
    const isLoading = isPricePerAurLoading || isPricePerWethLoading;

    // Combined refetch (for future additions)
    const refetch = useCallback(() => {
        refetchPricePerAur();
        refetchPricePerWeth();
    }, [refetchPricePerAur, refetchPricePerWeth]);

    // Return everything, including loading flag and possibly undefined data
    return {
        collaterals,
        refetch,
        isLoading,
        pricePerAur,
        pricePerWeth
    }
}