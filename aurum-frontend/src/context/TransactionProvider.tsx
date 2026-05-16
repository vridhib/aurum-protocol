"use client";

import { useState, useMemo, ReactNode } from "react";
import { TransactionContext } from "./TransactionContext";

export function TransactionProvider({ children }: { children: ReactNode }) {
    const [pendingAction, setPendingAction] = useState<string | null>(null);

    const isAnyTxPending = useMemo(() => pendingAction !== null, [pendingAction]);

    return (
        <TransactionContext.Provider value={{ isAnyTxPending, pendingAction, setPendingAction}}>
            {children}
        </TransactionContext.Provider>
    )
}