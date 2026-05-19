"use client";
import { useState, useEffect, useCallback } from "react";
import { useWriteContract, useWaitForTransactionReceipt, useAccount, useReadContract } from "wagmi";
import aurumGoldFaucetJson from "@/abis/AurumGoldFaucet.json";
import { AUR_FAUCET_ADDRESS } from "@/config/constants";
import { useTransactionContext } from "@/context/useTransactionContext";
import { useUserData } from "@/hooks/useUserData";
import { LoadingSpinner } from "../LoadingSpinner";
import { PageHeader } from "../PageHeader";


/**
 * Self‑contained component for claiming one‑time test AUR from the faucet.
 *
 * Reads the user's claim eligibility and executes a claim transaction. 
 * Manages all pending, success, and error states internally. Updates 
 * the global pending banner via TransactionContext.
 *
 * Once claimed, the button stays disabled permanently.
 */
export default function ClaimOneTimeAur() {
    const { address: userAddress } = useAccount();
    const { refetch: refetchUserData } = useUserData();
    const { pendingAction, setPendingAction, isAnyTxPending } = useTransactionContext();


    // Local state
    const [claimError, setClaimError] = useState<string | null>(null);


    // Read: hasClaimed AUR
    const { data: hasClaimed, isLoading: isClaimStatusLoading, refetch: refetchClaimStatus } = useReadContract({
        address: AUR_FAUCET_ADDRESS,
        abi: aurumGoldFaucetJson.abi,
        functionName: "s_hasClaimed",
        args: [userAddress],
        query: { enabled: !!userAddress },
    }) as {
        data: boolean | undefined;
        isLoading: boolean;
        refetch: () => void
    };


    // Write: claim AUR
    const { data: claimHash, isPending: isClaimPending, writeContract: claim, error: claimWriteError } = useWriteContract();
    const { isLoading: isClaimConfirming, isSuccess: isClaimSuccess } = useWaitForTransactionReceipt({ hash: claimHash });


    // Pending message management
    useEffect(() => {
        if (isClaimPending || isClaimConfirming) {
            setPendingAction("Claiming AUR from faucet...");
        } else {
            setPendingAction(null);
        }
    }, [isClaimPending, isClaimConfirming, setPendingAction]);

    // On success, update everything
    useEffect(() => {
        if (isClaimSuccess) {
            setPendingAction(null);
            refetchUserData();
            refetchClaimStatus();
        }
    }, [isClaimSuccess, refetchUserData, refetchClaimStatus, setPendingAction]);

    // Handle errors
    useEffect(() => {
        if (claimWriteError) {
            setClaimError("Transaction failed. Please try again.");
            setPendingAction(null);
        }
    }, [claimWriteError, setPendingAction]);


    // Claim handler 
    const handleClaim = useCallback(() => {
        setClaimError(null);
        claim({
            address: AUR_FAUCET_ADDRESS,
            abi: aurumGoldFaucetJson.abi,
            functionName: "claim",
        });
    }, [claim]);


    // Button state
    const isDisabled = hasClaimed || isClaimPending || isClaimConfirming || isClaimStatusLoading;
    const buttonText = isClaimPending || isClaimConfirming
        ? "Processing..."
        : isClaimStatusLoading
            ? "Loading..."
            : hasClaimed
                ? "Already Claimed"
                : "Get Test AUR";

    return (
        <div className="max-w-7xl mx-auto p-6 space-y-8">
            <PageHeader
                heading="AUR Faucet"
                subtitle="Claim One-Time AUR"
            />

            {/* Claim Card */}
            <div className="max-w-md mx-auto mt-16 bg-gray-800 border border-gray-700 p-8 rounded-xl shadow-lg text-center space-y-6">
                <h2 className="text-2xl font-bold text-white">AUR Faucet</h2>
                <p className="text-gray-300 text-sm">
                    Each address can claim <strong>10 AUR</strong> once. This faucet is for Sepolia testnet only.
                </p>
                <button
                    onClick={handleClaim}
                    disabled={isDisabled}
                    className="w-full bg-yellow-600 hover:bg-yellow-700 text-white font-bold py-3 px-4 rounded-lg transition disabled:opacity-50 disabled:cursor-not-allowed"
                >
                    {buttonText}
                </button>
                {claimError && <p className="text-red-500 text-sm">{claimError}</p>}
            </div>
        </div>
    );
}