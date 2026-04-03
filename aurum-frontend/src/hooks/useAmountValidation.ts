import { useMemo } from "react";
import { parseEther } from "viem";


/**
 * Validates an amount string and optionally checks against a maximum (in wei).
 * @param amount Amount string to validate.
 * @param max Optional maximum value in wei. that `amount` is allowed to be. If provided, the function checks whether the parsed amount exceeds this limit.
 * @returns An object containing:
 * - `isValid` (`boolean`) – `true` if the amount is a valid positive number.
 * - `exceeds` (`boolean`) – `true` if the amount exceeds `max` (only relevant when `max` is provided and `isValid` is `true`).
 */
export function useAmountValidation(amount: string, max?: bigint) {
  const isValid = useMemo(() => amount && parseFloat(amount) > 0, [amount]);
  const exceeds = useMemo(() => {
    if (!isValid || max === undefined) return false;
    else return parseEther(amount) > max;
  }, [amount, max, isValid]);
  return { isValid, exceeds };
}