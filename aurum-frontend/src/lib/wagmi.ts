"use client";

import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { sepolia } from "wagmi/chains";

export const config = getDefaultConfig({
  appName: "Aurum Protocol",
  projectId: "10fe43b9b1e65a5aa52fcc4718b054d5",
  chains: [sepolia],
  ssr: true,
});