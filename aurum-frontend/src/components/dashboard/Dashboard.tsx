"use client";
import { useState, useMemo } from "react";
import { useAccount } from "wagmi";
import { AUR_GOLD_ADDRESS, WETH_ADDRESS } from "@/config/constants";
import { useUserData } from "@/hooks/useUserData";
import { MintCard } from "./MintCard";
import { RedeemCard } from "./RedeemCard";
import { DepositCard } from "./DepositCard";
import { BurnCard } from "./BurnCard";
import { Header } from "./Header";
import { StatsGrid } from "./StatsGrid";
import { CollateralSelector } from "./CollateralSelector";


/**
 * Main dashboard component for the Aurum Protocol frontend.
 *
 * Displays the user's collateral value in USD, total debt, health factor, 
 * and provides forms for depositing/redeeming AUR/WETH and minting/burning
 * AUSD stablecoins.
 *
 * @component
 * @returns The rendered dashboard UI.
 */
export default function Dashboard() {
  // State for Amounts & UI 
  const [selectedTokenIndex, setSelectedTokenIndex] = useState(0);
  const collateralTokens = useMemo(() => [
    { address: AUR_GOLD_ADDRESS, symbol: "AUR", ltv: 85 },
    { address: WETH_ADDRESS, symbol: "WETH", ltv: 65 }
  ], []);
  const selectedToken = collateralTokens[selectedTokenIndex];

  // Reads 
  const { totalCollateralValueInUsd, totalDebt, healthFactor, refetch: refetchUserData, isLoading: isUserDataLoading, isRefetching } = useUserData();
  const { isConnected } = useAccount();


  // Render UI 
  // Determine whether to display dashboard components
  if (!isConnected) {
    return (
      <div className="flex items-center justify-center h-96 text-gray-400">
        Please connect your wallet to view the dashboard.
      </div>
    );
  }

  return (
    <div className="max-w-7xl mx-auto p-6 space-y-12">
      {/* Header*/}
      <Header onRefresh={refetchUserData} />

      {/* Stats Grid */}
      <StatsGrid
        collateral={totalCollateralValueInUsd ?? 0n}
        minted={totalDebt ?? 0n}
        healthFactor={healthFactor ?? 0n}
        isLoading={isUserDataLoading}
        isRefetching={isRefetching}
      />

      <div className="space-y-6">
        {/* Collateral Selector Buttons */}
        <CollateralSelector
          tokens={collateralTokens}
          selectedIndex={selectedTokenIndex}
          onChange={setSelectedTokenIndex}
        />

        {/* Actions */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <DepositCard selectedToken={selectedToken} />
          <RedeemCard selectedToken={selectedToken} />
          <MintCard />
          <BurnCard />
        </div>
      </div>
    </div>
  );
}