import aurumEngineJson from "@/abis/AurumEngine.json";
import aurumGoldJson from "@/abis/AurumGold.json";
import aurumAUSDJson from "@/abis/AurumUSD.json";
import aurumGoldFaucetJson from "@/abis/AurumGoldFaucet.json";
import { useAccount, useReadContract } from "wagmi";
import { useCallback, useEffect, useRef } from "react";
import { AURUM_ENGINE_ADDRESS, AURUM_AUSD_ADDRESS, AUR_GOLD_ADDRESS, AUR_FAUCET_ADDRESS } from "@/config/constants";


/**
 * Fetches and aggregates all user‑specific data from the AurumEngine contract.
 *
 * Reads the following on‑chain data for the currently connected wallet:
 * - Collateral deposited (AUR)
 * - AUSD minted (debt)
 * - Health factor
 * - AUR allowance for the Engine
 * - AUR wallet account balance 
 * - AUSD allowance for the Engine
 * - Last claim time from the faucet (and a computed `canClaim` flag)
 *
 * @returns {Object} An object containing:
 * - `amountCollateral` (`bigint | undefined`) – Total AUR deposited.
 * - `mintedAmount` (`bigint | undefined`) – Total AUSD minted (debt).
 * - `healthFactor` (`bigint | undefined`) – User's health factor (scaled by 1e18).
 * - `aurAllowance` (`bigint | undefined`) – AUR allowance for the Engine.
 * - `aurBalance` (`bigint | undefined`) – Current AUR wallet account balance.
 * - `ausdAllowance` (`bigint | undefined`) – AUSD allowance for the Engine.
 * - `lastClaimTime` (`bigint | undefined`) – Timestamp of the last faucet claim.
 * - `canClaim` (`boolean`) – Whether the user can claim test AUR from the faucet.
 * - `refetch` (`() => void`) – Function to manually refetch all data.
 * - `isLoading` (`boolean`) – `true` while any of the reads are still loading.
 *
 * @example
 * const { amountCollateral, refetch, isLoading } = useUserData();
 */
export function useUserData(): {
    refetch: () => void
    isLoading: boolean
    isRefetching: boolean
    amountCollateral: bigint | undefined
    mintedAmount: bigint | undefined
    healthFactor: bigint | undefined
    lastIndex: bigint | undefined
    activeCollateralTokens: string[] | undefined
    collateralAmounts: bigint[] | undefined
    debtAllocations: bigint[] | undefined
    lastClaimTime: bigint | undefined
    canClaim: boolean
    aurAllowance: bigint | undefined
    aurBalance: bigint | undefined
    ausdAllowance: bigint | undefined
} {
    const { address } = useAccount();

    // -------- Reads --------
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
            activeCollateralTokens: string[];
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

    const amountCollateral = dataToShow?.totalCollateralValueInUsd;
    const mintedAmount = dataToShow?.totalDebt;
    const healthFactor = dataToShow?.healthFactor;
    const lastIndex = dataToShow?.lastIndex;
    const activeCollateralTokens = dataToShow?.activeCollateralTokens;
    const collateralAmounts = dataToShow?.collateralAmounts;
    const debtAllocations = dataToShow?.debtAllocations;

    // Read: AUR Faucet lastClaimTime
    const { data: lastClaimTime, isLoading: isLastClaimTimeLoading, refetch: refetchLastClaimTime } = useReadContract({
        address: AUR_FAUCET_ADDRESS,
        abi: aurumGoldFaucetJson.abi,
        functionName: "lastClaimTime",
        args: [address],
        query: { enabled: !!address },
    }) as { 
        data: bigint | undefined; 
        isLoading: boolean; 
        refetch: () => void 
    };

    // Read: AUR allowance for the Engine
    const { data: aurAllowance, isLoading: isAurAllowanceLoading, refetch: refetchAURAllowance } = useReadContract({
        address: AUR_GOLD_ADDRESS,
        abi: aurumGoldJson.abi,
        functionName: "allowance",
        args: [address, AURUM_ENGINE_ADDRESS],
        query: { enabled: !!address }
    }) as { 
        data: bigint | undefined; 
        isLoading: boolean; 
        refetch: () => void 
    };

    // Read: AUR balance of the user
    const { data: aurBalance, isLoading: isAurBalanceLoading, refetch: refetchAurBalance } = useReadContract({
        address: AUR_GOLD_ADDRESS,
        abi: aurumGoldJson.abi,
        functionName: "balanceOf",
        args: [address],
        query: { enabled: !!address }
    }) as {
        data: bigint | undefined;
        isLoading: boolean;
        refetch: () => void
    };

    // Read: AUSD allowance for the Engine
    const { data: ausdAllowance, isLoading: isAusdAllowanceLoading, refetch: refetchAUSDAllowance } = useReadContract({
        address: AURUM_AUSD_ADDRESS,
        abi: aurumAUSDJson.abi,
        functionName: "allowance",
        args: [address, AURUM_ENGINE_ADDRESS],
        query: { enabled: !!address },
    }) as { 
        data: bigint | undefined; 
        isLoading: boolean; 
        refetch: () => void 
    };

    // Combined loading state that is true if any of the 6 reads are still fetching
    // const isLoading = isAccountDataLoading ||  isLastClaimTimeLoading || isAurAllowanceLoading || isAurBalanceLoading || isAusdAllowanceLoading;
    // True only when we have never loaded any account data
    const isStatsLoading = isAccountDataLoading && !dataToShow
    // Combined refetch that refreshes all 6 contract calls
    const refetch = useCallback(() => {
        refetchAccountData();
        refetchLastClaimTime();
        refetchAURAllowance();
        refetchAurBalance();
        refetchAUSDAllowance();
    }, [refetchAccountData, refetchLastClaimTime, refetchAURAllowance, refetchAurBalance, refetchAUSDAllowance]);


    // Return everything, including loading flag and possibly undefined data
    return {
        refetch,
        isLoading: isStatsLoading,
        isRefetching,
        amountCollateral,
        mintedAmount,
        healthFactor,
        lastIndex,
        activeCollateralTokens,
        collateralAmounts,
        debtAllocations,
        lastClaimTime,
        canClaim: lastClaimTime ? Date.now() / 1000 > Number(lastClaimTime) + 86400 : true,
        aurAllowance,
        aurBalance,
        ausdAllowance
    };
}