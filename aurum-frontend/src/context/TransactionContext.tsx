"use client";

import { createContext } from "react";


export const TransactionContext = createContext({
  isAnyTxPending: false,
  pendingAction: null as string | null,
  setPendingAction: (msg: string | null) => {}
});