import aurumEngineJson from "@/abis/AurumEngine.json";
import aurumGoldJson from "@/abis/AurumGold.json";
import aurumAUSDJson from "@/abis/AurumUSD.json";
import aurumGoldFaucetJson from "@/abis/AurumGoldFaucet.json";
import { useAccount, useReadContract } from "wagmi";
import { useCallback } from "react";
import { AURUM_ENGINE_ADDRESS, AURUM_AUSD_ADDRESS, AUR_GOLD_ADDRESS, AUR_FAUCET_ADDRESS } from "@/config/constants";

export function useUserData(): {
    refetch: () => void
    isLoading: boolean
    amountCollateral: bigint | undefined
    mintedAmount: bigint | undefined
    healthFactor: bigint | undefined
    lastClaimTime: bigint | undefined
    canClaim: boolean
    aurAllowance: bigint | undefined
    aurBalance: bigint | undefined
    ausdAllowance: bigint | undefined
} {
    const { address } = useAccount();

    // -------- Reads --------
    // Read: Collateral deposited
    const { data: amountCollateral, isLoading: isCollateralLoading, refetch: refetchCollateral } = useReadContract({
        address: AURUM_ENGINE_ADDRESS,
        abi: aurumEngineJson.abi,
        functionName: "getAmountCollateral",
        args: [address],
        query: { enabled: !!address },
    }) as {
         data: bigint | undefined; 
         isLoading: boolean; 
         refetch: () => void 
    };

    // Read: Minted AUSD
    const { data: mintedAmount, isLoading: isDebtLoading, refetch: refetchMinted } = useReadContract({
        address: AURUM_ENGINE_ADDRESS,
        abi: aurumEngineJson.abi,
        functionName: "getAUSDMinted",
        args: [address],
        query: { enabled: !!address },
    }) as { 
        data: bigint | undefined; 
        isLoading: boolean; 
        refetch: () => void 
    };

    // Read: Health Factor
    const { data: healthFactor, isLoading: isHealthFactorLoading, refetch: refetchHealthFactor } = useReadContract({
        address: AURUM_ENGINE_ADDRESS,
        abi: aurumEngineJson.abi,
        functionName: "getHealthFactor",
        args: [address],
        query: { enabled: !!address },
    }) as { 
        data: bigint | undefined; 
        isLoading: boolean; 
        refetch: () => void 
    };

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
    const isLoading = isCollateralLoading || isDebtLoading || isHealthFactorLoading || isLastClaimTimeLoading || isAurAllowanceLoading || isAurBalanceLoading || isAusdAllowanceLoading;

    // Combined refetch that refreshes all 6 contract calls
    const refetch = useCallback(() => {
        refetchCollateral();
        refetchMinted();
        refetchHealthFactor();
        refetchLastClaimTime();
        refetchAURAllowance();
        refetchAurBalance();
        refetchAUSDAllowance();
    }, [refetchCollateral, refetchMinted, refetchHealthFactor, refetchLastClaimTime, refetchAURAllowance, refetchAurBalance, refetchAUSDAllowance]);


    // Return everything, including loading flag and possibly undefined data
    return {
        refetch,
        isLoading,
        amountCollateral,
        mintedAmount,
        healthFactor,
        lastClaimTime,
        canClaim: lastClaimTime ? Date.now() / 1000 > Number(lastClaimTime) + 86400 : true,
        aurAllowance,
        aurBalance,
        ausdAllowance
    };
}


