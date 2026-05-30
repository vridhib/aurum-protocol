"use client";
import { AUR_GOLD_ADDRESS, MAX_UINT256, PRECISION, WETH_ADDRESS } from "@/config/constants";
import { gql, TypedDocumentNode } from "@apollo/client";
import { useQuery } from "@apollo/client/react";
import { useProtocolData } from "./useProtocolData";
import { useMemo } from "react";


export interface UserPosition {
  id: string;
  totalCollateralUsd: bigint;
  totalAdjusted: bigint;
  totalDebt: bigint;
  healthFactor: bigint;
  aurCollateralUsd: bigint;
  wethCollateralUsd: bigint;
  actualAurDebt: bigint;
  actualWethDebt: bigint;
  rawData: any;
}

// Define the shape of the data returned by the subgraph
type ProtocolData = {
  totalUsers: number;
  cumulativeIndex: string;
};

type UserData = {
  id: string;
  collaterals: Array<{
    token: string;
    amount: string;
  }>;
  debtAllocations: Array<{
    token: string;
    normalizedDebt: string;
  }>;
  lastIndex: string;
};

type UserStats = {
  protocol: ProtocolData;
  users: UserData[];
};

// Define variables
type UserStatsVariables = Record<string, never>;

// GraphQL query
const GET_USER_STATS: TypedDocumentNode<UserStats, UserStatsVariables> = gql`
  query GetUserStats {
    protocol(id: "1") {
      totalUsers
      cumulativeIndex
    }
    users(first: 100, orderBy: lastUpdated, orderDirection: desc) {
      id
      collaterals {
        token
        amount
      }
      debtAllocations {
        token
        normalizedDebt
      }
      lastIndex
    }
  }
`;

/**
 * Fetches and calculates all user positions from the Aurum subgraph. Combines 
 * subgraph data (collaterals, debt allocations, and last index) with live 
 * on-chain prices and the current cumulative index to compute each user's total 
 * collateral, total debt, health factor, and per-token breakdowns (i.e., AUR and 
 * WETH). Optionally filters positions to those with health factors below the 
 * provided threshold (i.e., `healthFactor >= maxHealthFactor`).
 * 
 * @param {bigint} maxHealthFactor Optional upper bound for health factor. 
 * @returns {Object} An object containing:
 *  - `positions (`UserPosition[]`): computed user positions.
 *  - `loading` (`boolean`): whether the initial fetch is in progress.
 *  - `error` (`Error | undefined`): any error returned by the subgraph query.
 * 
 *  @example
 * // All positions
 * const { positions, loading, error } = useUserPositions();
 * 
 * // Only underwater positions
 * const { positions, loading, error } = useUserPositions(PRECISION);
 */
export function useUserPositions(maxHealthFactor?: bigint) {
  // Get query data and protocol data
  const { data, loading, error } = useQuery(GET_USER_STATS);
  const { pricePerAur, pricePerWeth, collaterals, cumulativeIndex = PRECISION } = useProtocolData();


  // Map token to price and LTV
  const tokenToLtvPriceMap = useMemo(() => {
    const map = new Map<string, { ltv: bigint, price: bigint }>();
    for (const c of collaterals) {
      const price = c.address.toLowerCase() === AUR_GOLD_ADDRESS.toLowerCase() ? pricePerAur : pricePerWeth;
      if (!price) continue;
      map.set(c.address.toLowerCase(), { ltv: BigInt(c.ltv), price });
    }
    return map;
  }, [collaterals, pricePerAur, pricePerWeth]);


  // Aggregate data
  const users = data?.users ?? [];
  const positions = useMemo(() => {
    const result: UserPosition[] = [];
    for (const user of users) {
      let totalCollateralUsd = 0n;
      let totalAdjusted = 0n;
      let totalNormalizedDebt = 0n;
      let aurCollateralUsd = 0n;
      let wethCollateralUsd = 0n;
      let aurDebt = 0n;
      let wethDebt = 0n;

      // Loop over user.collaterals
      for (const c of user.collaterals) {
        const info = tokenToLtvPriceMap.get(c.token.toLowerCase());
        if (!info) continue;
        const usdValue = (info.price * BigInt(c.amount)) / PRECISION;
        totalAdjusted += (usdValue * info.ltv) / 100n;
        totalCollateralUsd += usdValue;

        if (c.token.toLowerCase() === AUR_GOLD_ADDRESS.toLowerCase()) {
          if (pricePerAur) aurCollateralUsd = (BigInt(c.amount) * pricePerAur) / PRECISION;
        }
        else if (c.token.toLowerCase() === WETH_ADDRESS.toLowerCase()) {
          if (pricePerWeth) wethCollateralUsd = BigInt(c.amount) * pricePerWeth / PRECISION;
        }
      }

      // Loop over user.debtAllocations
      for (const d of user.debtAllocations) {
        const normDebt = BigInt(d.normalizedDebt);
        totalNormalizedDebt += normDebt;
        if (d.token.toLowerCase() === AUR_GOLD_ADDRESS.toLowerCase()) {
          aurDebt = normDebt;
        }
        else if (d.token.toLowerCase() === WETH_ADDRESS.toLowerCase()) {
          wethDebt = normDebt;
        }
      }

      // Compute actual debt(s)
      const totalDebt = totalNormalizedDebt * cumulativeIndex / PRECISION;
      const actualAurDebt = aurDebt * cumulativeIndex / PRECISION;
      const actualWethDebt = wethDebt * cumulativeIndex / PRECISION;

      // Compute health factor
      const healthFactor = totalDebt === 0n ? MAX_UINT256 : (totalAdjusted * PRECISION) / totalDebt;
      if (maxHealthFactor && healthFactor >= maxHealthFactor) continue;

      result.push({
        id: user.id,
        totalCollateralUsd,
        totalAdjusted,
        totalDebt,
        healthFactor,
        aurCollateralUsd,
        wethCollateralUsd,
        actualAurDebt,
        actualWethDebt,
        rawData: user
      });
    }
    return result;
  }, [users, tokenToLtvPriceMap, cumulativeIndex, pricePerAur, pricePerWeth, maxHealthFactor]);

  return { positions, loading, error };
}