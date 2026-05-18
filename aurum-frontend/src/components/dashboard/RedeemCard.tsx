import { useEffect, useMemo, useState } from "react";
import { parseEther } from "viem";
import { useWaitForTransactionReceipt, useWriteContract } from "wagmi";
import { useTransactionContext } from "@/context/useTransactionContext";
import { useAmountValidation } from "@/hooks/useAmountValidation";
import { useProtocolData } from "@/hooks/useProtocolData";
import { useUserData } from "@/hooks/useUserData";
import { getUserFriendlyErrorMessage } from "@/utils/helperFunctions";
import aurumEngineJson from "@/abis/AurumEngine.json";
import { AUR_GOLD_ADDRESS, AURUM_ENGINE_ADDRESS, PERCENTAGE_PRECISION, PRECISION, PRICE_FEED_PRECISION, WETH_ADDRESS } from "@/config/constants";
import { TokenConfig } from "@/types/collateral";

interface RedeemCardProps {
    selectedToken: TokenConfig
}


/**
 * Self‑contained redemption form for a single collateral token.
 *
 * Reads the user's deposited collateral amount of the selected token, 
 * validates the input against their balance, and calculates the projected
 * health factor using the engine's formula. Executes the redeem through
 * the AurumEngine contract and manages all transaction states internally.
 * Updates the global pending banner via TransactionContext.
 *
 * Error messages are shown in priority order:
 * 1. Invalid amount (redeemAmount <= 0)
 * 2. Insufficient deposited balance
 * 3. Health factor would drop below 1 after redemption
 *
 * @param selectedToken - The collateral token to redeem (address, symbol).
 */
export function RedeemCard({ selectedToken }: RedeemCardProps) {
  const { activeCollateralTokens, collateralAmounts, mintedAmount, refetch: refetchUserData } = useUserData();
  const { collaterals, pricePerAur, pricePerWeth } = useProtocolData();
  const { setPendingAction } = useTransactionContext();


  // Local state
  const [redeemAmount, setRedeemAmount] = useState("");
  const [redeemError, setRedeemError] = useState<string | null>(null);


  // Input validation
  const maxRedeemable = useMemo(() => {
    if (!activeCollateralTokens || !collateralAmounts) return undefined;
    const index = activeCollateralTokens.findIndex(a => a === selectedToken.address);
    if (index === -1) return 0n;
    return collateralAmounts[index];
  }, [activeCollateralTokens, collateralAmounts, selectedToken.address]);
  
  const { isValid: isRedeemAmountValid, exceeds: doesRedeemExceedCollateral } = useAmountValidation(redeemAmount, maxRedeemable);


  // Write: Redeem collateral
  const { data: redeemHash, isPending: isRedeemPending, writeContract: redeem, error: redeemWriteError } = useWriteContract();
  const { isLoading: isRedeemConfirming, isSuccess: isRedeemSuccess } =
    useWaitForTransactionReceipt({ hash: redeemHash });


  // Calculate projected HF after redemption 
  const activeTokens = activeCollateralTokens ?? [];
  const amounts = collateralAmounts ?? [];
  const debt = mintedAmount ?? 0n;

  const priceMap = useMemo(() => {
    const map = new Map<`0x${string}`, bigint>();
    if (pricePerAur !== undefined) map.set(AUR_GOLD_ADDRESS, pricePerAur);
    if (pricePerWeth !== undefined) map.set(WETH_ADDRESS, pricePerWeth);
    return map;
  }, [pricePerAur, pricePerWeth]);

  const redeemWouldBeHealthy = useMemo(() => {
    // Amount must be positive and protocol data must be defined
    if (!redeemAmount || parseFloat(redeemAmount) <= 0) return true;
    if (!collaterals || collaterals.length === 0) return false;

    // Find selected token in the user's active list
    const index = activeTokens.findIndex(a => a === selectedToken.address);
    if (index === -1) return false;

    const redeemWei = parseEther(redeemAmount);
    if (redeemWei > amounts[index]) return false;
    // Simulate new collateral amounts
    const newAmounts = [...amounts];
    newAmounts[index] = amounts[index] - redeemWei;

    // Compute new adjusted collateral
    let newAdjusted = 0n;
    for (let i = 0; i < newAmounts.length; i++) {
      const amount = newAmounts[i];
      if (amount === 0n) continue;
      const tokenAddress = activeTokens[i];
      const price = priceMap.get(tokenAddress);
      if (!price) continue;
      const collateralData = collaterals.find(c => c.address === tokenAddress);
      if (!collateralData) continue;

      const usdValue = (price * amount) / PRECISION;
      newAdjusted += (usdValue * collateralData.ltv) / PERCENTAGE_PRECISION;
    }
    return debt === 0n ? true : (newAdjusted * PRECISION) / debt >= PRECISION;
  }, [redeemAmount, activeTokens, amounts, collaterals, priceMap, selectedToken.address]);


  // Clear error when user changes amount
  useEffect(() => {
    setRedeemError(null);
  }, [redeemAmount]);

  // Format write errors to friendly error message
  useEffect(() => {
    if (redeemWriteError) {
      setRedeemError(getUserFriendlyErrorMessage(redeemWriteError));
      setPendingAction(null);
    }
  }, [redeemWriteError, setPendingAction]);

  // On success, reset everything
  useEffect(() => {
    if (isRedeemSuccess) {
      setPendingAction(null);
      setRedeemAmount("");
      refetchUserData();
    }
  }, [isRedeemSuccess, refetchUserData, setPendingAction]);


  // Redeem handler
  const handleRedeem = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (!redeemWouldBeHealthy) return;
    setPendingAction(`Redeeming ${selectedToken.symbol}...`);
    redeem({
      address: AURUM_ENGINE_ADDRESS,
      abi: aurumEngineJson.abi,
      functionName: "redeemCollateral",
      args: [selectedToken.address, parseEther(redeemAmount)]
    });
  };

  // Disabled button state
  const isDisabled = 
    !isRedeemAmountValid || 
    doesRedeemExceedCollateral || 
    !redeemWouldBeHealthy || 
    isRedeemPending || 
    isRedeemConfirming || 
    !!redeemError;

  const showInvalidAmount = !!redeemAmount && !isRedeemAmountValid;
  const showInsufficientDeposit = isRedeemAmountValid && doesRedeemExceedCollateral;
  const showHealthFactorWarning = isRedeemAmountValid && !doesRedeemExceedCollateral && !redeemWouldBeHealthy;

  return (
    <form onSubmit={handleRedeem} className="bg-gray-800 border border-gray-700 p-6 rounded-xl shadow-sm space-y-4">
      <h3 className="text-xl font-bold text-white">Redeem {selectedToken.symbol}</h3>
      <input
        type="number"
        placeholder="0.00"
        step="0.01"
        value={redeemAmount}
        onChange={(e) => setRedeemAmount(e.target.value)}
        className="w-full p-3 bg-gray-900 border border-gray-700 rounded-lg text-white focus:ring-2 focus:ring-blue-500 outline-none transition"
      />
      <button
        type="submit"
        disabled={isDisabled}
        className="w-full bg-blue-600 hover:bg-blue-700 text-white font-bold py-3 px-4 rounded-lg transition disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {isRedeemPending ? "Processing..." : "Redeem"}
      </button>

      {showInvalidAmount && (
        <p className="text-red-500 text-sm">Please enter a valid amount greater than 0.</p>
      )}
      {showInsufficientDeposit && (
        <p className="text-red-500 text-sm">Insufficient {selectedToken.symbol} deposited.</p>
      )}
      {showHealthFactorWarning && (
        <p className="text-red-500 text-sm">
          Redeeming {redeemAmount} {selectedToken.symbol} would put your health factor below 1.
        </p>
      )}
      {redeemError && <p className="text-red-500 text-sm">{redeemError}</p>}
    </form>
  )
}