import { ApolloClient, InMemoryCache, HttpLink } from "@apollo/client";

const cache = new InMemoryCache();
const link = new HttpLink({ uri: "https://api.studio.thegraph.com/query/1745673/aurum-protocol-sepolia/v2.0.1" });

const client = new ApolloClient({
  cache: cache,
  link: link,
});

export default client;