"use client";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { isAddress, parseEther, type Abi } from "viem";
import { useAccount, useReadContract } from "wagmi";
import aurumAUSDJson from "@/abis/AurumUSD.json";
import aurumEngineJson from "@/abis/AurumEngine.json";
import { AUR_GOLD_ADDRESS, AURUM_AUSD_ADDRESS, AURUM_ENGINE_ADDRESS, PRECISION, WETH_ADDRESS } from "@/config/constants";
import { useTransactionContext } from "@/context/useTransactionContext";
import { useUserData } from "@/hooks/useUserData";
import { useAmountValidation } from "@/hooks/useAmountValidation";
import { useApproveAndExecute } from "@/hooks/useApproveAndExecute";
import { formatHealthFactorForDisplay, formatStablecoin, formatUsd, getUserFriendlyErrorMessage } from "@/utils/helperFunctions";
import { CollateralSelector } from "../dashboard/CollateralSelector";
import { Zap } from "lucide-react";
import { useUserPositions } from "@/hooks/useUserPositions";
import { UserPositionRow } from "../monitor/UserPositionRow";


/**
 * Liquidation dashboard for Aurum's frontend.
 * 
 * Displays a table of liquidatable users and a manual form with a
 * profit card. 
 * 
 * The table shows every liquidatable user with a 'Liquidate' button in an
 * 'Action' column. Clicking on the 'Liquidate' button auto-fills the form 
 * by setting that target user to 'targetToLiquidate'. The liquidator/keeper 
 * can then fill out the amount of debt that they will repay.
 * 
 * The component reads the user's AUSD balance and allowance, validates the 
 * input against the wallet balance, and executes the approve + liquidate 
 * flow through AurumEngine. The engine automatically caps the debtToCover 
 * amount at the user's maxDebtToCover debt (calculated from the user's 
 * dynamic close factor), so trying to cover more than the maxDebtToCover 
 * does not cause an error because it simply sets the debtToCover to 
 * maxDebtToCover.
 * 
 * If the target address is eligible for liquidation, a profit card with the 
 * 5% payout (in collateral) is shown, displaying the collateral amount and 
 * its USD value. A message will be shown if the target user does not have 
 * the selected collateral type.
 *
 * Error messages are shown one at a time in priority order:
 * 1. Invalid Ethereum address
 * 2. Target not eligible (health factor >= 1.00)
 * 3. Invalid debt amount (non‑positive)
 * 4. Insufficient AUSD balance
 *
 * Transaction states are managed internally and the global pending
 * banner is updated via TransactionContext.
 * 
 * @component
 * @returns The rendered UI with a table of liquidatable users and form to 
 *          liquidate users with a HF < 1.00.   
 */
export default function LiquidationDashboard() {
  const { address: liquidatorAddress } = useAccount();
  const { refetch: refetchLiquidatorData } = useUserData();
  const { setPendingAction } = useTransactionContext();
  const { positions: underwaterPositions, loading, error } = useUserPositions(PRECISION);
  const formRef = useRef<HTMLDivElement>(null);


  // Local state
  const [selectedTokenIndex, setSelectedTokenIndex] = useState(0);
  const collateralTokens = useMemo(() => [
    { address: AUR_GOLD_ADDRESS, symbol: "AUR", ltv: 85 },
    { address: WETH_ADDRESS, symbol: "WETH", ltv: 65 }
  ], []);
  const selectedToken = collateralTokens[selectedTokenIndex];
  const [targetToLiquidate, setTargetToLiquidate] = useState("");
  const [debtToCoverAmount, setDebtToCoverAmount] = useState("");
  const [debtToCoverAmountError, setDebtToCoverAmountError] = useState<string | null>(null);


  // Read liquidator's AUSD allowance
  const { data: ausdAllowance } = useReadContract({
    address: AURUM_AUSD_ADDRESS,
    abi: aurumAUSDJson.abi,
    functionName: "allowance",
    args: [liquidatorAddress, AURUM_ENGINE_ADDRESS],
    query: { enabled: !!liquidatorAddress },
  }) as { data: bigint | undefined };

  // Read liquidator's AUSD balance
  const { data: ausdBalance, refetch: refetchBalance } = useReadContract({
    address: AURUM_AUSD_ADDRESS,
    abi: aurumAUSDJson.abi,
    functionName: "balanceOf",
    args: [liquidatorAddress],
    query: { enabled: !!liquidatorAddress }
  }) as {
    data: bigint | undefined;
    refetch: () => void;
  };

  // Input validation against wallet balance
  const { isValid: isDebtToCoverAmountValid, exceeds: doesDebtToCoverExceedBalance } =
    useAmountValidation(debtToCoverAmount, ausdBalance);

  // Read AurumEngine's getUserAccountData to get target user's HF
  const trimmedTargetToLiquidate = targetToLiquidate.trim();
  const isValidAddress = trimmedTargetToLiquidate == "" || isAddress(trimmedTargetToLiquidate);

  const { data: targetData, isLoading: isTargetDataLoading, refetch: refetchTargetData } = useReadContract({
    address: AURUM_ENGINE_ADDRESS,
    abi: aurumEngineJson.abi,
    functionName: "getUserAccountData",
    args: [trimmedTargetToLiquidate],
    query: { enabled: !!trimmedTargetToLiquidate && isValidAddress },
  }) as {
    data: {
      totalCollateralValueInUsd: bigint;
      totalDebt: bigint;
      healthFactor: bigint;
      lastIndex: bigint;
      activeCollateralTokens: `0x${string}`[];
      collateralAmounts: bigint[];
      debtAllocations: bigint[];
    } | undefined;
    isLoading: boolean;
    refetch: () => void;
  };
  const targetHealthFactor = targetData?.healthFactor;

  const doesTargetHaveSelectedCollateral = useMemo(() => {
    if (!targetData) return false;
    const targetCollateralTypes = targetData.activeCollateralTokens ?? [];
    return targetCollateralTypes.some(
      (c) => c.toLowerCase() === selectedToken.address.toLowerCase()
    );
  }, [targetData, selectedToken.address]);

  // Prepare amount in wei (if input is valid)
  const debtToCoverAmountWei = useMemo(() => {
    try { return parseEther(debtToCoverAmount || "0"); }
    catch { return 0n; }
  }, [debtToCoverAmount]);

  const { data: profitData } = useReadContract({
    address: AURUM_ENGINE_ADDRESS,
    abi: aurumEngineJson.abi,
    functionName: "getLiquidationProfit",
    args: [selectedToken.address, trimmedTargetToLiquidate as `0x${string}`, debtToCoverAmountWei],
    query: {
      enabled:
        !!trimmedTargetToLiquidate &&
        !!debtToCoverAmount &&
        !!isDebtToCoverAmountValid &&
        !doesDebtToCoverExceedBalance &&
        !!targetHealthFactor &&
        targetHealthFactor < PRECISION
    },
  }) as {
    data: bigint[] | undefined;
    isLoading: boolean
  };


  // Combined burn flow (approve AUSD + burn AUSD)
  const onSuccess = useCallback(() => {
    refetchBalance();
    refetchLiquidatorData();
    setDebtToCoverAmount("");
    setPendingAction(null);
  }, [refetchBalance, setPendingAction, refetchLiquidatorData])

  const {
    start: startLiquidate,
    isPending,
    approveWriteError,
    executeWriteError
  } = useApproveAndExecute({
    approveContract: AURUM_AUSD_ADDRESS,
    approveAbi: aurumAUSDJson.abi as Abi,
    approveFunction: "approve",
    targetContract: AURUM_ENGINE_ADDRESS,
    targetAbi: aurumEngineJson.abi as Abi,
    targetFunction: "liquidate",
    allowance: ausdAllowance,
    onSuccess,
    executeArgs: [selectedToken.address, trimmedTargetToLiquidate]
  });


  // Format write errors to friendly error message
  useEffect(() => {
    const writeError = approveWriteError || executeWriteError;
    if (writeError) {
      setDebtToCoverAmountError(getUserFriendlyErrorMessage(writeError));
    }
  }, [approveWriteError, executeWriteError]);

  // Clear error on input change
  useEffect(() => {
    setDebtToCoverAmountError(null);
  }, [debtToCoverAmount]);

  // Clear global banner on write error
  useEffect(() => {
    if (approveWriteError || executeWriteError) {
      setPendingAction(null);
    }
  }, [approveWriteError, executeWriteError, setPendingAction]);


  // Liquidate handler
  const handleLiquidate = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (!isDebtToCoverAmountValid || doesDebtToCoverExceedBalance) return;
    setPendingAction(`Liquidating ${trimmedTargetToLiquidate}...`);
    startLiquidate(parseEther(debtToCoverAmount));
  };

  // Select target handler
  const handleSelectTarget = (address: string) => {
    setTargetToLiquidate(address);
    formRef.current?.scrollIntoView({ behavior: "smooth" });
  }


  // Error message display 
  const isTargetEligible = targetHealthFactor && targetHealthFactor < PRECISION;
  const showTargetIsIneligible = targetHealthFactor && targetHealthFactor >= PRECISION && !isTargetDataLoading;
  const showInvalidAmount = !!debtToCoverAmount && !isDebtToCoverAmountValid;
  const showInsufficientBalance = isDebtToCoverAmountValid && doesDebtToCoverExceedBalance;

  const errorMessage = useMemo(() => {
    if (!isValidAddress) return "Invalid Ethereum address.";
    if (showTargetIsIneligible) return "Target is ineligible. Only targets with health factors below 1.00 can be liquidated.";
    if (showInvalidAmount) return "Please enter a valid amount greater than 0.";
    if (showInsufficientBalance) return "Insufficient AUSD balance.";
    return null;
  }, [isValidAddress, showTargetIsIneligible, showInvalidAmount, showInsufficientBalance]);


  // Disabled button condition
  const isDisabled =
    !isValidAddress ||
    !isDebtToCoverAmountValid ||
    doesDebtToCoverExceedBalance ||
    !!debtToCoverAmountError ||
    isPending ||
    isTargetDataLoading ||
    !isTargetEligible ||
    (targetData !== undefined && !doesTargetHaveSelectedCollateral);

  // Render UI
  return (
    <div className="max-w-xl mx-auto w-full space-y-6 overflow-hidden">
      {/* Header */}
      <div className="space-y-2">
        <h1 className="text-4xl font-bold text-yellow-800 mt-6">Liquidations</h1>
        <p className="text-yellow-700/70 text-sm">Repay undercollateralized debt and earn a 5% bonus in collateral</p>
        <hr className="gold-border"></hr>
      </div>

      {/* Underwater Positions Table */}
      {loading && <p>Loading underwater positions...</p>}
      {error && <p className="text-red-600">Error: {error.message}</p>}
      {!loading && !error && (
        <div className="table-wrapper">
          <table className="gold-table">
            <thead>
              <tr>
                <th>User</th>
                <th>Total Collateral Value (USD)</th>
                <th>Total Debt</th>
                <th>Health Factor</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
              {underwaterPositions.map(p => (
                <UserPositionRow
                  key={p.id}
                  position={p}
                  action={
                    <button 
                      onClick={() => handleSelectTarget(p.id)} 
                      className="text-sm text-yellow-700 hover:underline whitespace-nowrap"
                    >
                      Liquidate
                    </button>
                  }
                />
              ))}
              {underwaterPositions.length === 0 && (
                <tr>
                  <td colSpan={5} className="text-center text-gray-500">No liquidatable positions.</td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}

      <div ref={formRef} className="mt-8">
        {/* Collateral Selector */}
        <CollateralSelector
          tokens={collateralTokens}
          selectedIndex={selectedTokenIndex}
          onChange={setSelectedTokenIndex}
        />

        {/* Liquidation Form */}
        <form onSubmit={handleLiquidate} className="form-card space-y-4 w-full max-w-[600px] mx-auto overflow-hidden">
          <h4 className="form-heading">Liquidate User</h4>
          {/* Target Address Input */}
          <div>
            <label className="block text-yellow-900 text-xs uppercase tracking-wider font-semibold mb-1">Target Address</label>
            <input
              type="text"
              placeholder="0xabc..."
              value={targetToLiquidate}
              onChange={(e) => setTargetToLiquidate(e.target.value)}
              className="form-input"
            />
            { /* Live Health Factor Indicator */}
            <div className="min-h-[18px]">
              {targetHealthFactor !== undefined && (
                <p className={`text-xs mt-1 font-medium ${targetHealthFactor < PRECISION ? "text-red-600" : "text-green-700"
                  }`}>
                  Health Factor: {formatHealthFactorForDisplay(targetHealthFactor)}
                </p>
              )}
            </div>
            {/* Collateral availability warning */}
            {targetData && !doesTargetHaveSelectedCollateral && (
              <p className="text-xs text-amber-900 mt-1">
                Target does not hold {selectedToken.symbol} collateral.
              </p>
            )}
          </div>

          {/* Debt to Cover Input */}
          <div>
            <label className="block text-yellow-900 text-xs uppercase tracking-wider font-semibold mb-1">Debt to Cover (AUSD)</label>
            <input
              type="number"
              placeholder="0.00"
              step="0.01"
              value={debtToCoverAmount}
              onChange={(e) => setDebtToCoverAmount(e.target.value)}
              className="form-input"
            />
            <div className="min-h-[18px]">
              {isTargetEligible && targetData?.totalDebt !== undefined && (
                <p className="text-xs text-yellow-900 mt-1">
                  Target total debt: {formatStablecoin(targetData.totalDebt)} AUSD
                </p>
              )}
            </div>
          </div>
          {/* Profit Preview */}
          {profitData && (
            <div className="gold-card p-3 text-sm space-y-2 border-l-4 border-yellow-600">
              <p className="text-yellow-900 font-semibold flex items-center gap-1">
                <Zap className="w-4 h-4" />Estimated Liquidation Profit
              </p>
              <div className="flex justify-between">
                <span>Bonus Collateral</span>
                <span className="font-mono font-bold">{formatStablecoin(profitData[1])} {selectedToken.symbol}</span>
              </div>
              <div className="flex justify-between">
                <span>Profit (USD)</span>
                <span className="font-mono font-bold">{formatUsd(profitData[0])}</span>
              </div>
            </div>
          )}

          {/* Submit Button */}
          <button type="submit" disabled={isDisabled} className="btn-primary">
            {isPending ? "Processing..." : "Liquidate"}
          </button>

          {/* Error Messages */}
          <div className="min-h-[24px]">
            {errorMessage && <p className="text-red-500 text-sm">{errorMessage}</p>}
            {debtToCoverAmountError && <p className="text-red-500 text-sm">{debtToCoverAmountError}</p>}
          </div>
        </form>
      </div>
    </div>
  );
}