import { useMemo } from "react";
import { parseEther } from "viem";

// Validates an amount string and optionally checks against a maximum (in wei).
export function useAmountValidation(amount: string, max?: bigint) {
  const isValid = useMemo(() => amount && parseFloat(amount) > 0, [amount]);
  const exceeds = useMemo(() => {
    if (!isValid || max === undefined) return false;
    else return parseEther(amount) > max;
  }, [amount, max, isValid]);
  return { isValid, exceeds };
}