import { ApolloClient, InMemoryCache, HttpLink } from "@apollo/client";

const cache = new InMemoryCache();
const link = new HttpLink({ uri: "https://api.studio.thegraph.com/query/1745673/aurum-protocol-sepolia/v1.0.0" });

const client = new ApolloClient({
  cache: cache,
  link: link,
});

export default client;