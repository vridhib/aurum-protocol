"use client";

import { useTransactionContext } from "@/context/useTransactionContext";
import { useAmountValidation } from "@/hooks/useAmountValidation";
import { useApproveAndExecute } from "@/hooks/useApproveAndExecute";
import { useState, useCallback, useEffect } from "react";
import { AURUM_ENGINE_ADDRESS } from "@/config/constants";
import aurumEngineJson from "@/abis/AurumEngine.json";
import erc20Json from "@/abis/ERC20.json";
import { parseEther, type Abi } from "viem";
import { useAccount, useReadContract } from "wagmi";
import { useUserData } from "@/hooks/useUserData";
import { getUserFriendlyErrorMessage } from "@/utils/helperFunctions";
import { TokenConfig } from "@/types/collateral";

interface DepositCardProps {
    selectedToken: TokenConfig;
}

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

    // Validation
    const { isValid, exceeds } = useAmountValidation(depositAmount, tokenBalance);

    // Deposit (approve + execute)
    const onSuccess = useCallback(() => {
        refetchBalance();
        refetchUserData();
        setDepositAmount("");
        setPendingAction(null);
    }, [refetchBalance, setPendingAction, refetchUserData])

    const { 
        start: startDeposit, 
        isPending, 
        currentAction, 
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

    // Surface write errors
    useEffect(() => {
        const writeError = approveWriteError || executeWriteError;
        if (writeError) {
            setDepositError(getUserFriendlyErrorMessage(writeError));
        }
    }, [approveWriteError, executeWriteError]);

    // Reset error when depositAmount changes (user starts typing again)
    useEffect(() => {
        setDepositError(null);
    }, [depositAmount]);

    useEffect(() => {
        if (approveWriteError || executeWriteError) {
            setPendingAction(null);
        }
    }, [approveWriteError, executeWriteError, setPendingAction]);



    // Submit handler
    const handleDeposit = async (e: React.FormEvent<HTMLFormElement>) => {
        e.preventDefault();
        if (!isValid || exceeds) return;

        setPendingAction(`Depositing ${selectedToken.symbol}...`);
        startDeposit(parseEther(depositAmount));
    };

    // Disabled state
    const isDisabled = !isValid || exceeds || !!depositError || isPending;

    return (
        <form onSubmit={handleDeposit} className="bg-gray-800 border border-gray-700 p-6 rounded-xl shadow-sm space-y-4">
            <h3 className="text-xl font-bold text-white">Deposit {selectedToken.symbol}</h3>
            <input
                type="number"
                placeholder="0.00"
                step="0.01"
                value={depositAmount}
                onChange={(e) => setDepositAmount(e.target.value)}
                className="w-full p-3 bg-gray-900 border border-gray-700 rounded-lg text-white focus:ring-2 focus:ring-blue-500 outline-none transition"
            />
            <button
                type="submit"
                disabled={isDisabled}
                className="w-full bg-blue-600 hover:bg-blue-700 text-white font-bold py-3 px-4 rounded-lg transition disabled:opacity-50 disabled:cursor-not-allowed"
            >
                {isPending ? "Processing..." : "Deposit"}
            </button>
            {!!depositAmount && !isValid && (<p className="text-red-500 text-sm">Please enter a valid amount greater than 0.</p>)}
            {isValid && exceeds && (<p className="text-red-500 text-sm">Insufficient {selectedToken.symbol} balance.</p>)}
            {depositError && <p className="text-red-500 text-sm">{depositError}</p>}
        </form>
    )
}