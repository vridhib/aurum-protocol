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
import { CollateralSelector } from "../ui/CollateralSelector";
import { formatEther } from "viem";
import { formatHealthFactorForDisplay, formatStablecoin } from "@/utils/helperFunctions";
import { StatCard } from "../ui/StatCard";


/**
 * Dashboard page for the Aurum frontend.
 *
 * Uses individual {@link StatCard} components to assemble a stats grid to showcase 
 * the user's collateral value in USD, total debt, health factor. Provides dedicated
 * forms to deposit {@link DepositCard} and redeem {@link RedeemCard} collateral as 
 * well as mint {@link MintCard} and burn {@link BurnCard} AUSD stablecoins.
 *
 * @component
 * @returns The rendered Dashboard page.
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
  // Only show loading skeleton when data is never loaded
  const showLoading = isUserDataLoading && !isRefetching;

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
      {/* Header */}
      <Header onRefresh={refetchUserData} />

      {/* Stats Overview */}
      <div className="relative grid grid-cols-1 md:grid-cols-3 gap-6">
        <StatCard
          title="Deposited Collateral Value"
          value={showLoading ? "Loading..." : `$${formatEther(totalCollateralValueInUsd || 0n)}`}
        />
        <StatCard
          title="AUSD Minted"
          value={showLoading ? "Loading..." : `${formatStablecoin(totalDebt || 0n)} AUSD`}
        />
        <StatCard
          title="Health Factor"
          value={showLoading ? "Loading..." : formatHealthFactorForDisplay(healthFactor)}
        />
      </div>

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