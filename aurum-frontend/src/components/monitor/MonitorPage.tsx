"use client";
import { CollateralData, useProtocolData } from "@/hooks/useProtocolData";
import { useState } from "react";
import { RiskParametersTab } from "./RiskParametersTab";
import { PositionsTab } from "./PositionsTab";
import { InterestIndexTab } from "./InterestIndexTab";
import { PRECISION } from "@/config/constants";


/**
 * Live protocol metrics used by the Monitor tabs.
 *
 * All values come from {@link useProtocolData} on‑chain reads
 * or from the subgraph. BigInts are scaled by 1e18 unless noted 
 * otherwise.
 */
export interface ProtocolMetrics {
  totalCollateralValueInUsd: bigint;
  totalDebt: bigint;
  utilization: number;
  cumulativeIndex: bigint;
  treasuryAusdBalance: bigint;
  pricePerAur: bigint;
  pricePerWeth: bigint;
  collaterals: CollateralData[];
}

/**
 * Monitor page for the Aurum frontend.
 *
 * Fetches and displays aggregated protocol statistics and user positions from the 
 * subgraph (via Apollo Client). It shows three tabs:
 *    1. Positions: stat cards (total collateral value, total debt, utilization, 
 *       cumulative index, treasury AUSD balance, and total number of users) and a 
 *       table showing all user positions with their collateral, debt, and health 
 *       factor (with more granular tooltip breakdowns). Health factors are computed 
 *       using the current AUR and WETH price (from `useProtocolData`) and are 
 *       color‑coded.
 *    2. Risk Parameters: the current per-collateral risk parameters.
 *    3. Index & Interest: stat cards (cumulative index, utilization, last update, and 
 *       borrow APY), a table showing all cumulative index updates, as well as a search 
 *       functionality to query per-user interest accrual (with principal, actual debt, 
 *       and accrued data cards) and projected interest (with pre-defined and custom 
 *       intervals).
 * 
 * @component
 * @returns The monitor page with a tabbed interface for viewing positions, risk parameters,
 *          and index/interest stats.
 */
export default function MonitorPage() {
  // Tabs and protocol data
  const TABS = ["Positions", "Risk Parameters", "Interest & Index"];
  const [activeTab, setActiveTab] = useState(0);
  const protocolData = useProtocolData();

  // Build the metrics object
  const metrics: ProtocolMetrics = {
    totalCollateralValueInUsd: protocolData.totalCollateralValueInUsd ?? 0n,
    totalDebt: protocolData.totalDebt ?? 0n,
    utilization: protocolData.utilization ?? 0,
    cumulativeIndex: protocolData.cumulativeIndex ?? PRECISION,
    treasuryAusdBalance: protocolData.treasuryBalance ?? 0n,
    pricePerAur: protocolData.pricePerAur ?? 0n,
    pricePerWeth: protocolData.pricePerWeth ?? 0n,
    collaterals: protocolData.collaterals,
  };


  // Render UI
  if (protocolData.isLoading) {
    return (
      <div className="flex justify-center items-center h-64">
        <div className="text-gray-400">Loading protocol data...</div>
      </div>
    );
  }

  return (
    <div className="max-w-7xl mx-auto p-6 space-y-12">
      <h1 className="text-3xl font-bold text-yellow-800">Protocol Monitor</h1>
      <div className="flex gap-2 border-b border-yellow-800/20">
        {TABS.map((tab, i) => (
          <button
            key={tab}
            onClick={() => setActiveTab(i)}
            className={`px-4 py-2 rounded-t-lg text-sm transition ${i === activeTab
              ? "bg-[#F2E0C8] text-yellow-900 font-semibold border border-b-0 border-yellow-800/20"
              : "text-gray-600 hover:text-yellow-800 hover:bg-yellow-50"
              }`}
          >
            {tab}
          </button>
        ))}
      </div>
      <div className="space-y-12">
        {activeTab === 0 && <PositionsTab metrics={metrics} />}
        {activeTab === 1 && <RiskParametersTab collaterals={metrics.collaterals} />}
        {activeTab === 2 && <InterestIndexTab cumulativeIndex={metrics.cumulativeIndex} utilization={metrics.utilization} />}
      </div>
    </div>
  );
}