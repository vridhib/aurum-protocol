import { getUserFriendlyErrorMessage } from "@/utils/helperFunctions";
import { useEffect } from "react";

// Clears action related state errors on input change
export function useClearErrorOnInputChange(
  setError: (error: string | null) => void,
  inputValue: string
) {
  useEffect(() => {
    setError(null);
  }, [inputValue, setError]);
}

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