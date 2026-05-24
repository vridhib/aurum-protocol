export function CollateralSelector({ 
  tokens, 
  selectedIndex, 
  onChange 
}: {
  tokens: { address: `0x${string}`; symbol: string; ltv: number }[];
  selectedIndex: number;
  onChange: (index: number) => void;
}) {
  return (
    <div className="flex gap-4 mb-3">
      {tokens.map((token, index) => (
        <label
          key={token.address}
          className={`px-4 py-2 gap-1.5 rounded-xl border-2 cursor-pointer transition-all duration-200 flex items-center ${
            index === selectedIndex
              ? "border-yellow-600 bg-[#F2E0C8] shadow-md shadow-yellow-900/10"
              : "border-yellow-800/20 bg-[#fdf5e6] hover:border-yellow-400/50 hover:bg-[#F2E0C8]/50"
          }`}
        >
          <input
            type="radio"
            name="collateral"
            value={index}
            checked={index === selectedIndex}
            onChange={() => onChange(index)}
            className="hidden"
          />

          {/* Radio dot */}
          <span
            className={`w-3 h-3 rounded-full border-2 flex items-center justify-center ${
              index === selectedIndex
                ? "border-yellow-600 bg-yellow-600"
                : "border-yellow-800/40 bg-transparent"
            }`}
          >
            {index === selectedIndex && (
              <span className="w-2 h-2 rounded-full bg-yellow-600" />
            )}
          </span>

          {/* Text */}
          <span className="text-lg font-bold text-gray-900">
            {token.symbol}:
          </span>
          <span className="text-sm text-gray-600">
            LTV {token.ltv}%
          </span>
        </label>
      ))}
    </div>
  );
}