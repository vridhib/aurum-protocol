import aurumInterestRateModelJson from "@/abis/AurumInterestRateModel.json";
import { AURUM_INTEREST_RATE_MODEL, PRECISION } from "@/config/constants";
import { gql, TypedDocumentNode } from "@apollo/client";
import { useLazyQuery, useQuery } from "@apollo/client/react";
import { useReadContract } from "wagmi";
import { useRef, useState } from "react";
import { StatCard } from "../StatCard";
import { formatEther } from "viem";
import { formatPercent, formatStablecoin } from "@/utils/helperFunctions";


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
 * Displays the live cumulative index, last update time, borrow APY, and
 * utilization rate. A historical table of cumulative index updates is
 * shown below, sourced from the subgraph. Users can also look up the
 * accrued interest for any protocol user by entering an address. The
 * principal, current debt, and accrued interest are computed on‑demand
 * using `useLazyQuery`.
 *
 * @component
 * @param {Object} props
 * @param {bigint} props.cumulativeIndex Current cumulative index (1e18 scaled).
 * @param {number} props.utilization Utilization rate as a decimal (0‑1).
 * @returns The Interest & Index tab UI.
 */
export function InterestIndexTab({ 
  cumulativeIndex, 
  utilization,
}: { 
  cumulativeIndex: bigint, 
  utilization: number,
}) {
  // Query updates
  const { loading: indexQueryLoading, error: indexQueryError, data: indexUpdatesData } = useQuery(GET_INDEX_UPDATES);
  const resultsRef = useRef<HTMLDivElement>(null);
  const SECONDS_PER_YEAR = 31536000;

  // Read AurumInterestRateModel borrowRate
  const utilizationBigInt = utilization * Number(PRECISION);
  const { data: borrowRatePerSecond } = useReadContract({
    address: AURUM_INTEREST_RATE_MODEL,
    abi: aurumInterestRateModelJson.abi,
    functionName: "getBorrowRate",
    args: [BigInt(utilizationBigInt) ?? 0n],
    query: { enabled: !!utilization }
  });


  // User interest lookup
  const [lookupAddress, setLookupAddress] = useState("");
  const [userResult, setUserResult] = useState<{ principal: bigint, actualDebt: bigint, accruedInterest: bigint } | null>(null);
  const [lookupError, setLookupError] = useState("");
  

  const [fetchUserInterest, { loading: userLoading }] = useLazyQuery<UserInterestStats, UserInterestVariables>(GET_USER_INTEREST);

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
      const lastIndex = BigInt(data.user.lastIndex);
      const protocolIndex = BigInt(data.protocol.cumulativeIndex);
      const principal = (totalNorm * lastIndex) / PRECISION;
      const actualDebt = (totalNorm * protocolIndex) / PRECISION;
      const accruedInterest = actualDebt - principal;
      setUserResult({ principal, actualDebt, accruedInterest });
      setLookupError("");
      setTimeout(() => {
        resultsRef.current?.scrollIntoView({ behavior: "smooth", block: "start"});
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
  const cumuluativeIndexString = cumulativeIndex !== undefined ? Number(formatEther(cumulativeIndex)).toFixed(6) : "...";
  const lastUpdateTimeString = lastUpdateTime !== undefined ? new Date(lastUpdateTime * 1000).toLocaleString() : "...";
  const apyString = apy !== undefined ? `${apy.toFixed(4)}%` : "..."
  const utilizationString = utilization !== undefined ? `${(utilization * 100).toFixed(1)}%` : "...";

  return (
    <div className="space-y-12">
      {/* Snapshot Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <StatCard title="Cumulative Index" value={cumuluativeIndexString} />
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
                  <td>{Number(formatEther(BigInt(update.newIndex))).toFixed(6)}</td>
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
            <p className="text-2xl font-bold text-yellow-800 mt-1">{formatStablecoin(userResult.accruedInterest)}</p>
          </div>
        </div>
      )}
    </div>
  );
}