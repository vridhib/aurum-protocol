"use client";
import { useState, useEffect, useMemo, useCallback } from "react";
import { parseEther, type Abi } from "viem";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import aurumAUSDJson from "@/abis/AurumUSD.json";
import aurumSavingsJson from "@/abis/AurumSavings.json";
import { AURUM_AUSD_ADDRESS, AURUM_SAVINGS_ADDRESS } from "@/config/constants";
import { useTransactionContext } from "@/context/useTransactionContext";
import { useApproveAndExecute } from "@/hooks/useApproveAndExecute";
import { useAmountValidation } from "@/hooks/useAmountValidation";
import { formatStablecoin, getUserFriendlyErrorMessage } from "@/utils/helperFunctions";
import { StatCard } from "../StatCard";
import { GoldHero } from "../GoldHero";


/**
 * Savings page for the Aurum frontend.
 * 
 * Self‑contained savings card that displays the current savings rate (APY), the
 * user’s share balance, and deposited AUSD using {@link StatCard} components. 
 * Renders individual forms that allow the user to deposit AUSD into the AurumSavings 
 * contract to earn yield, and to withdraw shares back to AUSD. 
 * 
 * @component
 * @returns The rendered savings page with current user values and forms.
 */
export default function Savings() {
  const { address: userAddress } = useAccount();
  const { setPendingAction } = useTransactionContext();


  // Local state 
  const [depositAmount, setDepositAmount] = useState("");
  const [withdrawShares, setWithdrawShares] = useState("");
  const [depositError, setDepositError] = useState<string | null>(null);
  const [withdrawError, setWithdrawError] = useState<string | null>(null);


  // Read user shares
  const { data: userShares, refetch: refetchUserShares } = useReadContract({
    address: AURUM_SAVINGS_ADDRESS,
    abi: aurumSavingsJson.abi,
    functionName: "getUserShares",
    args: [userAddress],
    query: { enabled: !!userAddress },
  }) as { data: bigint | undefined; refetch: () => void };

  // Read accruedPerShare
  const { data: accruedPerShare, refetch: refetchAccrued } = useReadContract({
    address: AURUM_SAVINGS_ADDRESS,
    abi: aurumSavingsJson.abi,
    functionName: "getAccruedPerShare",
    query: { enabled: true },
  }) as { data: bigint | undefined; refetch: () => void };

  // Read savingsRate
  const { data: savingsRate, refetch: refetchRate } = useReadContract({
    address: AURUM_SAVINGS_ADDRESS,
    abi: aurumSavingsJson.abi,
    functionName: "getSavingsRate",
    query: { enabled: true },
  }) as { data: bigint | undefined; refetch: () => void };

  // Read user's AUSD balance
  const { data: ausdBalance } = useReadContract({
    address: AURUM_AUSD_ADDRESS,
    abi: aurumAUSDJson.abi,
    functionName: "balanceOf",
    args: [userAddress],
    query: { enabled: !!userAddress },
  }) as { data: bigint | undefined };

  // Read user's AUSD allowance
  const { data: ausdAllowance } = useReadContract({
    address: AURUM_AUSD_ADDRESS,
    abi: aurumAUSDJson.abi,
    functionName: "allowance",
    args: [userAddress, AURUM_SAVINGS_ADDRESS],
    query: { enabled: !!userAddress },
  }) as { data: bigint | undefined };


  // Calculate derived values
  const shareValue = useMemo(() => {
    if (!userShares || !accruedPerShare) return undefined;
    return (userShares * accruedPerShare) / parseEther("1"); // in AUSD (18 decimals)
  }, [userShares, accruedPerShare]);

  const apy = useMemo(() => {
    if (!savingsRate) return undefined;
    return (Number(savingsRate) * 100) / 1e18; // percentage
  }, [savingsRate]);


  // Validate user input
  const { isValid: isDepositValid, exceeds: depositExceedsBalance } = useAmountValidation(depositAmount, ausdBalance);
  const { isValid: isWithdrawValid, exceeds: withdrawExceedsShares } = useAmountValidation(withdrawShares, userShares);


  // Deposit flow (approve AUSD + deposit AUSD)
  const onSuccess = useCallback(() => {
    setDepositAmount("");
    setPendingAction(null);
    refetchUserShares();
    refetchAccrued();
    refetchRate();
  }, [refetchUserShares, refetchAccrued, refetchRate, setPendingAction]);

  const { start: startDeposit, isPending: isDepositPending, approveWriteError, executeWriteError } =
    useApproveAndExecute({
      approveContract: AURUM_AUSD_ADDRESS,
      approveAbi: aurumAUSDJson.abi as Abi,
      approveFunction: "approve",
      targetContract: AURUM_SAVINGS_ADDRESS,
      targetAbi: aurumSavingsJson.abi as Abi,
      targetFunction: "deposit",
      allowance: ausdAllowance,
      onSuccess
    });


  // Write: withdraw shares  
  const { data: withdrawHash, isPending: isWithdrawPending, writeContract: withdraw, error: withdrawWriteError } =
    useWriteContract();
  const { isLoading: isWithdrawConfirming, isSuccess: isWithdrawSuccess } =
    useWaitForTransactionReceipt({ hash: withdrawHash });

  // Withdraw handler
  const handleWithdraw = (e: React.FormEvent) => {
    e.preventDefault();
    if (!isWithdrawValid || withdrawExceedsShares) return;
    setPendingAction("Withdrawing from savings...");
    withdraw({
      address: AURUM_SAVINGS_ADDRESS,
      abi: aurumSavingsJson.abi,
      functionName: "withdraw",
      args: [parseEther(withdrawShares)], // shares are 18 decimals
    });
  };

  // Deposit handler
  const handleDepositSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!isDepositValid || depositExceedsBalance) return;
    setPendingAction("Depositing into savings...");
    startDeposit(parseEther(depositAmount));
  };


  // Format deposit write errors to friendly error message
  useEffect(() => {
    const writeError = approveWriteError || executeWriteError;
    if (writeError) setDepositError(getUserFriendlyErrorMessage(writeError));
  }, [approveWriteError, executeWriteError]);

  useEffect(() => {
    if (withdrawWriteError) {
      setWithdrawError(getUserFriendlyErrorMessage(withdrawWriteError));
      setPendingAction(null);
    }
  }, [withdrawWriteError, setPendingAction]);

  // Clear errors on input change
  useEffect(() => { setDepositError(null); }, [depositAmount]);
  useEffect(() => { setWithdrawError(null); }, [withdrawShares]);

  // Clear global banner on (deposit or withdraw) write errors
  useEffect(() => {
    if (approveWriteError || executeWriteError || withdrawWriteError) {
      setPendingAction(null);
    }
  }, [approveWriteError, executeWriteError, withdrawWriteError, setPendingAction]);

  // On withdraw success, update 
  useEffect(() => {
    if (isWithdrawSuccess) {
      setPendingAction(null);
      setWithdrawShares("");
      refetchUserShares();
      refetchAccrued();
      refetchRate();
    }
  }, [isWithdrawSuccess]);


  // Button states
  const isDepositDisabled =
    !isDepositValid || depositExceedsBalance || !!depositError || isDepositPending;
  const isWithdrawDisabled =
    !isWithdrawValid || withdrawExceedsShares || !!withdrawError || isWithdrawPending || isWithdrawConfirming;

  const showInvalidDepositAmount = !!depositAmount && !isDepositValid;
  const showInsufficientBalance = isDepositValid && depositExceedsBalance;
  const showInvalidWithdrawShares = !!withdrawShares && !isWithdrawValid;
  const showInsufficientShares = isWithdrawValid && withdrawExceedsShares;

  return (
    <div className="max-w-7xl mx-auto p-6 space-y-8">
      <GoldHero
        title="Savings"
        subtitle="Deposit AUSD and earn yield from protocol fees"
      />
      {/* Stats Overview */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <StatCard
          title="Your Shares"
          value={userShares ? formatStablecoin(userShares) : "—"}
        />
        <StatCard
          title="Value (AUSD)"
          value={shareValue ? (Number(shareValue) / 1e18).toFixed(2) : "—"}
        />
        <StatCard
          title="Current APY"
          value={apy !== undefined ? `${apy.toFixed(2)}%` : "—"}
        />
      </div>

      {/* Deposit & Withdraw Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mt-20">
        {/* Deposit */}
        <form onSubmit={handleDepositSubmit} className="form-card">
          <h4 className="form-heading">Deposit into Savings</h4>
          <input
            type="number" placeholder="0.00" step="0.01"
            value={depositAmount} onChange={e => setDepositAmount(e.target.value)}
            className="form-input"
          />
          <button
            type="submit"
            disabled={isDepositDisabled}
            className="btn-primary"
          >
            {isDepositPending ? "Processing..." : "Deposit"}
          </button>
          {showInvalidDepositAmount && (
            <p className="text-red-500 text-sm">Please enter a valid amount greater than 0.</p>
          )}
          {showInsufficientBalance && (
            <p className="text-red-500 text-sm">Insufficient AUSD balance.</p>
          )}
          {depositError && <p className="text-red-500 text-sm">{depositError}</p>}
        </form>

        {/* Withdraw */}
        <form onSubmit={handleWithdraw} className="form-card">
          <h4 className="form-heading">Withdraw from Savings</h4>
          <input
            type="number" placeholder="0.00" step="0.01"
            value={withdrawShares} onChange={e => setWithdrawShares(e.target.value)}
            className="form-input"
          />
          <button
            type="submit"
            disabled={isWithdrawDisabled}
            className="btn-primary"
          >
            {isWithdrawPending || isWithdrawConfirming ? "Processing..." : "Withdraw"}
          </button>
          {showInvalidWithdrawShares && (
            <p className="text-red-500 text-sm">Please enter a valid number of shares greater than 0.</p>
          )}
          {showInsufficientShares && (
            <p className="text-red-500 text-sm">Insufficient shares.</p>
          )}
          {withdrawError && <p className="text-red-500 text-sm">{withdrawError}</p>}
        </form>
      </div>
    </div>
  );
}