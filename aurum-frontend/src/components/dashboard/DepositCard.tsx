"use client";
import { useState, useCallback, useEffect } from "react";
import { parseEther, type Abi } from "viem";
import { useAccount, useReadContract } from "wagmi";
import aurumEngineJson from "@/abis/AurumEngine.json";
import erc20Json from "@/abis/ERC20.json";
import { AURUM_ENGINE_ADDRESS } from "@/config/constants";
import { useTransactionContext } from "@/context/useTransactionContext";
import { useAmountValidation } from "@/hooks/useAmountValidation";
import { useApproveAndExecute } from "@/hooks/useApproveAndExecute";
import { useUserData } from "@/hooks/useUserData";
import { TokenConfig } from "@/types/collateral";
import { getUserFriendlyErrorMessage } from "@/utils/helperFunctions";


interface DepositCardProps {
    selectedToken: TokenConfig;
}

/**
 * Self‑contained deposit form for a single collateral token used in the
 * Dashboard page.
 *
 * Reads the user's ERC20 balance and allowance for the selected token,
 * validates the input, and executes the approve + deposit flow through
 * AurumEngine. Handles all transaction lifecycle states (pending, 
 * error, and success) internally and updates the global pending banner
 * via TransactionContext.
 * 
 * Error messages are shown in priority order:
 * 1. Invalid amount (depositAmount <= 0)
 * 2. Insufficient AUR/WETH balance
 * 
 * @param selectedToken The collateral token to deposit (address, symbol).
 * @returns The rendered UI form for depositing collateral.
 */
export function DepositCard({ selectedToken }: DepositCardProps) {
    const { address: userAddress } = useAccount();
    const { refetch: refetchUserData } = useUserData();
    const { setPendingAction } = useTransactionContext();


    // Local state
    const [depositAmount, setDepositAmount] = useState("");
    const [depositError, setDepositError] = useState<string | null>(null); 


    // Read user's allowance of the selected token
    const { data: tokenAllowance } = useReadContract({
        address: selectedToken.address,
        abi: erc20Json.abi,
        functionName: "allowance",
        args: userAddress ? [userAddress, AURUM_ENGINE_ADDRESS] : undefined,
        query: { enabled: !!userAddress },
    }) as { data: bigint | undefined };

    // Read user’s balance of the selected token 
    const { data: tokenBalance, refetch: refetchBalance } = useReadContract({
        address: selectedToken.address,
        abi: erc20Json.abi,
        functionName: "balanceOf",
        args: [userAddress],
        query: {enabled: !!userAddress }
    }) as {
        data: bigint | undefined;
        refetch: () => void;
    };


    // Input validation against wallet balance
    const { isValid: isDepositAmountValid, exceeds: doesDepositExceedBalance } = useAmountValidation(depositAmount, tokenBalance);


    // Combined deposit flow (approve token + deposit token)
    const onSuccess = useCallback(() => {
        refetchBalance();
        refetchUserData();
        setDepositAmount("");
        setPendingAction(null);
    }, [refetchBalance, setPendingAction, refetchUserData])

    const { 
        start: startDeposit, 
        isPending, 
        approveWriteError, 
        executeWriteError 
    } = useApproveAndExecute({
        approveContract: selectedToken.address,
        approveAbi: erc20Json.abi as Abi,
        approveFunction: "approve",
        targetContract: AURUM_ENGINE_ADDRESS,
        targetAbi: aurumEngineJson.abi as Abi,
        targetFunction: "depositCollateral",
        allowance: tokenAllowance,
        executeArgs: [selectedToken.address],
        onSuccess
    });


    // Format write errors to friendly error message
    useEffect(() => {
        const writeError = approveWriteError || executeWriteError;
        if (writeError) {
            setDepositError(getUserFriendlyErrorMessage(writeError));
        }
    }, [approveWriteError, executeWriteError]);

    // Clear error on input change
    useEffect(() => {
        setDepositError(null);
    }, [depositAmount]);

    // Clear global banner on write error
    useEffect(() => {
        if (approveWriteError || executeWriteError) {
            setPendingAction(null);
        }
    }, [approveWriteError, executeWriteError, setPendingAction]);


    // Deposit handler
    const handleDeposit = async (e: React.FormEvent<HTMLFormElement>) => {
        e.preventDefault();
        if (!isDepositAmountValid || doesDepositExceedBalance) return;
        setPendingAction(`Depositing ${selectedToken.symbol}...`);
        startDeposit(parseEther(depositAmount));
    };


    // Disabled state
    const isDisabled = !isDepositAmountValid || doesDepositExceedBalance || !!depositError ||  isPending;

    const showInvalidAmount = !!depositAmount && !isDepositAmountValid;
    const showInsufficientBalance = isDepositAmountValid && doesDepositExceedBalance;

    return (
        <form onSubmit={handleDeposit} className="form-card">
            <h4 className="form-heading">Deposit {selectedToken.symbol}</h4>
            <input
                type="number"
                placeholder="0.00"
                step="0.01"
                value={depositAmount}
                onChange={(e) => setDepositAmount(e.target.value)}
                className="form-input"
            />
            <button
                type="submit"
                disabled={isDisabled}
                className="btn-primary"
            >
                {isPending ? "Processing..." : "Deposit"}
            </button>

            {showInvalidAmount && (
                <p className="text-red-500 text-sm">Please enter a valid amount greater than 0.</p>
            )}
            {showInsufficientBalance && (
                <p className="text-red-500 text-sm">Insufficient {selectedToken.symbol} balance.</p>
            )}
            {depositError && <p className="text-red-500 text-sm">{depositError}</p>}
        </form>
    )
}