import { SuiClient } from '@mysten/sui/client';
// OneChain Testnet RPC
const client = new SuiClient({
    url: 'https://rpc-testnet.onelabs.cc:443'
});
async function main() {
    // Check connection
    const chain = await client.getChainIdentifier();
    console.log('Connected to:', chain);
}
main();