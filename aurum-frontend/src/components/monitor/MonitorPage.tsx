"use client";

import { gql } from "@apollo/client";
import { useQuery } from "@apollo/client/react";
import { formatEther } from "viem";
import { useProtocolData } from "@/hooks/useProtocolData";
import { calculateProjectedHealthFactor, getHealthColor, shortenAddress } from "@/utils/helperFunctions";
import { TypedDocumentNode } from "@apollo/client";
import { StatCard } from "@/components/dashboard/StatCard";


// Define the shape of the data returned by the subgraph
type ProtocolStats = {
    protocol: {
        totalCollateral: string;
        totalDebt: string;
        totalUsers: number;
    };
    users: Array<{
        id: string;
        collateral: string;
        debt: string;
    }>;
};

// Define variables (none)
type ProtocolStatsVariables = Record<string, never>;

// GraphQL query
const GET_PROTOCOL_STATS: TypedDocumentNode<
    ProtocolStats,
    ProtocolStatsVariables
> = gql`
  query GetProtocolStats {
    protocol(id: "1") {
      totalCollateral
      totalDebt
      totalUsers
    }
    users(first: 100, orderBy: collateral, orderDirection: desc) {
      id
      collateral
      debt
    }
  }
`;

export default function MonitorPage() {
    const { loading: queryLoading, error: queryError, data } = useQuery(GET_PROTOCOL_STATS);
    const { pricePerAur, isLoading: priceLoading } = useProtocolData();

    const isLoading = queryLoading || priceLoading;

    if (isLoading) {
        return (
            <div className="flex justify-center items-center h-64">
                <div className="text-gray-400">Loading protocol data...</div>
            </div>
        );
    }

    if (queryError) {
        return (
            <div className="flex justify-center items-center h-64">
                <div className="text-red-500">Error loading data: {queryError.message}</div>
            </div>
        );
    }

    const { protocol, users } = data!;
    const totalCollateral = BigInt(protocol.totalCollateral);
    const totalDebt = BigInt(protocol.totalDebt);
    const totalUsers = protocol.totalUsers;

    return (
        <div className="max-w-7xl mx-auto p-6 space-y-8">
            <h1 className="text-3xl font-bold text-white">Protocol Monitor</h1>

            {/* Stats Cards */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                <StatCard
                    title="Total Collateral"
                    value={`${formatEther(totalCollateral)} AUR`}
                />
                <StatCard
                    title="Total Debt"
                    value={`${formatEther(totalDebt)} AUSD`}
                />
                <StatCard
                    title="Total Users"
                    value={totalUsers.toString()}
                />
            </div>

            {/* User Table */}
            <div className="bg-gray-800 border border-gray-700 rounded-xl overflow-hidden">
                <div className="overflow-x-auto">
                    <table className="min-w-full divide-y divide-gray-700">
                        <thead className="bg-gray-900">
                            <tr>
                                <th className="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                                    User
                                </th>
                                <th className="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                                    Collateral (AUR)
                                </th>
                                <th className="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                                    Debt (AUSD)
                                </th>
                                <th className="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                                    Health Factor
                                </th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-gray-700">
                            {users.map((user: any) => {
                                const collateralWei = BigInt(user.collateral);
                                const debtWei = BigInt(user.debt);
                                const healthFactor = calculateProjectedHealthFactor(collateralWei, debtWei, (pricePerAur || 0n));
                                const healthColor = getHealthColor(healthFactor);
                                const healthDisplay = Number(formatEther(healthFactor || 0n)).toFixed(2);

                                return (
                                    <tr key={user.id} className="hover:bg-gray-700/50 transition">
                                        <td className="px-6 py-4 whitespace-nowrap text-sm font-mono text-white">
                                            {shortenAddress(user.id)}
                                        </td>
                                        <td className="px-6 py-4 whitespace-nowrap text-sm text-white">
                                            {formatEther(collateralWei)}
                                        </td>
                                        <td className="px-6 py-4 whitespace-nowrap text-sm text-white">
                                            {formatEther(debtWei)}
                                        </td>
                                        <td className={`px-6 py-4 whitespace-nowrap text-sm font-medium ${healthColor}`}>
                                            {healthDisplay}
                                        </td>
                                    </tr>
                                );
                            })}
                        </tbody>
                    </table>
                </div>
                {users.length === 0 && (
                    <div className="text-center py-8 text-gray-400">No users yet.</div>
                )}
            </div>
        </div>
    );
}