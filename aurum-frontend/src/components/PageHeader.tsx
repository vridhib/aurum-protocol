"use client";
import { useTransactionContext } from "@/context/useTransactionContext";
import { LoadingSpinner } from "./LoadingSpinner";

interface PageHeaderProps {
  heading: string;
  subtitle: string;
}

export function PageHeader({ heading, subtitle }: PageHeaderProps) {
  const { isAnyTxPending, pendingAction } = useTransactionContext();

  return (
    <>
      {/* Global Pending Banner */}
      {isAnyTxPending && (
        <div className="flex items-center justify-center text-yellow-400 py-2">
          <LoadingSpinner />
          <span className="ml-2 text-sm">{pendingAction}</span>
        </div>
      )}

      {/* Title Bar */}
      <div className="border-b border-gray-800 pb-6">
        <h1 className="text-3xl font-bold tracking-tight text-white">{heading}</h1>
        <p className="text-gray-400 text-sm">{subtitle}</p>
      </div>
    </>
  );
}