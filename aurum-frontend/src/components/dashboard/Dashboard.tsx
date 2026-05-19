"use client";
import { useState, useEffect, useMemo } from "react";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import aurumGoldFaucetJson from "@/abis/AurumGoldFaucet.json";
import { AUR_GOLD_ADDRESS, WETH_ADDRESS, AUR_FAUCET_ADDRESS } from "@/config/constants";
import { useTransactionContext } from "@/context/useTransactionContext";
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
  // ---------- State for Amounts & UI ----------
  const [selectedTokenIndex, setSelectedTokenIndex] = useState(0);
  const collateralTokens = useMemo(() => [
    { address: AUR_GOLD_ADDRESS, symbol: "AUR", ltv: 85},
    { address: WETH_ADDRESS, symbol: "WETH", ltv: 65}
  ], []);
  const selectedToken = collateralTokens[selectedTokenIndex];

  const { setPendingAction } = useTransactionContext();

  // ---------- Reads ----------
  const {amountCollateral, mintedAmount, healthFactor, canClaim, refetch: refetchUserData, isLoading: isUserDataLoading, isRefetching} = useUserData();
  const { isConnected } = useAccount();


  // ---------- Write Contracts For Actions That Don't Need Approval ----------
  // Write: Claim AUR faucet funds
  const { data: claimHash, isPending: isClaimPending, writeContract: claim } = useWriteContract();
  const { isLoading: isClaimConfirming, isSuccess: isClaimSuccess } = useWaitForTransactionReceipt({ hash: claimHash });


  // ---------- Effects ----------
  // Effects for updating the global pending action message
  useEffect(() => {
    if (isClaimPending || isClaimConfirming) {
      setPendingAction("Claiming AUR from faucet...");
    }
    else {
      setPendingAction(null);
    }
  }, [ isClaimPending, isClaimConfirming]);

  // Claim success effect
  useEffect(() => {
    if (isClaimSuccess) setPendingAction(null);
  }, [isClaimSuccess]);


  // ---------- Handlers ----------
  // Claim AUR from faucet handler
  const handleClaim = () => {
    claim({
      address: AUR_FAUCET_ADDRESS,
      abi: aurumGoldFaucetJson.abi,
      functionName: "claim"
    });
  };

  
  // ---------- Render UI ----------
  // Determine whether to display dashboard components
  if (!isConnected) {
    return (
      <div className="flex items-center justify-center h-96 text-gray-400">
        Please connect your wallet to view the dashboard.
      </div>
    );
  }

  return (
    <div className="max-w-7xl mx-auto p-6 space-y-8">
      {/* Header*/}
      <Header
        onRefresh={refetchUserData}
        onClaim={handleClaim}
        canClaim={canClaim}
        isClaimPending={isClaimPending}
        isClaimConfirming={isClaimConfirming}
      />
      
      {/* Stats Grid */}
      <StatsGrid
        collateral={amountCollateral ?? 0n}
        minted={mintedAmount ?? 0n}
        healthFactor={healthFactor ?? 0n}
        isLoading={isUserDataLoading}
        isRefetching={isRefetching}
      />

      {/* Collateral Selector */}
      <CollateralSelector
        tokens={collateralTokens}
        selectedIndex={selectedTokenIndex}
        onChange={setSelectedTokenIndex}
      />

      {/* Actions */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <DepositCard selectedToken={selectedToken}/>
        <RedeemCard selectedToken={selectedToken}/>
        <MintCard />
        <BurnCard />
      </div>
    </div>
  );
}