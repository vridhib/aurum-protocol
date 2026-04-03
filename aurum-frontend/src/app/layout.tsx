"use client";
import "@rainbow-me/rainbowkit/styles.css";
import "./globals.css";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider } from "wagmi";
import { RainbowKitProvider, darkTheme } from "@rainbow-me/rainbowkit";
import { config } from "../lib/wagmi";
import { ApolloProvider } from "@apollo/client/react";
import client from "@/lib/apollo-client";
import { NavBar } from "@/components/NavBar";


const queryClient = new QueryClient();

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider theme={darkTheme()}>
          <html lang="en">
            <body className="bg-gray-900 text-white">
              <ApolloProvider client={client}>
                <NavBar />
                <main className="min-h-screen flex flex-col">
                  {children}
                </main>
              </ApolloProvider>
            </body>
          </html>
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}