import { AUR_GOLD_ADDRESS, MAX_UINT256, PRECISION, WETH_ADDRESS } from "@/config/constants";
import { formatHealthFactorForDisplay, formatPercent, formatStablecoin, formatUsd, getHealthColor, shortenAddress } from "@/utils/helperFunctions";
import { CopyIcon } from "lucide-react";
import { useMemo, useState } from "react";
import { TooltipPortal } from "./ToolTipPortal";
import { gql, TypedDocumentNode } from "@apollo/client";
import { useQuery } from "@apollo/client/react";
import { StatCard } from "../StatCard";
import { formatEther } from "viem";
import { ProtocolMetrics } from "./MonitorPage";


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
 * Positions tab for the Protocol Monitor.
 *
 * The top stat cards show total collateral, total debt, utilization,
 * cumulative index, treasury balance, and total users. Below them, a table
 * of all protocol users lists each user’s total collateral value (in USD), 
 * total debt, and health factor, with per‑collateral breakdowns available 
 * on hover.
 *
 * All on‑chain metrics are received via the `metrics` prop (built from
 * `useProtocolData`). The user list and total user count are fetched
 * from the subgraph using Apollo’s `useQuery`.
 *
 * @component
 * @param {Object} props
 * @param {ProtocolMetrics} props.metrics Live protocol metrics.
 * @returns The Positions tab UI.
 */
export function PositionsTab({ metrics }: { metrics: ProtocolMetrics }) {
  const { loading: userQueryLoading, error: userQueryError, data: userStatsData } = useQuery(GET_USER_STATS);
  const totalUsers = userStatsData?.protocol?.totalUsers ?? 0;
  const users = userStatsData?.users ?? [];
  const [copiedAddress, setCopiedAddress] = useState<string | null>(null);


  // Map token to price and LTV
  const tokenToLtvPriceMap = useMemo(() => {
    const map = new Map<string, { ltv: bigint, price: bigint }>();
    for (const c of metrics.collaterals) {
      const price = c.address.toLowerCase() === AUR_GOLD_ADDRESS.toLowerCase() ? metrics.pricePerAur : metrics.pricePerWeth;
      if (!price) continue;
      map.set(c.address.toLowerCase(), { ltv: BigInt(c.ltv), price });
    }
    return map;
  }, [metrics.collaterals, metrics.pricePerAur, metrics.pricePerWeth]);


  // Copy user address
  const copyAddress = async (address: string) => {
    await navigator.clipboard.writeText(address);
    setCopiedAddress(address);
    setTimeout(() => setCopiedAddress(null), 2000);
  };


  // Render UI
  if (userQueryError) {
    return (
      <div className="flex justify-center items-center h-64">
        <div className="text-red-500">Error loading data: {userQueryError.message}</div>
      </div>
    );
  }

  return (
    <>
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <StatCard title="Total Collateral Value (USD)" value={formatUsd(metrics.totalCollateralValueInUsd || 0n)} />
        <StatCard title="Total Debt (AUSD)" value={`${formatStablecoin(metrics.totalDebt || 0n)}`} />
        <StatCard title="Utilization" value={`${formatPercent(metrics.utilization || 0)}`} />
        <StatCard title="Cumulative Index" value={Number(formatEther(metrics.cumulativeIndex || BigInt(1e18))).toFixed(6)} />
        <StatCard title="Treasury Balance (AUSD)" value={`${formatStablecoin(metrics.treasuryAusdBalance || 0n)}`} />
        <StatCard title="Total Users" value={totalUsers.toString()} />
      </div>
      <div className="table-wrapper">
        <table className="gold-table">
          <thead>
            <tr>
              <th>User</th>
              <th>Total Collateral Value (USD)</th>
              <th>Total Debt</th>
              <th>Health Factor</th>
            </tr>
          </thead>
          <tbody>
            {users.map((user: any) => {
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
                if (info === undefined) continue;
                const usdValue = (info.price * BigInt(c.amount)) / PRECISION;
                totalAdjusted += (usdValue * info.ltv) / 100n;
                totalCollateralUsd += usdValue;

                if (c.token.toLowerCase() === AUR_GOLD_ADDRESS.toLowerCase()) {
                  if (metrics.pricePerAur === undefined) continue;
                  aurCollateralUsd = (BigInt(c.amount) * metrics.pricePerAur) / PRECISION;
                }
                else if (c.token.toLowerCase() === WETH_ADDRESS.toLowerCase()) {
                  if (metrics.pricePerWeth === undefined) continue;
                  wethCollateralUsd = BigInt(c.amount) * metrics.pricePerWeth / PRECISION;
                }
              }

              // Loop over user.debtAllocations
              for (const debt of user.debtAllocations) {
                totalNormalizedDebt += BigInt(debt.normalizedDebt);
                if (debt.token.toLowerCase() === AUR_GOLD_ADDRESS.toLowerCase()) {
                  aurDebt = BigInt(debt.normalizedDebt);
                }
                else if (debt.token.toLowerCase() === WETH_ADDRESS.toLowerCase()) {
                  wethDebt = BigInt(debt.normalizedDebt);
                }
              }

              // Compute actual debt(s)
              const totalDebt = totalNormalizedDebt * metrics.cumulativeIndex / PRECISION;
              const actualAurDebt = aurDebt * metrics.cumulativeIndex / PRECISION;
              const actualWethDebt = wethDebt * metrics.cumulativeIndex / PRECISION;

              // Compute health factor
              const healthFactor = totalDebt === 0n ? MAX_UINT256 : (totalAdjusted * PRECISION) / totalDebt;
              const healthFactorColor = getHealthColor(healthFactor);

              // Tooltip contents (defined per user)
              const collateralTooltip = (
                <div className="text-left space-y-1">
                  <div className="flex justify-between gap-4">
                    <span>AUR</span><span className="font-mono">{formatUsd(aurCollateralUsd)}</span>
                  </div>
                  <div className="flex justify-between gap-4">
                    <span>WETH</span><span className="font-mono">{formatUsd(wethCollateralUsd)}</span>
                  </div>
                </div>
              );

              const debtTooltip = (
                <div className="text-left space-y-1">
                  <div className="flex justify-between gap-4">
                    <span>AUR</span><span className="font-mono">{formatStablecoin(actualAurDebt)}</span>
                  </div>
                  <div className="flex justify-between gap-4">
                    <span>WETH</span><span className="font-mono">{formatStablecoin(actualWethDebt)}</span>
                  </div>
                </div>
              );

              return (
                <tr key={user.id} className="hover:bg-yellow-50/50 transition">
                  {/* User Address with Copy Button */}
                  <td>
                    <div className="flex items-center gap-1">
                      <TooltipPortal content={<span className="font-mono text-xs">{user.id}</span>}>
                        <span className="cursor-help border-b border-dotted border-yellow-800/30">
                          {shortenAddress(user.id)}
                        </span>
                      </TooltipPortal>
                      <button
                        onClick={(e) => { e.stopPropagation(); copyAddress(user.id); }}
                        className="text-gray-400 hover:text-yellow-700 transition text-xs"
                        title="Copy address"
                      >
                        <CopyIcon className="w-3.5 h-3.5" />
                      </button>
                      {copiedAddress === user.id && (
                        <span className="text-green-600 text-xs ml-1 animate-pulse">Copied!</span>
                      )}
                    </div>
                  </td>

                  {/* Total Collateral with Breakdown Tooltip */}
                  <td>
                    <TooltipPortal content={collateralTooltip}>
                      <span className="cursor-help border-b border-dotted border-yellow-800/30">
                        {formatUsd(totalCollateralUsd)}
                      </span>
                    </TooltipPortal>
                  </td>

                  {/* Total Debt with Breakdown Tooltip */}
                  <td>
                    <TooltipPortal content={debtTooltip}>
                      <span className="cursor-help border-b border-dotted border-yellow-800/30">
                        {formatStablecoin(totalDebt)}
                      </span>
                    </TooltipPortal>
                  </td>

                  {/* Health Factor with Explanation Tooltip */}
                  <td className={healthFactorColor}>
                    <TooltipPortal content="Health Factor = Adjusted Collateral / Total Debt. Above 1.00 is safe.">
                      <span className="cursor-help border-b border-dotted border-yellow-800/30">
                        {formatHealthFactorForDisplay(healthFactor)}
                      </span>
                    </TooltipPortal>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </>
  );
}