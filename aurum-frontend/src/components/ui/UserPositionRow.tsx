"use client";
import { UserPosition } from "@/hooks/useUserPositions";
import { formatHealthFactorForDisplay, formatStablecoin, formatUsd, getHealthColor, shortenAddress } from "@/utils/helperFunctions";
import { TooltipPortal } from "./TooltipPortal";
import React, { useState } from "react";
import { CopyIcon } from "lucide-react";


/**
 * Table row for a single user position.
 * 
 * Displays the user's shortened address (with a tooltip showing the full 
 * address and a copy button), total collateral value (with a per-collateral 
 * breakdown tooltip), total actual debt (with per-collateral debt allocations), 
 * and a color-coded health factor. An optional `action` prop allows injecting 
 * other columns (e.g., a 'Liquidate' button) without changing the row structure.
 * 
 * @component
 * @param {Object} props
 * @param {UserPosition} position The user position to display
 * @param {React.ReactNode} action Optional content rendered in an extra column
 * @returns A table row element.
 */
export function UserPositionRow({ position, action }: { position: UserPosition, action?: React.ReactNode }) {
  // Copy user address
  const [copiedAddress, setCopiedAddress] = useState<string | null>(null);
  const copyAddress = async (address: string) => {
    await navigator.clipboard.writeText(address);
    setCopiedAddress(address);
    setTimeout(() => setCopiedAddress(null), 2000);
  };
  
  const healthFactorColor = getHealthColor(position.healthFactor);

  // Tooltip contents (defined per user)
  const collateralTooltip = (
    <div className="text-left space-y-1">
      <div className="flex justify-between gap-4">
        <span>AUR</span><span className="font-mono">{formatUsd(position.aurCollateralUsd)}</span>
      </div>
      <div className="flex justify-between gap-4">
        <span>WETH</span><span className="font-mono">{formatUsd(position.wethCollateralUsd)}</span>
      </div>
    </div>
  );

  const debtTooltip = (
    <div className="text-left space-y-1">
      <div className="flex justify-between gap-4">
        <span>AUR</span><span className="font-mono">{formatStablecoin(position.actualAurDebt)}</span>
      </div>
      <div className="flex justify-between gap-4">
        <span>WETH</span><span className="font-mono">{formatStablecoin(position.actualWethDebt)}</span>
      </div>
    </div>
  );

  // Render UI table row
  return (
    <tr key={position.id} className="hover:bg-yellow-50/50 transition">
      {/* User Address with Copy Button */}
      <td>
        <div className="flex items-center gap-1">
          <TooltipPortal content={<span className="font-mono text-xs">{position.id}</span>}>
            <span className="cursor-help border-b border-dotted border-yellow-800/30">
              {shortenAddress(position.id)}
            </span>
          </TooltipPortal>
          <button
            onClick={(e) => { e.stopPropagation(); copyAddress(position.id); }}
            className="text-gray-400 hover:text-yellow-700 transition text-xs"
            title="Copy address"
          >
            <CopyIcon className="w-3.5 h-3.5" />
          </button>
          {copiedAddress === position.id && (
            <span className="text-green-600 text-xs ml-1 animate-pulse">Copied!</span>
          )}
        </div>
      </td>

      {/* Total Collateral with Breakdown Tooltip */}
      <td>
        <TooltipPortal content={collateralTooltip}>
          <span className="cursor-help border-b border-dotted border-yellow-800/30">
            {formatUsd(position.totalCollateralUsd)}
          </span>
        </TooltipPortal>
      </td>

      {/* Total Debt with Breakdown Tooltip */}
      <td>
        <TooltipPortal content={debtTooltip}>
          <span className="cursor-help border-b border-dotted border-yellow-800/30">
            {formatStablecoin(position.totalDebt)}
          </span>
        </TooltipPortal>
      </td>

      {/* Health Factor with Explanation Tooltip */}
      <td className={healthFactorColor}>
        <TooltipPortal content="Health Factor = Adjusted Collateral / Total Debt. Above 1.00 is safe.">
          <span className="cursor-help border-b border-dotted border-yellow-800/30">
            {formatHealthFactorForDisplay(position.healthFactor)}
          </span>
        </TooltipPortal>
      </td>
      {action && <td>{action}</td>}
    </tr>
  );
}
