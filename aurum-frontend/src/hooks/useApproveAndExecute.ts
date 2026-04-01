import { useEffect, useState } from "react";
import { type Abi } from "viem";
import { useWaitForTransactionReceipt, useWriteContract } from "wagmi";

export function useApproveAndExecute({
    approveContract,
    approveAbi,
    approveFunction,
    targetContract,
    targetAbi,
    targetFunction,
    onSuccess,
    allowance,
}: {
    approveContract: `0x${string}`;
    approveAbi: Abi;
    approveFunction: string;
    targetContract: `0x${string}`;
    targetAbi: Abi;
    targetFunction: string;
    onSuccess?: () => void;
    allowance?: bigint;
}) {
    const [step, setStep] = useState<"idle" | "approving" | "executing">("idle");
    const [amount, setAmount] = useState<bigint | null>(null);
    const [error, setError] = useState<Error | null>(null);

    const { data: approveHash, isPending: isApproving, writeContract: approve } = useWriteContract();
    const { isLoading: isApprovingConfirmed, isSuccess: isApproved } = useWaitForTransactionReceipt({ hash: approveHash });

    const { data: executeHash, isPending: isExecuting, writeContract: execute } = useWriteContract();
    const { isLoading: isExecutingConfirmed, isSuccess: isExecuted } = useWaitForTransactionReceipt({ hash: executeHash });

    // When the approval succeeds, execute the target function
    useEffect(() => {
        if (step === "approving" && isApproved && amount !== null) {
            setStep("executing");
            execute({
                address: targetContract,
                abi: targetAbi,
                functionName: targetFunction,
                args: [amount]
            });
        }
    }, [step, isApproved, execute, targetContract, targetAbi, targetFunction, amount]);

    // When the execution succeeds, reset and call onSuccess
    useEffect(() => {
        if (step === "executing" && isExecuted) {
            setStep("idle");
            setAmount(null);
            onSuccess?.();
        }
    }, [step, isExecuted, onSuccess]);

    const start = (newAmount: bigint) => {
        setAmount(newAmount);
        // If allowance is enough, go directly to execution
        if (allowance !== undefined && allowance >= newAmount) {
            setStep("executing");
            execute({
                address: targetContract,
                abi: targetAbi,
                functionName: targetFunction,
                args: [newAmount],
            });
        } else {
            setStep("approving");
            approve({
                address: approveContract,
                abi: approveAbi,
                functionName: approveFunction,
                args: [targetContract, newAmount],
            });
        }
    };

    const isPending = isApproving || isApprovingConfirmed || isExecuting || isExecutingConfirmed;
    const currentAction = step;

    return { start, isPending, currentAction, error };
}