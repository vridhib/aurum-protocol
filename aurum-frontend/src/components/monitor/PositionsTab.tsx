import { formatPercent, formatStablecoin, formatUsd } from "@/utils/helperFunctions";
import { StatCard } from "../StatCard";
import { formatEther } from "viem";
import { ProtocolMetrics } from "./MonitorPage";
import { useUserPositions } from "@/hooks/useUserPositions";
import { UserPositionRow } from "./UserPositionRow";


/**
 * Positions tab for the Protocol Monitor.
 *
 * Provides an overview of the protocol's key metrics and a view of all user 
 * positions. At the top of the page are individual stat cards displaying the
 * total collateral value (in USD), total debt, utilization, cumulative index, 
 * treasury balance, and total users. Below the stat cards is a table, showing 
 * all protocol users, that lists each user’s total collateral value (in USD), 
 * total debt, and health factor, with per‑collateral breakdowns available on 
 * hover.
 *
 * All on‑chain metrics are received via the `metrics` prop (built from
 * `useProtocolData`). The table reuses the shared {@link useUserPositions} 
 * hook and {@link UserPositionRow} component.
 *
 * @component
 * @param {Object} props
 * @param {ProtocolMetrics} props.metrics Live protocol metrics.
 * @returns The Positions tab for the Monitor page.
 */
export function PositionsTab({ metrics }: { metrics: ProtocolMetrics }) {
  const { positions, loading, error } = useUserPositions();
  const totalUsers = positions?.length;

  // Format values
  const formattedTotalCollateralValue = formatUsd(metrics.totalCollateralValueInUsd || 0n);
  const formattedTotalDebt = formatStablecoin(metrics.totalDebt || 0n);
  const formattedUtilization = formatPercent(metrics.utilization || 0)
  const formattedCumulativeIndex = Number(formatEther(metrics.cumulativeIndex || BigInt(1e18))).toFixed(6);
  const formattedTreasuryBalance = formatStablecoin(metrics.treasuryAusdBalance || 0n);

  // Render UI
  if (loading) return <p>Loading user positions...</p>;
  if (error) {
    return (
      <div className="flex justify-center items-center h-64">
        <div className="text-red-600">Error loading data: {error.message}</div>
      </div>
    );
  }

  return (
    <>
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <StatCard title="Total Collateral Value (USD)" value={formattedTotalCollateralValue} />
        <StatCard title="Total Debt (AUSD)" value={formattedTotalDebt} />
        <StatCard title="Utilization" value={formattedUtilization} />
        <StatCard title="Cumulative Index" value={formattedCumulativeIndex} />
        <StatCard title="Treasury Balance (AUSD)" value={formattedTreasuryBalance} />
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
            {positions.map(p => (
              <UserPositionRow key={p.id} position={p} />
            ))}
            {positions.length === 0 && (
              <tr>
                <td colSpan={5} className="text-center text-gray-500">No users found.</td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </>
  );
}