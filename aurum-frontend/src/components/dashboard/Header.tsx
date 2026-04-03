import { LoadingSpinner } from "./LoadingSpinner";


/**
 * Header section for the dashboard of the Aurum Protocol frontend. 
 * @param isAnyTxPending Indicates whether any transaction is pending.
 * @param pendingAction Stores the current pending action as a string.
 * @param onRefresh Function that refreshes data.
 * @param onClaim Function that handles a claim test AUR action.
 * @param canClaim Indicates whether a user can claim test AUR.
 * @param isClaimPending Indicates whether a claim action is pending.
 * @param isClaimConfirming Indicates whether a claim action is confirming. 
 * @component
 * @returns A header section for the main dashboard.
 */
export function Header({
    isAnyTxPending,
    pendingAction,
    onRefresh,
    onClaim,
    canClaim,
    isClaimPending,
    isClaimConfirming
}: {
    isAnyTxPending: boolean;
    pendingAction: string | null;
    onRefresh: () => void;
    onClaim: () => void;
    canClaim: boolean;
    isClaimPending: boolean;
    isClaimConfirming: boolean;
}) {
    return (
        <div className="flex justify-between items-center border-b border-gray-800 pb-6">
            <div>
                <h1 className="text-3xl font-bold tracking-tight text-white">Dashboard</h1>
                <p className="text-gray-400 text-sm">Manage your Aurum positions</p>
            </div>

            <div className="flex items-center gap-2">
                {isAnyTxPending && (
                    <div className="flex items-center text-yellow-400">
                        <LoadingSpinner />
                        <span className="ml-2 text-sm">{pendingAction}</span>
                    </div>
                )}

                <button
                    onClick={onRefresh}
                    className="px-4 py-2 bg-gray-800 hover:bg-gray-700 rounded-lg text-sm transition"
                >
                    Refresh Data
                </button>

                <button
                    onClick={onClaim}
                    disabled={!canClaim || isClaimPending || isClaimConfirming}
                    className="px-4 py-2 bg-yellow-600 hover:bg-yellow-700 rounded-lg text-sm"
                >
                    Get Test AUR
                </button>
            </div>
        </div>
    )
}