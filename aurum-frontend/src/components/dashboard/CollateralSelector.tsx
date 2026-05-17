export function CollateralSelector({tokens, selectedIndex, onChange}: {
  tokens: { address: `0x${string}`; symbol: string; ltv: number }[];
  selectedIndex: number;
  onChange: (index: number) => void;
}) {
  return (
    <div className="flex gap-4 mb-4">
      {tokens.map((token, index) => (
        <label
          key={token.address}
          className={`flex-1 p-4 rounded-lg cursor-pointer border-2 transition ${
            index === selectedIndex
              ? "border-yellow-500 bg-gray-700"
              : "border-gray-600 bg-gray-800"
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
          <div className="text-center">
            <div className="text-lg font-bold text-white">{token.symbol}</div>
            <div className="text-sm text-gray-400">LTV {token.ltv}%</div>
          </div>
        </label>
      ))}
    </div>
  );
}