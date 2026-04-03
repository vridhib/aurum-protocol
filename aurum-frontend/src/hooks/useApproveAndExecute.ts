import { useEffect, useState } from "react";
import { type Abi } from "viem";
import { useWaitForTransactionReceipt, useWriteContract } from "wagmi";


/**
 * Consolidates the approve and execute flow.
 * Initiates an approval and, if the user already has a sufficient allowance, it skips to the execution step.
 * 
 * @param approveContract Contract address that needs to approve a transaction.
 * @param approveAbi Contract ABI of the `approveContract`.
 * @param approveFunction `approve()` function name.
 * @param targetContract Contract address that needs an approval.
 * @param targetAbi Contract ABI of `targetContract`.
 * @param targetFunction Function from `targetContract` that needs approval before execution.
 * @param onSuccess Function that is run upon successful execution.
 * @param allowance Stores user's current allowance (skips approve step if `allowance` is enough).
 * 
 * @returns An object containing:
 * - `start` (`(bigint) => void`) – Function that initiates the approve and execute flow.
 * - `isPending` (`boolean`) – `true` while either of the actions are still pending.
 * - `currentAction` (`string`) – Represents the current step of the approve and execute flow.
 * - `approveWriteError` (`WriteContractErrorType | null`) – Stores any write errors (if any) in the approve step.
 * - `executeWriteError` (`WriteContractErrorType | null`) – Stores any write errors (if any) in the execute step.

 * 
 * @example
 * const { start: startDeposit, isPending: isDepositPendingHook, currentAction: depositAction, approveWriteError: approveDepositWriteError, executeWriteError: executeDepositWriteError } = useApproveAndExecute({
     approveContract: AUR_GOLD_ADDRESS,
     approveAbi: aurumGoldJson.abi as Abi,
     approveFunction: "approve",
     targetContract: AURUM_ENGINE_ADDRESS,
     targetAbi: aurumEngineJson.abi as Abi,
     targetFunction: "depositCollateral",
     allowance: aurAllowance,
     onSuccess: () => {
       refetchUserData();  
       setDepositAmount("");
       setPendingAction(null);
     }
   });
 */
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

    const { data: approveHash, isPending: isApproving, writeContract: approve, error: approveWriteError } = useWriteContract();
    const { isLoading: isApproveConfirmed, isSuccess: isApproveSuccess } = useWaitForTransactionReceipt({ hash: approveHash });

    const { data: executeHash, isPending: isExecuting, writeContract: execute, error: executeWriteError } = useWriteContract();
    const { isLoading: isExecuteConfirmed, isSuccess: isExecuteSuccess } = useWaitForTransactionReceipt({ hash: executeHash });

    // When the approval succeeds, execute the target function
    useEffect(() => {
        if (step === "approving" && isApproveSuccess && amount !== null) {
            setStep("executing");
            execute({
                address: targetContract,
                abi: targetAbi,
                functionName: targetFunction,
                args: [amount]
            });
        }
    }, [step, isApproveSuccess, execute, targetContract, targetAbi, targetFunction, amount]);

    // When the execution succeeds, reset and call onSuccess
    useEffect(() => {
        if (step === "executing" && isExecuteSuccess) {
            setStep("idle");
            setAmount(null);
            onSuccess?.();
        }
    }, [step, isExecuteSuccess, onSuccess]);

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

    const isPending = isApproving || isApproveConfirmed || isExecuting || isExecuteConfirmed;
    const currentAction = step;

    return { start, isPending, currentAction, approveWriteError, executeWriteError };
}