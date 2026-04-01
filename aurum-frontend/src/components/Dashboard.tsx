"use client";
import { useState, useEffect, useMemo } from "react";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { parseEther, type Abi } from "viem";
import { calculateProjectedHealthFactor } from "@/utils/helperFunctions";
import aurumEngineJson from "@/abis/AurumEngine.json";
import aurumGoldJson from "@/abis/AurumGold.json";
import aurumAUSDJson from "@/abis/AurumUSD.json";
import aurumGoldFaucetJson from "@/abis/AurumGoldFaucet.json";
import { useApproveAndExecute } from "@/hooks/useApproveAndExecute";
import { useAmountValidation } from "@/hooks/useAmountValidation";
import { useClearErrorOnInputChange, useWriteErrorHandler } from "@/hooks/useErrorHandling";
import { useUserData } from "@/hooks/useUserData";
import { useProtocolData } from "@/hooks/useProtocolData";
import { MintCard } from "./MintCard";
import { RedeemCard } from "./RedeemCard";
import { DepositCard } from "./DepositCard";
import { BurnCard } from "./BurnCard";
import { Header } from "./Header";
import { StatsGrid } from "./StatsGrid";
import { AURUM_ENGINE_ADDRESS, AURUM_AUSD_ADDRESS, AUR_GOLD_ADDRESS, AUR_FAUCET_ADDRESS, ONE } from "@/config/constants";


export default function Dashboard() {
  // ---------- State for Amounts & UI ----------
  const [depositAmount, setDepositAmount] = useState("");
  const [redeemAmount, setRedeemAmount] = useState("");
  const [mintAmount, setMintAmount] = useState("");
  const [burnAmount, setBurnAmount] = useState("");
  const [pendingAction, setPendingAction] = useState<string | null>(null);
  const [depositError, setDepositError] = useState<string | null>(null);
  const [redeemError, setRedeemError] = useState<string | null>(null);
  const [mintError, setMintError] = useState<string | null>(null);
  const [burnError, setBurnError] = useState<string | null>(null);


  // ---------- Reads ----------
  const {amountCollateral, mintedAmount, healthFactor, aurAllowance, aurBalance, ausdAllowance, canClaim, refetch: refetchUserData, isLoading: isUserDataLoading} = useUserData();
  const { pricePerAur } = useProtocolData();
  const { isConnected } = useAccount();


  // ---------- Write Contracts For Actions That Don't Need Approval ----------
  // Write: Redeem collateral (AUR)
  const { data: redeemHash, isPending: isRedeemPending, writeContract: redeem, error: redeemWriteError } = useWriteContract();
  const { isLoading: isRedeemConfirming, isSuccess: isRedeemSuccess } =
    useWaitForTransactionReceipt({ hash: redeemHash });

  // Write: Mint AUSD
  const { data: mintHash, isPending: isMintPending, writeContract: mint, error: mintWriteError } = useWriteContract();
  const { isLoading: isMintConfirming, isSuccess: isMintSuccess } =
    useWaitForTransactionReceipt({ hash: mintHash });

  // Write: Claim AUR faucet funds
  const { data: claimHash, isPending: isClaimPending, writeContract: claim } = useWriteContract();
  const { isLoading: isClaimConfirming, isSuccess: isClaimSuccess } = useWaitForTransactionReceipt({ hash: claimHash });


  // ---------- Custom Hooks For Deposit and Burn (Approval & Execution) ----------
  const { start: startDeposit, isPending: isDepositPendingHook, currentAction: depositAction, approveWriteError: approveDepositWriteError, executeWriteError: executeDepositWriteError } = useApproveAndExecute({
    approveContract: AUR_GOLD_ADDRESS,
    approveAbi: aurumGoldJson.abi as Abi,
    approveFunction: "approve",
    targetContract: AURUM_ENGINE_ADDRESS,
    targetAbi: aurumEngineJson.abi as Abi,
    targetFunction: "depositCollateral",
    allowance: aurAllowance,
    onSuccess: () => {
      // Refetch data, clear input, clear global pending action
      refetchUserData();  
      setDepositAmount("");
      setPendingAction(null);
    }
  });

  const { start: startBurn, isPending: isBurnPendingHook, currentAction: burnAction, approveWriteError: approveBurnWriteError, executeWriteError: executeBurnWriteError } = useApproveAndExecute({
    approveContract: AURUM_AUSD_ADDRESS,
    approveAbi: aurumAUSDJson.abi as Abi,
    approveFunction: "approve",
    targetContract: AURUM_ENGINE_ADDRESS,
    targetAbi: aurumEngineJson.abi as Abi,
    targetFunction: "burnAUSD",
    allowance: ausdAllowance,
    onSuccess: () => {
      // Refetch data, clear input, clear global pending action
      refetchUserData(); 
      setBurnAmount("");
      setPendingAction(null);
    }
  });


  // ---------- Derived state: Projected Health Factor ----------
  // Check if mintAmount keeps the user's health factor healthy
  const mintWouldBeHealthy = useMemo(() => {
    if (!mintAmount || parseFloat(mintAmount) <= 0) return true;
    if (amountCollateral === undefined || mintedAmount === undefined || pricePerAur === undefined) return false;

    const mintWei = parseEther(mintAmount);
    const newMinted = mintedAmount + mintWei;
    const projectedHealthFactor = calculateProjectedHealthFactor(amountCollateral, newMinted, pricePerAur);
    return projectedHealthFactor >= ONE;
  }, [mintAmount, amountCollateral, mintedAmount, pricePerAur]);

  // Check if redeemAmount keeps the user's health factor healthy
  const redeemWouldBeHealthy = useMemo(() => {
    if (!redeemAmount || parseFloat(redeemAmount) <= 0) return true;
    if (amountCollateral === undefined || mintedAmount === undefined || pricePerAur === undefined) return false;

    const redeemWei = parseEther(redeemAmount);
    const newCollateral = amountCollateral - redeemWei;
    if (mintedAmount === 0n) return true;
    const projectedHealthFactor = calculateProjectedHealthFactor(newCollateral, mintedAmount, pricePerAur);
    return projectedHealthFactor >= ONE;
  }, [redeemAmount, amountCollateral, mintedAmount, pricePerAur]);


  // ---------- Input Validation Hooks ----------
  const { isValid: isDepositAmountValid, exceeds: doesDepositExceedBalance } = useAmountValidation(depositAmount, aurBalance);
  const { isValid: isRedeemAmountValid, exceeds: doesRedeemExceedCollateral } = useAmountValidation(redeemAmount, amountCollateral);
  const { isValid: isMintAmountValid } = useAmountValidation(mintAmount);
  const { isValid: isBurnAmountValid, exceeds: doesBurnExceedMinted } = useAmountValidation(burnAmount, mintedAmount);


  // ---------- Error Handling For Writes ----------
  // If the user removed the bad/invalid number remove the error
  useClearErrorOnInputChange(setDepositError, depositAmount);
  useClearErrorOnInputChange(setRedeemError, redeemAmount);
  useClearErrorOnInputChange(setMintError, mintAmount);
  useClearErrorOnInputChange(setBurnError, burnAmount);

  // Handle post transaction write errors
  useWriteErrorHandler(approveDepositWriteError, setDepositError);
  useWriteErrorHandler(executeDepositWriteError, setDepositError);
  useWriteErrorHandler(redeemWriteError, setRedeemError);
  useWriteErrorHandler(mintWriteError, setMintError);
  useWriteErrorHandler(approveBurnWriteError, setBurnError);
  useWriteErrorHandler(executeBurnWriteError, setBurnError);


  // ---------- Effects ----------
  // Effects for updating the global pending action message
  useEffect(() => {
    if (isDepositPendingHook) {
      setPendingAction(depositAction === "approving" ? "Approving AUR deposit..." : "Depositing AUR...");
    }
    else if (isBurnPendingHook) {
      setPendingAction(burnAction === "approving" ? "Approving AUSD for burn..." : "Burning AUSD...");
    }
    else if (isRedeemPending || isRedeemConfirming) {
      setPendingAction("Redeeming AUR...");
    }
    else if (isMintPending || isMintConfirming) {
      setPendingAction("Minting AUSD...");
    }
    else if (isClaimPending || isClaimConfirming) {
      setPendingAction("Claiming AUR from faucet...");
    }
    else {
      setPendingAction(null);
    }
  }, [
    isDepositPendingHook, depositAction,
    isBurnPendingHook, burnAction,
    isRedeemPending, isRedeemConfirming,
    isMintPending, isMintConfirming,
    isClaimPending, isClaimConfirming
  ]);

  // Success effects for redeem & mint (no approval) ----
  // Refetch data after successful redeem
  useEffect(() => {
    if (isRedeemSuccess) {
      setPendingAction(null);
      refetchUserData();    
      setRedeemAmount("");
    }
  }, [isRedeemSuccess, refetchUserData]);

  // Refetch data after successful mint
  useEffect(() => {
    if (isMintSuccess) {
      setPendingAction(null);
      refetchUserData(); 
      setMintAmount("");
    }
  }, [isMintSuccess, refetchUserData]);

  // Claim success effect
  useEffect(() => {
    if (isClaimSuccess) setPendingAction(null);
  }, [isClaimSuccess]);


  // ---------- Handlers ----------
  // Deposit handler
  const handleDeposit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (!isDepositAmountValid || doesDepositExceedBalance) return;
    const amountWei = parseEther(depositAmount);
    startDeposit(amountWei);
  };

  // Redeem handler
  const handleRedeem = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (!isRedeemAmountValid || doesRedeemExceedCollateral) return;
    const amountWei = parseEther(redeemAmount);
    redeem({
      address: AURUM_ENGINE_ADDRESS,
      abi: aurumEngineJson.abi,
      functionName: "redeemCollateral",
      args: [amountWei],
    });
  };

  // Mint handler
  const handleMint = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (!isMintAmountValid) return;
    const amountWei = parseEther(mintAmount);
    mint({
      address: AURUM_ENGINE_ADDRESS,
      abi: aurumEngineJson.abi,
      functionName: "mintAUSD",
      args: [amountWei],
    });
  };

  // Burn handler
  const handleBurn = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (!isBurnAmountValid || doesBurnExceedMinted) return;
    const amountWei = parseEther(burnAmount);
    startBurn(amountWei);
  };

  // Claim AUR from faucet handler
  const handleClaim = () => {
    claim({
      address: AUR_FAUCET_ADDRESS,
      abi: aurumGoldFaucetJson.abi,
      functionName: "claim"
    });
  };


  // ---------- Button Disabled States ----------
  // Determine deposit button state
  const isDepositButtonDisabled = 
    !isDepositAmountValid || doesDepositExceedBalance || !!depositError || isDepositPendingHook;

  // Determine redeem button state
  const isRedeemButtonDisabled =
    !isRedeemAmountValid || doesRedeemExceedCollateral || !!redeemError ||
    isRedeemPending || isRedeemConfirming || !redeemWouldBeHealthy;

  // Determine mint button state
  const isMintButtonDisabled =
    !isMintAmountValid || !!mintError || isMintPending || isMintConfirming || !mintWouldBeHealthy;

  // Determine burn button state
  const isBurnButtonDisabled =
    !isBurnAmountValid || doesBurnExceedMinted || !!burnError || isBurnPendingHook;

  const isAnyTxPending = 
    isDepositPendingHook || isRedeemPending || isRedeemConfirming || isMintPending || 
    isMintConfirming || isBurnPendingHook || isClaimPending || isClaimConfirming;


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
        isAnyTxPending={isAnyTxPending}
        pendingAction={pendingAction}
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
      />

      {/* Actions */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Deposit Card */}
        <DepositCard
          depositAmount={depositAmount}
          setDepositAmount={setDepositAmount}
          onDeposit={handleDeposit}
          isPending={isDepositPendingHook}
          error={depositError}
          isDisabled={isDepositButtonDisabled}
          isValid={isDepositAmountValid}
          exceeds={doesDepositExceedBalance}
        />

        {/* Redeem Card */}
        <RedeemCard
          redeemAmount={redeemAmount}
          setRedeemAmount={setRedeemAmount}
          onRedeem={handleRedeem}
          isPending={isRedeemPending || isRedeemConfirming}
          error={redeemError}
          isDisabled={isRedeemButtonDisabled}
          willBeHealthy={redeemWouldBeHealthy}
          isValid={isRedeemAmountValid}
          exceeds={doesRedeemExceedCollateral}
        />

        {/* Mint Card */}
        <MintCard
          mintAmount={mintAmount}
          setMintAmount={setMintAmount}
          onMint={handleMint}
          isPending={isMintPending || isMintConfirming}
          error={mintError}
          isDisabled={isMintButtonDisabled}
          willBeHealthy={mintWouldBeHealthy}
          isValid={isMintAmountValid}
        />

        {/* Burn Card */}
        <BurnCard
          burnAmount={burnAmount}
          setBurnAmount={setBurnAmount}
          onBurn={handleBurn}
          isPending={isBurnPendingHook}
          error={burnError}
          isDisabled={isBurnButtonDisabled}
          isValid={isBurnAmountValid}
          exceeds={doesBurnExceedMinted}
        />
      </div>
    </div>
  );
}