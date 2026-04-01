export function BurnCard({
    burnAmount,
    setBurnAmount,
    onBurn,
    isPending,
    error,
    isDisabled,
    isValid,
    exceeds
}: {
    burnAmount: string;
    setBurnAmount: (v: string) => void;
    onBurn: (e: React.FormEvent<HTMLFormElement>) => void;
    isPending: boolean;
    error: string | null;
    isDisabled: boolean;
    isValid: boolean | ""
    exceeds: boolean
}) {
    return (
        <form onSubmit={onBurn} className="bg-gray-800 border border-gray-700 p-6 rounded-xl shadow-sm space-y-4">
            <h3 className="text-xl font-bold text-white">Burn AUSD</h3>
            <input
                type="number"
                placeholder="0.00"
                step="0.01"
                value={burnAmount}
                onChange={(e) => setBurnAmount(e.target.value)}
                className="w-full p-3 bg-gray-900 border border-gray-700 rounded-lg text-white focus:ring-2 focus:ring-green-500 outline-none transition"
            />
            <button
                type="submit"
                disabled={isDisabled}
                className="w-full bg-green-600 hover:bg-green-700 text-white font-bold py-3 px-4 rounded-lg transition disabled:opacity-50 disabled:cursor-not-allowed"
            >
                {isPending ? "Processing..." : "Burn"}
            </button>
            {!!burnAmount && !isValid && (<p className="text-red-500 text-sm">Please enter a valid amount greater than 0.</p>)}
            {isValid && exceeds && (<p className="text-red-500 text-sm">Cannot burn more AUSD than your minted AUSD.</p>)}
            {error && <p className="text-red-500 text-sm">{error}</p>}
        </form>
    )
}