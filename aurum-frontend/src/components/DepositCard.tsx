export function DepositCard({
    depositAmount,
    setDepositAmount,
    onDeposit,
    isPending,
    error,
    isDisabled,
    isValid
}: {
    depositAmount: string;
    setDepositAmount: (v: string) => void;
    onDeposit: (e: React.FormEvent<HTMLFormElement>) => void;
    isPending: boolean;
    error: string | null;
    isDisabled: boolean;
    isValid: boolean | "";
}) {
    return (
        <form onSubmit={onDeposit} className="bg-gray-800 border border-gray-700 p-6 rounded-xl shadow-sm space-y-4">
            <h3 className="text-xl font-bold text-white">Deposit AUR</h3>
            <input
                type="number"
                placeholder="0.00"
                step="0.01"
                value={depositAmount}
                onChange={(e) => setDepositAmount(e.target.value)}
                className="w-full p-3 bg-gray-900 border border-gray-700 rounded-lg text-white focus:ring-2 focus:ring-blue-500 outline-none transition"
            />
            <button
                type="submit"
                disabled={isDisabled}
                className="w-full bg-blue-600 hover:bg-blue-700 text-white font-bold py-3 px-4 rounded-lg transition disabled:opacity-50 disabled:cursor-not-allowed"
            >
                {isPending ? "Processing..." : "Deposit"}
            </button>
            {!!depositAmount && !isValid && (<p className="text-red-500 text-sm">Please enter a valid amount greater than 0.</p>)}
            {error && <p className="text-red-500 text-sm">{error}</p>}
        </form>
    )
}