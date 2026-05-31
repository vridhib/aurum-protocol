"use client";
import { useGoldEvents } from "@/hooks/useGoldEvents";
import { shortenAddress } from "@/utils/helperFunctions";
import { useState } from "react";
import { isAddress } from "viem";
import { ReserveSnapshot } from "./ReserveSnapshot";


/**
 * Gold Ledger page for the Aurum frontend.
 * 
 * Provides a complete audit trail of the physical gold backing the AUR token.
 * It displays:
 *  - A reserve snapshot card showing the current AUR supply, recorded gold ounces, 
 *    and an indicator showing whether the reserves are balanced.
 * - A filter bar that allows the user to filter events by type (`GoldDeposited`, 
 *   `GoldWithdrawn`, and `GoldLoss`) and by user address. 
 * - An event table that lists all matching events with their timestamp, type, user, 
 *   description, and a link to the Sepolia transaction. 
 * 
 * All data is fetched from the Aurum subgraph via the {@link useGoldEvents} hook.
 * 
 * @component
 * @returns The rendered Gold Ledger page with a reserve snapshot, search/filter 
 *          functionality, and event table.
 */
export default function GoldLedger() {
  const EVENT_TYPES = ["GoldDeposited", "GoldWithdrawn", "GoldLoss"];

  const [selectedTypes, setSelectedTypes] = useState<string[]>([]);
  const [inputAddress, setInputAddress] = useState("");
  const [filterAddress, setFilterAddress] = useState("");

  const { events, loading, error } = useGoldEvents(filterAddress);


  // Filter by selected event types
  const filteredEvents = selectedTypes.length > 0
    ? events.filter(e => selectedTypes.includes(e.eventType))
    : events;

  // Trim inputAddress and apply filter
  const handleApplyFilter = () => {
    const trimmedAddress = inputAddress.trim();
    if (trimmedAddress === "" || isAddress(trimmedAddress)) {
      setFilterAddress(trimmedAddress);
    }
  };

  return (
    <div className="ml-12 mr-12 space-y-6">
      {/* Header */}
      <div className="space-y-2">
        <h1 className="text-4xl font-bold text-yellow-800 mt-6">AurumGold Ledger</h1>
        <p className="text-yellow-700/70 text-sm">Immutable on-chain record of all gold deposits, withdrawals, and loss reports</p>
        <hr className="gold-border"></hr>
      </div>

      {/* Reserves */}
      <ReserveSnapshot />

      {/* Filter Bar */}
      <div className="flex flex-col gap-4">
        <div className="flex flex-col">
          <label className="text-yellow-900 text-sm uppercase tracking-wider font-semibold mb-1">Event Types</label>
          <div className="flex flex-wrap gap-2">
            {EVENT_TYPES.map(type => (
              <button
                key={type}
                onClick={() => setSelectedTypes(prev =>
                  prev.includes(type) ? prev.filter(t => t !== type) : [...prev, type]
                )}
                className={`px-2 py-1 rounded text-sm ${
                  selectedTypes.includes(type)
                    ? "bg-yellow-600 text-white border-yellow-600"
                    : "bg-white border-yellow-800/20 text-gray-700 hover:bg-yellow-50"
                }`}
              >
                {type}
              </button>
            ))}
          </div>
        </div>

        <div className="flex flex-col">
          <label className="text-yellow-900 text-sm uppercase trackin-wider font-semibold mb-1">User Address</label>
          <div className="flex items-center gap-2">
            <input 
              type="text"
              placeholder="0xabc..."
              value={inputAddress}
              onChange={e => setInputAddress(e.target.value)}
              className="form-input h-[50px]"
            />
            <button 
              onClick={handleApplyFilter} 
              className="inline-flex items-center gap-2 px-6 py-3 bg-yellow-600/30 border border-yellow-600/40 text-yellow-800 rounded-lg hover:bg-yellow-800/20 hover:border-yellow-500 transition shadow-lg shadow-yellow-900/10"
            >
              Filter 
            </button>
          </div>
        </div>
      </div>

      {/* Table */}
      {loading && <p className="text-gray-600">Loading events...</p>}
      {error && <p className="text-red-500">Error: {error.message}</p>}
      {!loading && !error && (
        <div className="table-wrapper">
          <table className="gold-table">
            <thead>
              <tr>
                <th>Timestamp</th>
                <th>Event Type</th>
                <th>User</th>
                <th>Details</th>
                <th>Transaction</th>
              </tr>
            </thead>
            <tbody>
              {filteredEvents.map(event => (
                <tr key={event.id}>
                  <td className="whitespace-nowrap">{new Date(event.timestamp * 1000).toLocaleString()}</td>
                  <td>{event.eventType}</td>
                  <td>{shortenAddress(event.user)}</td>
                  <td>{event.details}</td>
                  <td>
                    <a
                      href={`https://sepolia.etherscan.io/tx/${event.txHash}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-gray-700 hover:underline"
                    >
                      {shortenAddress(event.txHash)}
                    </a>
                  </td>
                </tr>
              ))}
              {filteredEvents.length === 0 && (
                <tr>
                  <td colSpan={5} className="text-center text-gray-500">No gold events found.</td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}