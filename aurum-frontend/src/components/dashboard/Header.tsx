"use client"
import { useRouter } from "next/navigation";
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
  const router = useRouter();

  return (
    <div className="flex justify-between items-center border-b border-yellow-800/20 pb-4 mb-16">
      <div>
        <h1 className="text-3xl font-bold text-yellow-800">Dashboard</h1>
        <p className="text-yellow-700/70 text-sm">Manage your Aurum positions</p>
      </div>
      <div className="flex items-center gap-3">
        {isAnyTxPending && (
          <div className="flex items-center text-yellow-600">
            <LoadingSpinner />
            <span className="ml-2 text-sm">{pendingAction}</span>
          </div>
        )}
        <button
          onClick={onRefresh}
          className="px-4 py-2 bg-[#fff0b3] text-yellow-900 rounded-lg text-sm hover:bg-yellow-200 transition"
        >
          Refresh Data
        </button>
        <button
          onClick={() => router.push("/about")}
          className="px-4 py-2 border border-yellow-600/40 text-yellow-800 rounded-full text-sm hover:bg-yellow-600/10 transition"
        >
          Read About
        </button>
      </div>
    </div>
  );
}