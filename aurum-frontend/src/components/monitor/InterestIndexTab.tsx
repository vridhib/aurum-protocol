import aurumInterestRateModelJson from "@/abis/AurumInterestRateModel.json";
import { AURUM_INTEREST_RATE_MODEL, PRECISION } from "@/config/constants";
import { gql, TypedDocumentNode } from "@apollo/client";
import { useLazyQuery, useQuery } from "@apollo/client/react";
import { useReadContract } from "wagmi";
import { useRef, useState } from "react";
import { StatCard } from "../ui/StatCard";
import { formatEther } from "viem";
import { formatPercent, formatStablecoin } from "@/utils/helperFunctions";
import { TooltipPortal } from "../ui/TooltipPortal";


// Define the shape of the data returned by the subgraph
type IndexUpdate = {
  id: string;
  newIndex: string;
  utilization: string;
  timestamp: string;
};

type IndexUpdatesResponse = {
  cumulativeIndexUpdates: IndexUpdate[];
};

type UserInterestStats = {
  user: {
    lastIndex: string;
    debtAllocations: { normalizedDebt: string }[];
  };
  protocol: {
    cumulativeIndex: string;
  };
};

// Define variables
type UserInterestVariables = { userId: string };
type IndexUpdateVariables = Record<string, never>;

// GraphQL query
const GET_USER_INTEREST: TypedDocumentNode<UserInterestStats, UserInterestVariables> = gql`
  query GetUserInterest($userId: ID!) {
    user(id: $userId) {
      lastIndex
      debtAllocations {
        normalizedDebt
      }
    }
    protocol(id: "1") {
      cumulativeIndex
    }
  }
`;

const GET_INDEX_UPDATES: TypedDocumentNode<IndexUpdatesResponse, IndexUpdateVariables> = gql`
  query GetCumulativeIndexUpdates {
    cumulativeIndexUpdates(first: 100, orderBy: timestamp, orderDirection: desc) {
      id
      newIndex
      utilization
      timestamp
    }
  }
`

/**
 * Interest & Index tab for the Protocol Monitor.
 *
 * Provides a comprehensive interest and index overview of the protocol 
 * and individual users. The page displays:
 *  - Individual stat cards displaying the live cumulative index, last 
 *    update time, borrow APY, and utilization rate. 
 *  - A historical table of cumulative index updates, sourced from the 
 * subgraph. 
 *  - A lookup feature where users can look up the accrued interest and 
 *    projected interest for any protocol user by entering an address. 
 *    For the specified user, the following will be displayed:
 *     - Individual stat cards showing the user's principal, actual debt,
 *       and accrued interest (with the percentage shown in a tooltip).
 *     - The projected interest accrual in 30 days, 60 days, and 365 days, 
 *       as well as an optional custom interval input option (with the 
 *       percentage shown in a tooltip).
 * 
 * The principal, current debt, and accrued interest are computed on‑demand 
 * using `useLazyQuery`.
 *
 * @component
 * @param {Object} props
 * @param {bigint} props.cumulativeIndex Current cumulative index (1e18 scaled).
 * @param {number} props.utilization Utilization rate as a decimal (0‑1).
 * @returns The Interest & Index tab for the Monitor page.
 */
export function InterestIndexTab({ cumulativeIndex, utilization }: { cumulativeIndex: bigint, utilization: number }) {
  // Query updates
  const { loading: indexQueryLoading, error: indexQueryError, data: indexUpdatesData } = useQuery(GET_INDEX_UPDATES);
  const [fetchUserInterest, { loading: userLoading }] = useLazyQuery<UserInterestStats, UserInterestVariables>(GET_USER_INTEREST);
  const resultsRef = useRef<HTMLDivElement>(null);

  // User interest lookup
  const [lookupAddress, setLookupAddress] = useState("");
  const [userResult, setUserResult] = useState<{ principal: bigint, actualDebt: bigint, accruedInterest: bigint } | null>(null);
  const [lookupError, setLookupError] = useState("");
  const [totalNormalizedDebt, setTotalNormalizedDebt] = useState<bigint>(0n);
  const [customDays, setCustomDays] = useState<number>(0);

  // Constants
  const SECONDS_PER_YEAR = 31536000;
  const INTERVALS = [30, 90, 365];


  // Read AurumInterestRateModel borrowRate
  const utilizationBigInt = utilization * Number(PRECISION);
  const { data: borrowRatePerSecond } = useReadContract({
    address: AURUM_INTEREST_RATE_MODEL,
    abi: aurumInterestRateModelJson.abi,
    functionName: "getBorrowRate",
    args: [BigInt(utilizationBigInt) ?? 0n],
    query: { enabled: !!utilization }
  }) as { data: bigint | undefined };


  // Interest compute and formatting helpers
  const computeProjectedInterest = (days: number) => {
    if (!userResult || totalNormalizedDebt <= 0n || !borrowRatePerSecond) return null;

    const seconds = BigInt(days) * 24n * 60n * 60n;
    const futureIndex = (cumulativeIndex * (PRECISION + borrowRatePerSecond * seconds)) / PRECISION;
    const futureDebt = (totalNormalizedDebt * futureIndex) / PRECISION;
    const projectedInterest = futureDebt - userResult.principal;

    return projectedInterest;
  }

  const formatPercentOfPrincipal = (amount: bigint, principal: bigint): string => (
    `${((Number(formatEther(amount)) / Number(formatEther(principal))) * 100).toFixed(4)}% of principal`
  );


  // Handle user lookup
  const handleLookup = async () => {
    if (!lookupAddress.trim()) return;
    try {
      const result = await fetchUserInterest({
        variables: { userId: lookupAddress.toLowerCase().trim() },
      });
      const data = result.data;
      if (!data?.user || !data?.protocol) {
        setLookupError("User not found in subgraph.");
        setUserResult(null);
        return;
      }
      // Compute interest
      const totalNorm = data.user.debtAllocations.reduce<bigint>((sum, d) => sum + BigInt(d.normalizedDebt), 0n);
      setTotalNormalizedDebt(totalNorm);
      const lastIndex = BigInt(data.user.lastIndex);
      const protocolIndex = BigInt(data.protocol.cumulativeIndex);
      const principal = (totalNorm * lastIndex) / PRECISION;
      const actualDebt = (totalNorm * protocolIndex) / PRECISION;
      const accruedInterest = actualDebt - principal;
      setUserResult({ principal, actualDebt, accruedInterest });
      setLookupError("");
      setTimeout(() => {
        resultsRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
      }, 100);
    }
    catch (err: unknown) {
      setLookupError(err instanceof Error ? err.message : "Unknown error");
      setUserResult(null);
    }
  };


  // Derived values
  const apy = borrowRatePerSecond 
    ? (Number(borrowRatePerSecond) * SECONDS_PER_YEAR) / 1e18 * 100 
    : undefined;
  const lastUpdateTime = indexUpdatesData?.cumulativeIndexUpdates[0]?.timestamp
    ? Number(indexUpdatesData.cumulativeIndexUpdates[0].timestamp) 
    : undefined;
  const indexUpdates: IndexUpdate[] = indexUpdatesData?.cumulativeIndexUpdates ?? [];

  // For display
  const cumulativeIndexString = cumulativeIndex !== undefined ? formatStablecoin(cumulativeIndex, 6) : "...";
  const lastUpdateTimeString = lastUpdateTime !== undefined ? new Date(lastUpdateTime * 1000).toLocaleString() : "...";
  const apyString = apy !== undefined ? `${apy.toFixed(4)}%` : "...";
  const utilizationString = utilization !== undefined ? formatPercent(utilization) : "...";

  const accruedInterestPercentage = userResult 
    ? formatPercentOfPrincipal(userResult.accruedInterest, userResult.principal) 
    : undefined;
  const customProjectedInterest = customDays > 0 ? computeProjectedInterest(customDays) : null;

  return (
    <div className="space-y-12">
      {/* Snapshot Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <StatCard title="Cumulative Index" value={cumulativeIndexString} />
        <StatCard title="Last Updated" value={lastUpdateTimeString} />
        <StatCard title="Borrow APY" value={apyString} />
        <StatCard title="Utilization" value={utilizationString} />
      </div>

      {/* Historical Index Updates Table */}
      <h2 className="section-heading">Cumulative Index History</h2>
      {indexQueryLoading ? (
        <p className="text-gray-600">Loading historical data...</p>
      ) : indexQueryError ? (
        <p className="text-red-500">Error: {indexQueryError.message}</p>
      ) : (
        <div className="table-wrapper">
          <table className="gold-table">
            <thead>
              <tr>
                <th>Timestamp</th>
                <th>New Index</th>
                <th>Utilization</th>
              </tr>
            </thead>
            <tbody>
              {indexUpdates.map((update) => (
                <tr key={update.id}>
                  <td>{new Date(Number(update.timestamp) * 1000).toLocaleString()}</td>
                  <td>{(formatStablecoin(BigInt(update.newIndex), 6))}</td>
                  <td>{formatPercent(Number(update.utilization) / 1e18)}</td>
                </tr>
              ))}
              {indexUpdates.length === 0 && (
                <tr>
                  <td colSpan={3} className="text-center text-gray-500">No index updates yet.</td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}

      {/* User Interest Lookup */}
      <h2 className="section-heading">User Accrued Interest</h2>
      <div className="flex gap-2 max-w-md">
        <input
          type="text"
          placeholder="0xabcd..."
          value={lookupAddress}
          onChange={(e) => setLookupAddress(e.target.value)}
          className="form-input flex-1"
        />
        <button
          onClick={handleLookup}
          disabled={userLoading || !lookupAddress.trim()}
          className="bg-yellow-600 hover:bg-yellow-800 text-white font-bold py-3 px-4 rounded-lg transition disabled:opacity-50 disabled:cursor-not-allowed w-auto"
        >
          {userLoading ? "Loading..." : "Lookup"}
        </button>
      </div>
      {lookupError && (<p className="text-red-500 text-sm mt-2">{lookupError}</p>)}

      {userResult && (
        <div ref={resultsRef} className="grid grid-cols-1 md:grid-cols-3 gap-4 mt-4">
          <div className="gold-card p-4 text-center">
            <p className="text-yellow-900 text-xs uppercase tracker-wider font-semibold">Principal</p>
            <p className="text-2xl font-bold text-yellow-800 mt-1">{formatStablecoin(userResult.principal)}</p>
          </div>
          <div className="gold-card p-4 text-center">
            <p className="text-yellow-900 text-xs uppercase tracker-wider font-semibold">Current Debt</p>
            <p className="text-2xl font-bold text-yellow-800 mt-1">{formatStablecoin(userResult.actualDebt)}</p>
          </div>
          <div className="gold-card p-4 text-center">
            <p className="text-yellow-900 text-xs uppercase tracker-wider font-semibold">Accrued Interest</p>
            <TooltipPortal content={accruedInterestPercentage} >
              <p className="text-2xl font-bold text-yellow-800 mt-1">{formatStablecoin(userResult.accruedInterest)}</p>
            </TooltipPortal>
          </div>
        </div>
      )}

      {/* Interest Projection Card */}
      {userResult && totalNormalizedDebt > 0n && borrowRatePerSecond !== undefined && (
        <div>
          <div className="gold-card p-6 space-y-4 mt-6">
            <h3 className="text-lg font-bold text-yellow-900">Projected Interest</h3>
            <div className="grid grid-cols-3 gap-4 text-center">
              {INTERVALS.map(days => {
                const projectedInterest = computeProjectedInterest(days);

                if (projectedInterest === null) return null;
                return (
                  <div key={days}>
                    <p className="text-sm uppercase tracking-wider text-yellow-900/70 font-semibold">
                      {days === 365 ? "1 Year" : `${days} Days`}
                    </p>
                    <TooltipPortal content={formatPercentOfPrincipal(projectedInterest, userResult.principal)} >
                      <p className="text-2xl font-bold text-yellow-800 mt-1">
                        {formatStablecoin(projectedInterest)}
                      </p>
                    </TooltipPortal>
                    <p className="text-xs text-gray-500 mt-0.5">in additional interest</p>
                  </div>
                );

              })}
            </div>
            {/* Custom Interval Input */}
            <div className="gold-border pt-4 mt-4">
              <label className="text-sm uppercase tracking-wider text-yellow-900/70 font-semibold mr-2">Custom (days)</label>
              <input
                type="number"
                placeholder="e.g. 180"
                value={customDays || ""}
                onChange={e => setCustomDays(Number(e.target.value) || 0)}
                className="form-input w-28 text-sm inline-block"
                min={1}
              />
            </div>
            {/* Live Custom Projection */}
            {customDays > 0 && customProjectedInterest !== null && (
              <div className="text-center pt-2">
                <p className="text-sm uppercase tracking-wider text-yellow-900/70 font-semibold">Custom ({customDays} Days)</p>
                <TooltipPortal content={formatPercentOfPrincipal(customProjectedInterest, userResult.principal)} >
                  <p className="text-2xl font-bold text-yellow-800 mt-1">{formatStablecoin(customProjectedInterest)}</p>
                </TooltipPortal>
                <p className="text-xs text-gray-500 mt-0.5">in additional interest</p>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}