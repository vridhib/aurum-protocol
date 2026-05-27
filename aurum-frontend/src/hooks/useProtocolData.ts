import { parseEther } from "viem";
import { useReadContract, useReadContracts } from "wagmi";
import aurumEngineJson from "@/abis/AurumEngine.json";
import aurumUsdJson from "@/abis/AurumUSD.json";
import { useCallback, useMemo } from "react";
import { AURUM_ENGINE_ADDRESS, AUR_GOLD_ADDRESS, WETH_ADDRESS, COLLATERAL_TOKENS, AURUM_AUSD_ADDRESS, AURUM_TREASURY_ADDRESS } from "@/config/constants";
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
  minCloseFactor: bigint;
  maxCloseFactor: bigint;
}

/**
 * Fetches and aggregates all protocol‑specific data from the AurumEngine contract.
 *
 * Reads the following on‑chain data:
 * - Price (in USD) per AUR token
 * - Price (in USD) per WETH token
 * - Total collateral value in USD
 * - Total debt (amount of AUSD minted)
 * - Utilization (totalDebt / totalCollateralValueInUsd)
 * - Treasury balance of AUSD
 *
 * @returns {Object} An object containing:
 * 
 * - `collaterals (`CollateralData[]`): Array of collateral information (as defined in the `CollateralData` interface). 
 * - `refetch` (`() => void`): Function to manually refetch all data.
 * - `isLoading` (`boolean`): `true` while any of the reads are still loading.
 * - `pricePerAur` (`bigint | undefined`):  Price (in USD) for 1 AUR token.
 * - `pricePerWeth` (`bigint | undefined`):  Price (in USD) for 1 WETH token.
 * - `totalCollateralValueInUsd` (`bigint | undefined`): Protocol's total collateral value in USD.
 * - `totalDebt` (`bigint | undefined`): Protocol's total debt (AUSD supply).
 * - `utilization` (`bigint | undefined`): Protocol's utilization (totalDebt / totalCollateralValueInUsd).
 * - `treasuryBalance` (`bigint | undefined`): Protocol's total AUSD treasury balance.
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
  totalCollateralValueInUsd: bigint | undefined;
  totalDebt: bigint | undefined;
  utilization: number | undefined;
  treasuryBalance: bigint | undefined;
  cumulativeIndex: bigint | undefined;
} {
  // Fetch CollateralInfo for each known token
  const { data: collateralInfos, isLoading: isCollateralInfosLoading, refetch: refetchCollateralInfos } = useReadContracts({
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
        minCloseFactor: data.minCloseFactor,
        maxCloseFactor: data.maxCloseFactor
      };
    }).filter((c): c is CollateralData => c !== null);
  }, [collateralInfos]);

  // Read current AUR Price
  const { data: pricePerAur, isLoading: isPricePerAurLoading, refetch: refetchPricePerAur } = useReadContract({
    address: AURUM_ENGINE_ADDRESS,
    abi: aurumEngineJson.abi,
    functionName: "getUsdValue",
    args: [AUR_GOLD_ADDRESS, parseEther("1")],
  }) as {
    data: bigint | undefined
    isLoading: boolean
    refetch: () => void
  };

  // Read current WETH price
  const { data: pricePerWeth, isLoading: isPricePerWethLoading, refetch: refetchPricePerWeth } = useReadContract({
    address: AURUM_ENGINE_ADDRESS,
    abi: aurumEngineJson.abi,
    functionName: "getUsdValue",
    args: [WETH_ADDRESS, parseEther("1")],
  }) as {
    data: bigint | undefined
    isLoading: boolean
    refetch: () => void
  };

  // Read totalCollateralValueInUsd and totalDebt
  const { data: globalMetrics, isLoading: isGlobalMetricsLoading, refetch: refetchGlobalMetrics } = useReadContract({
    address: AURUM_ENGINE_ADDRESS,
    abi: aurumEngineJson.abi,
    functionName: "getGlobalMetrics",
  }) as {
    data: [bigint, bigint] | undefined
    isLoading: boolean
    refetch: () => void
  };
  const totalCollateralValueInUsd = globalMetrics?.[0];
  const totalDebt = globalMetrics?.[1];
  const utilization = (totalCollateralValueInUsd != null && totalDebt != null)
    ? (totalCollateralValueInUsd > 0n 
      ? Number(totalDebt * 10000n / totalCollateralValueInUsd) / 10000 
      : 0)
    : 0;

  // Read treasury's balance of AUSD
  const { data: treasuryBalance, isLoading: isTreasuryBalanceLoading, refetch: refetchTreasuryBalance } = useReadContract({
    address: AURUM_AUSD_ADDRESS,
    abi: aurumUsdJson.abi,
    functionName: "balanceOf",
    args: [AURUM_TREASURY_ADDRESS]
  }) as {
    data: bigint | undefined
    isLoading: boolean
    refetch: () => void
  };

  const { data: cumulativeIndex, isLoading: isCumulativeIndexLoading, refetch: refetchCumulativeIndex } = useReadContract({
    address: AURUM_ENGINE_ADDRESS,
    abi: aurumEngineJson.abi,
    functionName: "s_cumulativeIndex",
  }) as {
    data: bigint | undefined
    isLoading: boolean
    refetch: () => void
  };

  // Combined loading state
  const isLoading =
    isCollateralInfosLoading ||
    isPricePerAurLoading ||
    isPricePerWethLoading ||
    isGlobalMetricsLoading ||
    isTreasuryBalanceLoading ||
    isCumulativeIndexLoading;

  // Combined refetch
  const refetch = useCallback(() => {
    refetchCollateralInfos();
    refetchPricePerAur();
    refetchPricePerWeth();
    refetchGlobalMetrics();
    refetchTreasuryBalance();
    refetchCumulativeIndex();
  }, [refetchCollateralInfos, refetchPricePerAur, refetchPricePerWeth, refetchGlobalMetrics, refetchTreasuryBalance, refetchCumulativeIndex]);

  // Return everything, including loading flag and possibly undefined data
  return {
    collaterals,
    refetch,
    isLoading,
    pricePerAur,
    pricePerWeth,
    totalCollateralValueInUsd,
    totalDebt,
    utilization,
    treasuryBalance,
    cumulativeIndex
  }
}