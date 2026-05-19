import { LoadingSpinner } from "../LoadingSpinner";
import { useTransactionContext } from "@/context/useTransactionContext";

/**
 * Header section for the dashboard of the Aurum Protocol frontend. 
 * @param onRefresh Function that refreshes data.
 * @component
 * @returns A header section for the main dashboard.
 */
export function Header({ onRefresh }: { onRefresh: () => void }) {
    const { isAnyTxPending, pendingAction } = useTransactionContext();

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
            </div>
        </div>
    )
}