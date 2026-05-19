import { useEffect, useRef } from "react";
import { useAccount, useReadContract } from "wagmi";
import aurumEngineJson from "@/abis/AurumEngine.json";
import { AURUM_ENGINE_ADDRESS} from "@/config/constants";


/**
 * Aggregates user‑specific on‑chain data from the AurumEngine contract.
 *
 * Uses a single call to {@link AurumEngine.getUserAccountData} to fetch the
 * user’s total collateral value, total debt, health factor, last cumulative
 * index, and per‑collateral breakdowns. The result is cached (staleTime = 2 min)
 * and previous values are preserved during background refetches, so the
 * stats never disappear.
 *
 * @returns {Object} An object containing:
 * - `refetch`                   – Function to manually refetch the account data.
 * - `isLoading`                 – `true` only when the account data has never been loaded.
 * - `isRefetching`              – `true` when a background refresh is in progress.
 * - `totalCollateralValueInUsd` – Total USD value of all deposited collateral.
 * - `totalDebt`                 – Total AUSD minted + accrued interest.
 * - `healthFactor`              – Current user health factor (scaled by 1e18).
 * - `lastIndex`                 – Last cumulative index at which the user minted or repaid.
 * - `activeCollateralTokens`    – Addresses of tokens with active deposits.
 * - `collateralAmounts`         – Raw token amounts deposited per collateral.
 * - `debtAllocations`           – Normalized debt allocated to each collateral.
 *
 * @example
 * const { totalCollateralValueInUsd, totalDebt, healthFactor, refetch, isLoading } = useUserData();
 */
export function useUserData(): {
    refetch: () => void
    isLoading: boolean
    isRefetching: boolean
    totalCollateralValueInUsd: bigint | undefined
    totalDebt: bigint | undefined
    healthFactor: bigint | undefined
    lastIndex: bigint | undefined
    activeCollateralTokens: `0x${string}`[] | undefined
    collateralAmounts: bigint[] | undefined
    debtAllocations: bigint[] | undefined
} {
    const { address } = useAccount();

    // Read AurumEngine's getUserAccountData to parse UserAccountData struct 
    const { data: accountData, isLoading: isAccountDataLoading, refetch: refetchAccountData } = useReadContract({
        address: AURUM_ENGINE_ADDRESS,
        abi: aurumEngineJson.abi,
        functionName: "getUserAccountData",
        args: [address],
        query: {
             enabled: !!address,
             staleTime: 2 * 60 * 1000
        },
    }) as {
        data: {
            totalCollateralValueInUsd: bigint;
            totalDebt: bigint;
            healthFactor: bigint;
            lastIndex: bigint;
            activeCollateralTokens: `0x${string}`[];
            collateralAmounts: bigint[];
            debtAllocations: bigint[];
        } | undefined;
        isLoading: boolean;
        refetch: () => void;
    };

    const lastAccountData = useRef(accountData);
    useEffect(() => {
        if (accountData) lastAccountData.current = accountData;
    }, [accountData]);

    const dataToShow = accountData ?? lastAccountData.current;
    const isRefetching = isAccountDataLoading && !!lastAccountData.current;

    const totalCollateralValueInUsd = dataToShow?.totalCollateralValueInUsd;
    const totalDebt = dataToShow?.totalDebt;
    const healthFactor = dataToShow?.healthFactor;
    const lastIndex = dataToShow?.lastIndex;
    const activeCollateralTokens = dataToShow?.activeCollateralTokens;
    const collateralAmounts = dataToShow?.collateralAmounts;
    const debtAllocations = dataToShow?.debtAllocations;

    // Combined loading state that is true only when never loaded any account data
    const isStatsLoading = isAccountDataLoading && !dataToShow

    // Return everything, including loading flag and possibly undefined data
    return {
        refetch: refetchAccountData,
        isLoading: isStatsLoading,
        isRefetching,
        totalCollateralValueInUsd,
        totalDebt,
        healthFactor,
        lastIndex,
        activeCollateralTokens,
        collateralAmounts,
        debtAllocations,
    };
}