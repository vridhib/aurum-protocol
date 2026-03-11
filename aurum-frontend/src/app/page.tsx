"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";
import Dashboard from "../components/Dashboard";

export default function Home() {
  return (
    <div className="flex flex-col min-h-screen">
      <nav className="border-b border-gray-800 bg-gray-900/50 backdrop-blur-md sticky top-0 z-10">
        <div className="max-w-7xl mx-auto px-6 h-16 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 bg-gradient-to-tr from-yellow-500 to-amber-600 rounded-lg"></div>
            <span className="text-xl font-bold tracking-tighter text-white">AURUM</span>
          </div>
          <ConnectButton />
        </div>
      </nav>

      <Dashboard />
    </div>
  );
}