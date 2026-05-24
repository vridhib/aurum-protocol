"use client";
import { AURUM_ENGINE_ADDRESS, AUR_GOLD_ADDRESS, AURUM_AUSD_ADDRESS } from "@/config/constants";
import { useProtocolData } from "@/hooks/useProtocolData";
import { formatEtherAsPercent, formatPercent, formatStablecoin, formatUsd } from "@/utils/helperFunctions";
import { Coins, Gauge, ShieldAlert, Landmark, PiggyBank, Zap } from "lucide-react";
import { StatCard } from "../StatCard";
import { FeatureCard } from "./FeatureCard";
import { LinkCard } from "./LinkCard";
import { GoldHero } from "../GoldHero";

/*
 * About page component for the Aurum Protocol frontend.
 *
 * Displays the protocol's total collateral value in USD, total debt, utilization, 
 * and treasury balance as well as describes a high level overview of the protocol's
 * features and design choices, with the relevant links showcased at the bottom.
 */
export default function AboutPage() {
  const { collaterals, totalCollateralValueInUsd, totalDebt, utilization, treasuryBalance } = useProtocolData();

  return (
    <div className="max-w-7xl mx-auto p-6 space-y-20">
      {/* Gold Hero Banner */}
      <GoldHero
        title="Aurum Protocol"
        subtitle="A decentralized stablecoin backed by AUR (tokenized gold) and ETH: designed for capital efficiency, transparency, and resilience."
      />

      {/* Stats Bar */}
      <section className="grid grid-cols-2 md:grid-cols-4 gap-4 -mt-8">
        <StatCard title="Total Collateral" value={formatUsd(totalCollateralValueInUsd || 0n)} />
        <StatCard title="Total Debt" value={formatStablecoin(totalDebt || 0n)} />
        <StatCard title="Utilization" value={formatPercent(utilization || 0)} />
        <StatCard title="Treasury" value={formatStablecoin(treasuryBalance || 0n)} />
      </section>

      {/* Protocol Overview */}
      <section className="space-y-4 gold-border">
        <h2 className="section-heading">What is Aurum?</h2>
        <p className="leading-relaxed">
          Aurum is a decentralized, over-collateralized stablecoin system backed by tokenized gold (AUR) and WETH. Users can deposit these assets to mint Aurum USD (AUSD), a stablecoin pegged to $1 USD. The protocol is designed for capital efficiency, taking advantage of gold's historical stability while maintaining robust per-collateral risk management for both collateral types.
        </p>
        <p className="leading-relaxed">
          This is the V2-beta release, which adds multi-collateral support, automatic per-collateral debt allocation, a dynamic interest rate model, volatility-based LTVs, a dynamic close factor, a treasury with bad-debt protection, Chainlink Automation, and a savings contract.
        </p>
      </section>

      {/* Key Features */}
      <section className="space-y-6 gold-border">
        <h2 className="section-heading">Key Features</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <FeatureCard
            icon={Coins}
            title="Multi-Collateral Support"
            description="Deposit both AUR and WETH as collateral. Each asset has its own LTV, debt ceiling, and risk parameters."
          />
          <FeatureCard
            icon={Gauge}
            title="Dynamic LTV"
            description="LTV ratios adjust automatically based on each collateral's annualized volatility, keeping the protocol safe in fluctuating markets."
          />
          <FeatureCard
            icon={ShieldAlert}
            title="Dynamic Close Factor"
            description="Liquidation amounts scale with the severity of a position's insolvency: fair for nearly-healthy positions and aggressive for deeply underwater positions."
          />
          <FeatureCard
            icon={Landmark}
            title="Treasury & Bad-Debt Reserve"
            description="Protocol fees accumulate in a treasury that acts as a lender of last resort, covering insolvent positions when normal liquidations cannot."
          />
          <FeatureCard
            icon={PiggyBank}
            title="Savings Yield"
            description="Deposit AUSD into the savings contract and earn yield generated from protocol fees (interest and liquidations)."
          />
          <FeatureCard
            icon={Zap}
            title="Chainlink Automation"
            description="Hourly index updates and daily LTV adjustments keep the protocol autonomous and responsive to real-time data."
          />
        </div>
      </section>

      {/* Risk Parameters (live) */}
      <section className="space-y-6 gold-border">
        <h2 className="section-heading">Current Risk Parameters</h2>
        {collaterals.length === 0 ? (
          <p className="text-gray-600">Loading on-chain parameters...</p>
        ) : (
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
              </tbody>
            </table>
          </div>
        )}

        <p className="text-gray-500 text-sm">
          * Values fetched live from the Sepolia testnet. LTV adjusts dynamically with volatility.
        </p>
      </section>


      {/* Design Philosophy */}
      <section className="space-y-4 gold-border">
        <h2 className="section-heading">Design Philosophy</h2>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div className="gold-card p-6 text-center">
            <Coins className="w-8 h-8 text-yellow-700 mx-auto mb-3" />
            <h4 className="text-lg font-semibold text-gray-900 mb-2">Capital Efficiency</h4>
            <p className="text-gray-700 text-sm">
              Gold's low volatility allows an 85% LTV, giving you more borrowing power with less collateral.
            </p>
          </div>
          <div className="gold-card p-6 text-center">
            <ShieldAlert className="w-8 h-8 text-yellow-700 mx-auto mb-3" />
            <h4 className="text-lg font-semibold text-gray-900 mb-2">User Protection</h4>
            <p className="text-gray-700 text-sm">
              Partial liquidations, slippage-protected redemptions, and a dynamic close factor prevent unnecessary wipeouts.
            </p>
          </div>
          <div className="gold-card p-6 text-center">
            <Zap className="w-8 h-8 text-yellow-700 mx-auto mb-3" />
            <h4 className="text-lg font-semibold text-gray-900 mb-2">Transparency & Autonomy</h4>
            <p className="text-gray-700 text-sm">
              All risk parameters are verifiable on-chain, and Chainlink Automation handles upkeep without central control.
            </p>
          </div>
        </div>
      </section>

      {/* Links & References */}
      <section className="space-y-4 gold-border">
        <h2 className="section-heading">Links & References</h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <LinkCard
            title="GitHub Repository"
            description="Source code, tests, and documentation"
            href="https://github.com/vridhib/aurum-protocol"
          />
          <LinkCard
            title="Aurum Engine"
            description="Engine contract"
            href={`https://sepolia.etherscan.io/address/${AURUM_ENGINE_ADDRESS}#code`}
          />
          <LinkCard
            title="AurumGold (AUR)"
            description="RWA-backed gold token"
            href={`https://sepolia.etherscan.io/address/${AUR_GOLD_ADDRESS}#code`}
          />
          <LinkCard
            title="Aurum USD (AUSD)"
            description="Stablecoin contract"
            href={`https://sepolia.etherscan.io/address/${AURUM_AUSD_ADDRESS}#code`}
          />
          <LinkCard
            title="V1 Release"
            description="Original single-collateral version"
            href="https://github.com/vridhib/aurum-protocol/releases/tag/v1.0.0"
          />
          <LinkCard
            title="Cyfrin Updraft"
            description="Advanced Foundry course's DeFi Stablecoin project that inspired this project"
            href="https://updraft.cyfrin.io/courses/advanced-foundry/develop-defi-protocol/defi-introduction"
          />
        </div>
      </section>

      {/* Disclaimer */}
      <section className="gold-border">
        <p className="text-gray-500 text-sm leading-relaxed">
          <strong>Disclaimer:</strong> This protocol is unaudited and deployed on the Sepolia testnet for demonstration purposes. It is not intended for production use with real funds. All risk parameters are configurable and should be carefully evaluated before any mainnet deployment.
        </p>
      </section>
    </div>
  );
}