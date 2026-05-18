import { AUR_GOLD_ADDRESS, AURUM_ENGINE_ADDRESS, PERCENTAGE_PRECISION, PRECISION, PRICE_FEED_PRECISION, WETH_ADDRESS } from "@/config/constants";
import aurumEngineJson from "@/abis/AurumEngine.json";
import { useTransactionContext } from "@/context/useTransactionContext";
import { useAmountValidation } from "@/hooks/useAmountValidation";
import { useProtocolData } from "@/hooks/useProtocolData";
import { useUserData } from "@/hooks/useUserData";
import { getUserFriendlyErrorMessage } from "@/utils/helperFunctions";
import { useEffect, useMemo, useState } from "react";
import { parseEther } from "viem";
import { useWaitForTransactionReceipt, useWriteContract } from "wagmi";

/**
 * Self‑contained mint form.
 *
 * Projects the user’s health factor after minting using the engine’s
 * multi‑collateral formula. The mint amount is not token‑specific (minting 
 * increases total debt globally). Transaction states are managed internally
 * and the global pending banner is updated via TransactionContext.
 *
 * Error messages are shown in priority order:
 * 1. Invalid amount (mintAmount <= 0)
 * 2. No collateral deposited (totalCollateralValue == 0)
 * 3. Health factor would drop below 1 after minting
 */
export function MintCard() {
    const { amountCollateral: totalCollateralValue = 0n, activeCollateralTokens, collateralAmounts, mintedAmount, refetch: refetchUserData } = useUserData();
    const { collaterals, pricePerAur, pricePerWeth } = useProtocolData();
    const { setPendingAction } = useTransactionContext();


    // Local state
    const [mintAmount, setMintAmount] = useState("");
    const [mintError, setMintError] = useState<string | null>(null);


    // Input validation
    const { isValid: isMintAmountValid } = useAmountValidation(mintAmount);


    // Write: Mint AUSD
    const { data: mintHash, isPending: isMintPending, writeContract: mint, error: mintWriteError } = useWriteContract();
    const { isLoading: isMintConfirming, isSuccess: isMintSuccess } =
    useWaitForTransactionReceipt({ hash: mintHash });


    // Calculate projected HF after minting 
    const activeTokens = activeCollateralTokens ?? [];
    const amounts = collateralAmounts ?? [];
    const debt = mintedAmount ?? 0n;

    const priceMap = useMemo(() => {
    const map = new Map<`0x${string}`, bigint>();
    if (pricePerAur !== undefined) map.set(AUR_GOLD_ADDRESS, pricePerAur);
    if (pricePerWeth !== undefined) map.set(WETH_ADDRESS, pricePerWeth);
    return map;
    }, [pricePerAur, pricePerWeth]);
    
    const mintWouldBeHealthy = useMemo(() => {
        // Amount must be positive and protocol data must be defined
        if (totalCollateralValue === 0n) return false;
        if (!mintAmount || parseFloat(mintAmount) <= 0) return true;
        if (!collaterals || collaterals.length === 0) return false;
    
        const mintWei = parseEther(mintAmount);
        const newDebt = debt + mintWei;

        // Compute current adjusted collateral
        let adjusted = 0n;
        for (let i = 0; i < activeTokens.length; i++) {
          const amount = amounts[i];
          if (amount === 0n) continue;
          const tokenAddress = activeTokens[i];
          const price = priceMap.get(tokenAddress);
          if (!price) continue;
          const collateralData = collaterals.find(c => c.address === tokenAddress);
          if (!collateralData) continue;
    
          const usdValue = (price * amount) / PRECISION;
          adjusted += (usdValue * collateralData.ltv) / PERCENTAGE_PRECISION;
        }
        return (adjusted * PRECISION) / newDebt >= PRECISION;
      }, [mintAmount, activeTokens, amounts, collaterals, priceMap, totalCollateralValue, debt]);
    
    
    // Clear error when user changes amount
    useEffect(() => {
        setMintError(null);
    }, [mintAmount]);

    // Format write errors to friendly error message
    useEffect(() => {
        if (mintWriteError) {
            setMintError(getUserFriendlyErrorMessage(mintWriteError));
            setPendingAction(null);
        }
    }, [mintWriteError, setPendingAction]);

    // On success, reset everything
    useEffect(() => {
        if (isMintSuccess) {
            setPendingAction(null);
            setMintAmount("");
            refetchUserData();
        }
    }, [isMintSuccess, refetchUserData, setPendingAction]);


    // Mint handler
    const handleMint = async (e: React.FormEvent<HTMLFormElement>) => {
        e.preventDefault();
        setPendingAction(`Minting AUSD...`);
        mint({
            address: AURUM_ENGINE_ADDRESS,
            abi: aurumEngineJson.abi,
            functionName: "mintAUSD",
            args: [parseEther(mintAmount)],
        });
    };


    // Disabled button state
    const isDisabled =
    !isMintAmountValid || 
    !!mintError || 
    isMintPending || 
    isMintConfirming || 
    !mintWouldBeHealthy;

    const showInvalidAmount = !!mintAmount && !isMintAmountValid;
    const showMissingDeposit = isMintAmountValid && totalCollateralValue === 0n;
    const showHealthFactorWarning = isMintAmountValid && (totalCollateralValue > 0n) && !mintWouldBeHealthy;
      
    return (
        <form onSubmit={handleMint} className="bg-gray-800 border border-gray-700 p-6 rounded-xl shadow-sm space-y-4">
            <h3 className="text-xl font-bold text-white">Mint AUSD</h3>
            <input
                type="number"
                placeholder="0.00"
                step="0.01"
                value={mintAmount}
                onChange={(e) => setMintAmount(e.target.value)}
                className="w-full p-3 bg-gray-900 border border-gray-700 rounded-lg text-white focus:ring-2 focus:ring-blue-500 outline-none transition"
            />
            <button
                type="submit"
                disabled={isDisabled}
                className="w-full bg-green-600 hover:bg-green-700 text-white font-bold py-3 px-4 rounded-lg transition disabled:opacity-50 disabled:cursor-not-allowed"
            >
                {isMintPending ? "Processing..." : "Mint"}
            </button>

            {showInvalidAmount && (
                <p className="text-red-500 text-sm">Please enter a valid amount greater than 0.</p>
            )}
            {showMissingDeposit && (
                <p className="text-red-500 text-sm">Cannot mint AUSD without depositing collateral.</p>
            )}
            {showHealthFactorWarning && (
                <p className="text-red-500 text-sm">Minting this amount would put your health factor below 1.</p>
            )}
            {mintError && <p className="text-red-500 text-sm">{mintError}</p>}
        </form>
    )
}