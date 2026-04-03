import { getUserFriendlyErrorMessage } from "@/utils/helperFunctions";
import { useEffect } from "react";


/**
 * Clears action related state errors on input change.
 * @param setError The state setter function for the state error that correlates to `inputValue`
 * @param inputValue The input value that has been updated
 * 
 * When `inputValue` is updated in the UI, the previous error (if any) is also cleared in the UI.
 * 
 * @example 
 * useClearErrorOnInputChange(setMintError, mintAmount);
 */
export function useClearErrorOnInputChange(
  setError: (error: string | null) => void,
  inputValue: string
) {
  useEffect(() => {
    setError(null);
  }, [inputValue, setError]);
}


/**
 * Handles post transaction write errors by setting the given state setter to a user friendly error message.
 * @param error The error object from a wagmi write contract hook (e.g., mintWriteError).
 * @param setError The error state setter correlating to the error from `useWaitForTransactionReceipt()`
 * @example
   useWriteErrorHandler(mintWriteError, setMintError);
 */
export function useWriteErrorHandler(
  error: unknown,
  setError: (msg: string | null) => void
) {
  useEffect(() => {
    if (error) {
      setError(getUserFriendlyErrorMessage(error));
    } else {
      setError(null);
    }
  }, [error, setError]);
}