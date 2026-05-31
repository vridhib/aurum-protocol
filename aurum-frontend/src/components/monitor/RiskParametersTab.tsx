import { CollateralData } from "@/hooks/useProtocolData";
import { formatEtherAsPercent } from "@/utils/helperFunctions";


/**
 * Risk Parameters tab for the Protocol Monitor.
 *
 * Renders a live table of per‑collateral risk settings fetched from the
 * `useProtocolData` hook. Columns shown include token, LTV, base LTV, 
 * min LTV, debt ceiling, baseline volatility, and active status.
 *
 * @component
 * @param {Object} props
 * @param {CollateralData[]} props.collaterals Collateral data from the protocol.
 * @returns The Risk Parameters tab for the Monitor page.
 */
export function RiskParametersTab({ collaterals }: {collaterals: CollateralData[]}) {
  return (
    <div className="table-wrapper">
      <table className="gold-table">
        <thead>
          <tr>
            <th>Parameter</th>
            {collaterals.map((c) => (
              <th key={c.symbol}>{c.symbol}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {/* LTV */}
          <tr>
            <td className="row-header">LTV</td>
            {collaterals.map((c) => (
              <td key={c.symbol}>{c.ltv.toString()}%</td>
            ))}
          </tr>
          {/* Base LTV */}
          <tr>
            <td className="row-header">Base LTV</td>
            {collaterals.map((c) => (
              <td key={c.symbol}>{c.baseLtv.toString()}%</td>
            ))}
          </tr>
          {/* Min LTV */}
          <tr>
            <td className="row-header">Min LTV</td>
            {collaterals.map((c) => (
              <td key={c.symbol}>{c.minLtv.toString()}%</td>
            ))}
          </tr>
          {/* Debt Ceiling */}
          <tr>
            <td className="row-header">Debt Ceiling</td>
            {collaterals.map((c) => (
              <td key={c.symbol}>${(Number(c.debtCeiling) / 1e18).toLocaleString()}</td>
            ))}
          </tr>
          {/* Baseline Volatility */}
          <tr>
            <td className="row-header">Baseline Volatility</td>
            {collaterals.map((c) => (
              <td key={c.symbol}>
                {(Number(c.baselineVolatility) / 1e16).toFixed(0)}%
              </td>
            ))}
          </tr>
          {/* Min Close Factor */}
          <tr>
            <td className="row-header">Min Close Factor</td>
            {collaterals.map((c) => (
              <td key={c.symbol}>
                {formatEtherAsPercent(c.minCloseFactor)}
              </td>
            ))}
          </tr>
          {/* Max Close Factor */}
          <tr>
            <td className="row-header">Max Close Factor</td>
            {collaterals.map((c) => (
              <td key={c.symbol}>
                {formatEtherAsPercent(c.maxCloseFactor)}
              </td>
            ))}
          </tr>
          {/* Active Status */}
          <tr>
            <td className="row-header">Active Status</td>
            {collaterals.map((c) => (
              <td key={c.symbol}>
                {c.isActive ? "Active" : "Inactive"}
              </td>
            ))}
          </tr>
        </tbody>
      </table>
    </div>
  );
}