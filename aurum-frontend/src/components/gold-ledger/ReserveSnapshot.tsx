import aurumGoldJson from "@/abis/AurumGold.json";
import { AUR_GOLD_ADDRESS } from "@/config/constants";
import { formatWeiAmount } from "@/utils/helperFunctions";
import { useReadContract } from "wagmi";


/**
 * Reserve snapshot card used in the GoldLedger component.
 * 
 * Displays live on-chain data about the AurumGold contract:
 *  - AUR Minted: the total supply of AUR tokens.
 *  - Gold Ounces: the total gold ounces in the vault recorded by the custodian.
 *  - Reserve Status: a green/red indicator showing whether the on-chain token 
 *    supply exactly matches the off-chain gold reserves (i.e., `totalSupply() 
 *    == getTotalGoldOUnces()`).
 * 
 * This card is intended to be placed at the top of the {@link GoldLedger} page, 
 * just above the event table.
 * 
 * @component
 * @returns Reserve status UI card with token and ounce amounts as well as a
 *          reserve status balanced indicator.
 */
export function ReserveSnapshot() {
  // Read total supply of AUR tokens
  const { data: totalSupply } = useReadContract({
    address: AUR_GOLD_ADDRESS,
    abi: aurumGoldJson.abi,
    functionName: "totalSupply",
  }) as { data: bigint | undefined };

  // Read total gold ounces recorded by custodian
  const { data: totalOunces } = useReadContract({
    address: AUR_GOLD_ADDRESS,
    abi: aurumGoldJson.abi,
    functionName: "getTotalGoldOunces",
  }) as { data: bigint | undefined };

  const supply = totalSupply ?? 0n;
  const ounces = totalOunces ?? 0n;
  const isBalanced = supply === ounces;

  return (
    <div className="gold-card p-6 space-y-3">
      <h3 className="text-2xl font-bold text-yellow-700">Reserve Status</h3>
      <div className="flex flex-wrap items-center gap-6">
        {/* Minted Tokens */}
        <div>
          <p className="text-sm uppercase tracking-wider text-yellow-900/70 font-semibold">AUR Minted</p>
          <p className="text-2xl font-bold text-yellow-800">
            {formatWeiAmount(supply)}
          </p>
        </div>

        {/* Gold Ounces */}
        <div>
          <p className="text-sm uppercase tracking-wider text-yellow-900/70 font-semibold">Gold Ounces</p>
          <p className="text-2xl font-bold text-yellow-800">
            {(formatWeiAmount(ounces))}
          </p>
        </div>

        {/* Balanced Indicator */}
        <div className="flex items-center gap-4 ml-auto">
          <span
            className={`w-3 h-3 rounded-full ${
              isBalanced ? "bg-green-600" : "bg-red-600"
            }`}
          />
          <span className="text-sm font-semibold text-gray-800">
            {isBalanced ? "Balanced" : "Unbalanced"}
          </span>
        </div>
      </div>

      <p className="text-xs text-gray-500 mt-2">
        The total AUR minted must equal the gold ounces held in the vault.
      </p>
    </div>
  );
}