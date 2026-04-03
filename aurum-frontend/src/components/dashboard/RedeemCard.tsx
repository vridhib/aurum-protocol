/**
 * Redeem section for the Aurum Protocol frontend.
 * @param redeemAmount Stores user's redeem amount.
 * @param setRedeemAmount State setter associated with `redeemAmount`.
 * @param onRedeem Function that handles the redeem action.
 * @param isPending Indicates whether the redeem action is pending.
 * @param error Stores any errors (user input or write errors) for the redeem action.
 * @param isDisabled Indicates whether the 'Redeem' button is enabled or disabled.
 * @param willBeHealthy Indicates whether a user can redeem `redeemAmount` and still have a HF >= 1.00
 * @param isValid Indicates whether `redeemAmount` falls within a valid range (>0).
 * @param exceeds Indicates whether 'redeemAmount` exceeds the user's valid range (<= deposited AUR).
 * @component
 * @returns The redeem card UI containing an input field and a button.
 */
export function RedeemCard({
  redeemAmount,
  setRedeemAmount,
  onRedeem,
  isPending,
  error,
  isDisabled,
  willBeHealthy,
  isValid,
  exceeds
}: {
  redeemAmount: string;
  setRedeemAmount: (v: string) => void;
  onRedeem: (e: React.FormEvent<HTMLFormElement>) => void;
  isPending: boolean;
  error: string | null;
  isDisabled: boolean;
  willBeHealthy: boolean;
  isValid: boolean | "";
  exceeds: boolean;
}) {
  return (
    <form onSubmit={onRedeem} className="bg-gray-800 border border-gray-700 p-6 rounded-xl shadow-sm space-y-4">
      <h3 className="text-xl font-bold text-white">Redeem AUR</h3>
      <input
        type="number"
        placeholder="0.00"
        step="0.01"
        value={redeemAmount}
        onChange={(e) => setRedeemAmount(e.target.value)}
        className="w-full p-3 bg-gray-900 border border-gray-700 rounded-lg text-white focus:ring-2 focus:ring-blue-500 outline-none transition"
      />
      <button
        type="submit"
        disabled={isDisabled}
        className="w-full bg-blue-600 hover:bg-blue-700 text-white font-bold py-3 px-4 rounded-lg transition disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {isPending ? "Processing..." : "Redeem"}
      </button>
      {!!redeemAmount && !isValid && (<p className="text-red-500 text-sm">Please enter a valid amount greater than 0.</p>)}
      {isValid && exceeds && (<p className="text-red-500 text-sm">Cannot redeem more than your deposited collateral.</p>)}
      {!willBeHealthy && (<p className="text-red-500 text-sm">Redeeming this amount would put your health factor below 1.</p>)}
      {error && <p className="text-red-500 text-sm">{error}</p>}
    </form>
  )
}