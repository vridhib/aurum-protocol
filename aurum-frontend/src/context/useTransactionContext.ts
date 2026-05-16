import { useContext } from "react";
import { TransactionContext } from "./TransactionContext";

export function useTransactionContext() {
  return useContext(TransactionContext);
}