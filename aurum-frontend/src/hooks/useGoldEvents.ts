import { formatWeiAmount } from "@/utils/helperFunctions";
import { gql } from "@apollo/client";
import { useQuery } from "@apollo/client/react";
import { useMemo } from "react";


// Declare types
export interface GoldEvent {
  id: string;
  eventType: "GoldDeposited" | "GoldWithdrawn" | "GoldLoss";
  timestamp: number;
  user: string;         // deposited to/withdrawn from/reported by
  amount: bigint        // raw wei amount (tokens or ounces)
  details: string;      // human readable description
  txHash: string;
  block: string;
}

// Define the shape of the combined GraphQL response
interface GoldEventsData {
  goldDepositeds: {
    id: string;
    to: string;
    ouncesDeposited: string;
    tokensMinted: string;
    block: string;
    timestamp: string;
  }[];
  goldWithdrawns: {
    id: string;
    to: string;
    ouncesWithdrawn: string;
    tokensBurned: string;
    block: string;
    timestamp: string;
  }[];
  goldLosses: {
    id: string;
    reporter: string;
    ouncesLost: string;
    block: string;
    timestamp: string
  }[];
}

// Query for when user is not specified
const GET_ALL_GOLD_EVENTS = gql`
  query GetAllGoldEvents($first: Int!, $skip: Int!) {
    goldDepositeds(first: $first, skip: $skip, orderBy: timestamp, orderDirection: desc) {
      id
      to
      ouncesDeposited
      tokensMinted
      block
      timestamp
    }
    goldWithdrawns(first: $first, skip: $skip, orderBy: timestamp, orderDirection: desc) {
      id
      to
      ouncesWithdrawn
      tokensBurned
      block
      timestamp
    }
    goldLosses(first: $first, skip: $skip, orderBy: timestamp, orderDirection: desc) {
      id
      reporter
      ouncesLost
      block
      timestamp
    }
  }
`;

// Query for when user is specified
const GET_USER_GOLD_EVENTS = gql`
  query GetUserGoldEvents($first: Int!, $skip: Int!, $user: String) {
    goldDepositeds(first: $first, skip: $skip, where: { to: $user }, orderBy: timestamp, orderDirection: desc) {
      id
      to
      ouncesDeposited
      tokensMinted
      block
      timestamp
    }
    goldWithdrawns(first: $first, skip: $skip, where: { to: $user }, orderBy: timestamp, orderDirection: desc) {
      id
      to
      ouncesWithdrawn
      tokensBurned
      block
      timestamp
    }
    goldLosses(first: $first, skip: $skip, where: { reporter: $user }, orderBy: timestamp, orderDirection: desc) {
      id
      reporter
      ouncesLost
      block
      timestamp
    }
  }
`;

/**
 * Fetches and merges gold-related events from the Aurum subgraph. The 
 * subgraph contains three separate immutable event entities corresponding 
 * to the AurumGold contract: `GoldDeposited`, `GoldWithdrawn`, and `GoldLoss`. 
 * This hook queries all three entities in a single call and merges then into 
 * a unified array of {@link GoldEvent} objects, sorted by most recent.
 * 
 * @param {string} userAddress Optional Ethereum address to filter events by.
 * If provided, the returned events are filtered on the subgraph side to only 
 * include those where the user was the recipient, withdrawer, or reporter.
 *  
 * @returns {Object} An object containing:
 *  - `events` (`GoldEvent[]`): merged and sorted gold events.
 *  - `loading` (`boolean`): whether the initial fetch is in progress.
 *  - `error` (`Error | undefined`): any error returned by the subgraph query.
 * 
 * @example
 * // All events
 * const { events, loading, error } = useGoldEvents();
 * 
 * // Events for a specific user
 * const { events } = useGoldEvents("0xabc...");
 */
export function useGoldEvents(userAddress?: string) {
  const query = userAddress ? GET_USER_GOLD_EVENTS : GET_ALL_GOLD_EVENTS;
  const variables = userAddress
    ? { first: 50, skip: 0, user: userAddress }
    : { first: 50, skip: 0 }

  const { data, loading, error } = useQuery<GoldEventsData>(query, {
    variables: variables,
    fetchPolicy: "network-only",    // always get fresh data
  });


  const events: GoldEvent[] = useMemo(() => {
    if (!data) return [];
    const result: GoldEvent[] = [];
    // Gold deposits
    for (const e of data.goldDepositeds ?? []) {
      result.push({
        id: e.id,
        eventType: "GoldDeposited",
        timestamp: Number(e.timestamp),
        user: e.to,
        amount: BigInt(e.tokensMinted),
        details: `Minted ${formatWeiAmount(BigInt(e.tokensMinted))} AUR for ${formatWeiAmount(BigInt(e.ouncesDeposited))} oz gold deposits`,
        txHash: e.id.split("-")[0],
        block: ""
      });
    }
    // Gold withdrawals
    for (const e of data.goldWithdrawns ?? []) {
      result.push({
        id: e.id,
        eventType: "GoldWithdrawn",
        timestamp: Number(e.timestamp),
        user: e.to,
        amount: BigInt(e.tokensBurned),
        details: `Burned ${formatWeiAmount(BigInt(e.tokensBurned))} AUR for ${formatWeiAmount(BigInt(e.ouncesWithdrawn))} oz gold withdrawals`,
        txHash: e.id.split("-")[0],
        block: ""
      });
    }
    // Gold losses
    for (const e of data.goldLosses ?? []) {
      result.push({
        id: e.id,
        eventType: "GoldLoss",
        timestamp: Number(e.timestamp),
        user: e.reporter,
        amount: BigInt(e.ouncesLost),
        details: `Reported gold loss: ${formatWeiAmount(BigInt(e.ouncesLost))} oz`,
        txHash: e.id.split("-")[0],
        block: ""
      });
    }
    // Sort by newest
    return result.sort((a, b) => b.timestamp - a.timestamp);
  }, [data]);

  return { events, loading, error };
}