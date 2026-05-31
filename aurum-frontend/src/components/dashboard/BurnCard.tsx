"use client";
import { useCallback, useEffect, useState } from "react";
import { parseEther, type Abi } from "viem";
import { useAccount, useReadContract } from "wagmi";
import aurumAUSDJson from "@/abis/AurumUSD.json";
import aurumEngineJson from "@/abis/AurumEngine.json";
import { AURUM_AUSD_ADDRESS, AURUM_ENGINE_ADDRESS } from "@/config/constants";
import { useTransactionContext } from "@/context/useTransactionContext";
import { useUserData } from "@/hooks/useUserData";
import { useAmountValidation } from "@/hooks/useAmountValidation";
import { useApproveAndExecute } from "@/hooks/useApproveAndExecute";
import { getUserFriendlyErrorMessage } from "@/utils/helperFunctions";


/**
 * Self‑contained burn form used in the Dashboard page.
 *
 * Reads the user's AUSD balance and allowance, validates the input
 * against the wallet balance, and executes the approve + burn flow
 * through AurumEngine. The engine automatically caps the amount at 
 * the user's total debt, so burning more than the debt does not
 * cause an error because it simply repays everything.
 *
 * Error messages are shown in priority order:
 * 1. Invalid amount (burnAmount <= 0)
 * 2. Insufficient AUSD balance
 *
 * Transaction states are managed internally and the global pending
 * banner is updated via TransactionContext.
 * 
 * @component
 * @returns The rendered UI form for minting AUSD.
 */
export function BurnCard() {
    const { address: userAddress } = useAccount();
    const { refetch: refetchUserData } = useUserData();
    const { setPendingAction } = useTransactionContext();


    // Local state
    const [burnAmount, setBurnAmount] = useState("");
    const [burnError, setBurnError] = useState<string | null>(null);


    // Read user's AUSD allowance
    const { data: ausdAllowance } = useReadContract({
        address: AURUM_AUSD_ADDRESS,
        abi: aurumAUSDJson.abi,
        functionName: "allowance",
        args: [userAddress, AURUM_ENGINE_ADDRESS],
        query: { enabled: !!userAddress },
    }) as { data: bigint | undefined };

    // Read user's AUSD balance
    const { data: ausdBalance, refetch: refetchBalance } = useReadContract({
        address: AURUM_AUSD_ADDRESS,
        abi: aurumAUSDJson.abi,
        functionName: "balanceOf",
        args: [userAddress],
        query: {enabled: !!userAddress }
    }) as {
        data: bigint | undefined;
        refetch: () => void;
    };


    // Input validation against wallet balance
    const { isValid: isBurnAmountValid, exceeds: doesBurnExceedBalance } = useAmountValidation(burnAmount, ausdBalance);


    // Combined burn flow (approve AUSD + burn AUSD)
    const onSuccess = useCallback(() => {
        refetchBalance();
        refetchUserData();
        setBurnAmount("");
        setPendingAction(null);
    }, [refetchBalance, setPendingAction, refetchUserData])

    const { 
        start: startBurn, 
        isPending, 
        approveWriteError, 
        executeWriteError 
    } = useApproveAndExecute({
        approveContract: AURUM_AUSD_ADDRESS,
        approveAbi: aurumAUSDJson.abi as Abi,
        approveFunction: "approve",
        targetContract: AURUM_ENGINE_ADDRESS,
        targetAbi: aurumEngineJson.abi as Abi,
        targetFunction: "burnAUSD",
        allowance: ausdAllowance,
        onSuccess
    });


    // Format write errors to friendly error message
    useEffect(() => {
        const writeError = approveWriteError || executeWriteError;
        if (writeError) {
            setBurnError(getUserFriendlyErrorMessage(writeError));
        }
    }, [approveWriteError, executeWriteError]);

    // Clear error on input change
    useEffect(() => {
        setBurnError(null);
    }, [burnAmount]);

    // Clear global banner on write error
    useEffect(() => {
        if (approveWriteError || executeWriteError) {
            setPendingAction(null);
        }
    }, [approveWriteError, executeWriteError, setPendingAction]);


    // Burn handler
    const handleBurn = async (e: React.FormEvent<HTMLFormElement>) => {
        e.preventDefault();
        if (!isBurnAmountValid || doesBurnExceedBalance) return;
        setPendingAction(`Burning AUSD...`);
        startBurn(parseEther(burnAmount));
    };


    // Disabled state
    const isDisabled = !isBurnAmountValid || doesBurnExceedBalance || !!burnError || isPending;

    const showInvalidAmount = !!burnAmount && !isBurnAmountValid;
    const showInsufficientBalance = isBurnAmountValid && doesBurnExceedBalance;

    return (
        <form onSubmit={handleBurn} className="form-card">
            <h4 className="form-heading">Burn AUSD</h4>
            <input
                type="number"
                placeholder="0.00"
                step="0.01"
                value={burnAmount}
                onChange={(e) => setBurnAmount(e.target.value)}
                className="form-input"
            />
            <button
                type="submit"
                disabled={isDisabled}
                className="btn-primary"
            >
                {isPending ? "Processing..." : "Burn"}
            </button>

            {showInvalidAmount && (
                <p className="text-red-500 text-sm">Please enter a valid amount greater than 0.</p>
            )}
            {showInsufficientBalance && (
                <p className="text-red-500 text-sm">Insufficient AUSD balance.</p>
            )}
            {burnError && <p className="text-red-500 text-sm">{burnError}</p>}
        </form>
    );
}