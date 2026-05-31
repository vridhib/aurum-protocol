interface CollateralSelectorProps {
  tokens: { address: `0x${string}`; symbol: string; ltv: number }[];
  selectedIndex: number;
  onChange: (index: number) => void;
}

/**
 * Collateral selector radio buttons for the Aurum frontend.
 * 
 * Renders a row of slim, gold-bronze themed buttons (one for each collateral token). 
 * The active token is highlighted and displays the current LTV. Used in the Dashboard 
 * and Liquidation pages to let users choose which collateral they are acting on. 
 * 
 * @component
 * @param {CollateralSelectorProps} props 
 * @param {CollateralSelectorProps['tokens']} props.tokens Available collateral tokens with their LTV.
 * @param {number} props.selectedIndex Index of the currently selected token.
 * @param {CollateralSelectorProps['onChange']} onChange Callback when a token is selected.
 * @returns A flex container with radio-style collateral buttons.
 */
export function CollateralSelector({ tokens, selectedIndex, onChange }: CollateralSelectorProps) {
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