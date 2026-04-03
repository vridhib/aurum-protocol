"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { ConnectButton } from "@rainbow-me/rainbowkit";


/**
 * Navigation bar for the Aurum Protocol frontend.
 *
 * Renders the logo, navigation links (dashboard and monitor), and the wallet
 * connection button (via RainbowKit). The active link is highlighted based on
 * the current route.
 *
 * @component
 * @returns The navigation bar.
 */
export function NavBar() {
    const pathname = usePathname();
    return (
        <nav className="border-b border-gray-800 bg-gray-900/50 backdrop-blur-md sticky top-0 z-10">
            <div className="max-w-7x-1 max-auto px-6 h-16 flex items-center justify-between">
                <div className="flex items-center gap-8">
                    <div className="flex items-center gap-2">
                        <div className="w-8 h-8 bg-gradient-to-tr from-yellow-500 to-amber-600 rounded-lg"></div>
                        <span className="text-xl font-bold tracking-tighter text-white">AURUM</span>
                    </div>
                    <div className="flex gap-4">
                        <Link
                            href="/"
                            className={`text-sm transition ${pathname === "/" ? "text-white" : "text-gray-400 hover:text-white"}`}
                        >
                            Dashboard
                        </Link>
                        <Link
                            href="/monitor"
                            className={`text-sm transition ${pathname === "/monitor" ? "text-white" : "text-gray-400 hover:text-white"}`}
                        >
                            Monitor
                        </Link>
                    </div>
                </div>
                <ConnectButton />
            </div>
        </nav>
    );
}