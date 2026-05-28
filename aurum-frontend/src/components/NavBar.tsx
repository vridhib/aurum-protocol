"use client";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { NavLink } from "./NavLink";


/**
 * Navigation bar for the Aurum Protocol frontend.
 *
 * Renders the logo, navigation links (dashboard, monitor, faucet, savings, 
 * and about), and the wallet connection button (via RainbowKit). The active
 * link is highlighted based on the current route.
 *
 * @component
 * @returns The navigation bar.
 */
export function NavBar() {
  return (
    <nav className="border-b border-yellow-600 bg-[#eccd7d] backdrop-blur-md sticky top-0 z-10">
      <div className="max-w-7x-1 max-auto px-6 h-16 flex items-center justify-between">
        <div className="flex items-center gap-8">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 bg-gradient-to-tr from-yellow-500 to-amber-600 rounded-lg"></div>
            <span className="text-xl font-bold tracking-tighter text-white">AURUM</span>
          </div>
          <div className="flex gap-4">
            <NavLink href="/">Dashboard</NavLink>
            <NavLink href="/liquidation">Liquidation</NavLink>
            <NavLink href="/monitor">Monitor</NavLink>
            <NavLink href="/faucet">Claim One-Time AUR</NavLink>
            <NavLink href="/savings">Savings</NavLink>
            <NavLink href="/about">About</NavLink>
          </div>
        </div>
        <ConnectButton />
      </div>
    </nav>
  );
}