import { SuiClient } from '@onelabs/sui/client';
import { Ed25519Keypair } from '@onelabs/sui/keypairs/ed25519';
import { Transaction } from '@onelabs/sui/transactions';
import { fromB64 } from '@onelabs/sui/utils';

// ============================================================================
// Configuration
// ============================================================================

const PACKAGE_ID = "0xa421e6b6f0f8d5e3d9f1fbf955c8cc54486788cdb85d4c3c60f9f67d242b6e75";
const RPC_URL = 'https://rpc-testnet.onelabs.cc:443';

// Coin type
const COIN_TYPE = '0x2::oct::OCT';

// ============================================================================
// Test Setup
// ============================================================================

const client = new SuiClient({ url: RPC_URL });

// Create test keypairs (in production, load from keystore)
// You can use your actual mnemonic or private key
const player1 = Ed25519Keypair.deriveKeypair(
    "REDACTED_MNEMONIC_3"
);
const player2 = Ed25519Keypair.deriveKeypair(
    "REDACTED_MNEMONIC_2"
);

const player1Address = player1.getPublicKey().toSuiAddress();
const player2Address = player2.getPublicKey().toSuiAddress();

console.log('Player 1:', player1Address);
console.log('Player 2:', player2Address);

// ============================================================================
// Helper Functions
// ============================================================================

async function executeTransaction(
    signer: Ed25519Keypair,
    tx: Transaction,
    description: string
) {
    console.log(`\n📤 ${description}...`);

    // Explicitly set gas payment using the custom native token
    const address = signer.getPublicKey().toSuiAddress();

    // 1. Find a candidate coin (if we haven't cached one, or just re-fetch to be safe)
    const coins = await client.getCoins({
        owner: address,
        coinType: COIN_TYPE
    });

    if (coins.data.length > 0) {
        // Use the first available coin loop to find one with enough balance
        const candidate = coins.data.find(c => BigInt(c.balance) > 10_000_000n);

        if (candidate) {
            // 2. Fetch the LATEST version of this coin object directly
            // This bypasses indexer lag which causes "not available for consumption" errors
            const coinData = await client.getObject({
                id: candidate.coinObjectId
            });

            if (coinData.data && coinData.data.version && coinData.data.digest) {
                tx.setGasPayment([{
                    objectId: coinData.data.objectId,
                    version: coinData.data.version,
                    digest: coinData.data.digest,
                }]);
            }
        }
    }

    try {
        const result = await client.signAndExecuteTransaction({
            signer,
            transaction: tx,
            options: {
                showEffects: true,
                showEvents: true,
                showObjectChanges: true,
            },
        });
        // ... rest of function unchanged

        if (result.effects?.status.status === 'success') {
            console.log(`✅ Success! Digest: ${result.digest}`);

            // Show events
            if (result.events && result.events.length > 0) {
                console.log('📢 Events:');
                result.events.forEach((event, i) => {
                    console.log(`  ${i + 1}. ${event.type}`);
                    console.log(`     Data:`, JSON.stringify(event.parsedJson, null, 2));
                });
            }

            return result;
        } else {
            console.error(`❌ Failed:`, result.effects?.status);
            throw new Error(`Transaction failed: ${result.effects?.status.error}`);
        }
    } catch (error) {
        console.error(`❌ Error executing transaction:`, error);
        throw error;
    }
}

async function getGasCoin(address: string, amount: bigint = 1000000000n) {
    const coins = await client.getCoins({ owner: address, coinType: COIN_TYPE });

    if (coins.data.length === 0) {
        throw new Error(`No gas coins found for ${address}. Please fund this address first.`);
    }

    // Find a coin with enough balance
    const suitableCoin = coins.data.find(coin => BigInt(coin.balance) >= amount);

    if (!suitableCoin) {
        throw new Error(`No coin with sufficient balance (need ${amount})`);
    }

    return suitableCoin.coinObjectId;
}

// ============================================================================
// Test Flow
// ============================================================================

async function runFullGameFlow() {
    console.log('🎮 Starting Bomb Panic Integration Test\n');
    console.log('='.repeat(60));

    // Check connection
    const chainId = await client.getChainIdentifier();
    console.log('🔗 Connected to chain:', chainId);

    let gameStateId: string;

    // ========================================================================
    // Step 1: Create and Share GameState
    // ========================================================================

    console.log('\n📦 Step 1: Creating GameState object...');

    const createTx = new Transaction();

    // Create a mock GameHubRef (using a dummy ID for testing)
    // In production, this would be a real GameHub object
    const dummyHubId = '0x0000000000000000000000000000000000000000000000000000000000000000';

    // Call create_game_state and share it
    // Note: We need to add a helper entry function to your contract for this
    // For now, we'll assume you've added an `initialize_game` entry function

    createTx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::initialize_game`,
        arguments: [
            createTx.pure.address(dummyHubId), // hub_ref ID
        ],
        typeArguments: [COIN_TYPE],
    });

    const createResult = await executeTransaction(
        player1,
        createTx,
        'Creating GameState'
    );

    // Extract the created GameState object ID
    const createdObjects = createResult.objectChanges?.filter(
        (change) => change.type === 'created'
    );

    const gameStateObject = createdObjects?.find((obj) =>
        obj.objectType?.includes('::bomb_panic::GameState')
    );

    if (!gameStateObject || gameStateObject.type !== 'created') {
        throw new Error('Failed to find created GameState object');
    }

    gameStateId = gameStateObject.objectId;
    console.log(`✅ GameState created: ${gameStateId}`);

    // ========================================================================
    // Step 2: Players Join
    // ========================================================================

    console.log('\n👥 Step 2: Players joining the game...');

    // Player 1 joins
    const join1Tx = new Transaction();
    join1Tx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::join`,
        arguments: [join1Tx.object(gameStateId)],
        typeArguments: [COIN_TYPE],
    });

    await executeTransaction(player1, join1Tx, 'Player 1 joining');

    // Player 2 joins
    const join2Tx = new Transaction();
    join2Tx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::join`,
        arguments: [join2Tx.object(gameStateId)],
        typeArguments: [COIN_TYPE],
    });

    await executeTransaction(player2, join2Tx, 'Player 2 joining');

    // ========================================================================
    // Step 3: Start Round
    // ========================================================================

    console.log('\n🚀 Step 3: Starting the round...');

    const startTx = new Transaction();

    const poolValue = 1000000n; // 0.001 SUI (in MIST)

    startTx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::start_round`,
        arguments: [
            startTx.object('0x8'), // Random object (shared)
            startTx.object(gameStateId),
            startTx.object('0x6'), // Clock object (shared)
            startTx.pure.u64(poolValue),
        ],
        typeArguments: [COIN_TYPE],
    });

    const startResult = await executeTransaction(
        player1,
        startTx,
        'Starting round'
    );

    // Extract bomb holder from RoundStarted event
    const roundStartedEvent = startResult.events?.find((e) =>
        e.type.includes('::bomb_panic::RoundStarted')
    );

    let currentHolder = (roundStartedEvent?.parsedJson as any)?.bomb_holder as string;
    let explodeAtMs = (roundStartedEvent?.parsedJson as any)?.explode_at_ms as string;

    console.log(`💣 Initial bomb holder: ${currentHolder}`);
    console.log(`⏰ Explosion time: ${explodeAtMs} ms`);

    // ========================================================================
    // Step 4: Pass Bomb
    // ========================================================================

    console.log('\n🔄 Step 4: Passing the bomb...');

    // Determine who should pass (current holder)
    const holderKeypair = currentHolder === player1Address ? player1 : player2;

    // Wait a bit to accumulate some reward
    await new Promise(resolve => setTimeout(resolve, 2000));

    const passTx = new Transaction();
    passTx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::pass_bomb`,
        arguments: [
            passTx.object('0x8'), // Random
            passTx.object(gameStateId),
            passTx.object('0x6'), // Clock
        ],
        typeArguments: [COIN_TYPE],
    });

    const passResult = await executeTransaction(
        holderKeypair,
        passTx,
        'Passing bomb'
    );

    const bombPassedEvent = passResult.events?.find((e) =>
        e.type.includes('::bomb_panic::BombPassed')
    );

    currentHolder = (bombPassedEvent?.parsedJson as any)?.to as string;
    console.log(`💣 New bomb holder: ${currentHolder}`);

    // ========================================================================
    // Step 5: Wait and Trigger Explosion
    // ========================================================================

    console.log('\n💥 Step 5: Waiting for explosion time...');

    const now = Date.now();
    const waitTime = Math.max(0, Number(explodeAtMs) - now + 1000);

    console.log(`⏳ Waiting ${waitTime}ms for explosion...`);
    await new Promise(resolve => setTimeout(resolve, waitTime));

    const explodeTx = new Transaction();
    explodeTx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::try_explode`,
        arguments: [
            explodeTx.object(gameStateId),
            explodeTx.object('0x6'), // Clock
        ],
        typeArguments: [COIN_TYPE],
    });

    const explodeResult = await executeTransaction(
        player1, // Anyone can call this (permissionless)
        explodeTx,
        'Triggering explosion'
    );

    const explodedEvent = explodeResult.events?.find((e) =>
        e.type.includes('::bomb_panic::Exploded')
    );

    console.log(`💀 Dead player: ${(explodedEvent?.parsedJson as any)?.dead_player}`);

    // ========================================================================
    // Step 6: Consume Settlement Intent
    // ========================================================================

    console.log('\n💰 Step 6: Consuming settlement intent...');

    // Note: This would typically be called by the GameHubSDK
    // For testing, we'll call it directly and inspect the returned value

    const settleTx = new Transaction();

    // Call consume_settlement_intent (returns SettlementIntent)
    const [settlementIntent] = settleTx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::consume_settlement_intent`,
        arguments: [settleTx.object(gameStateId)],
        typeArguments: [COIN_TYPE],
    });

    // SettlementIntent has 'drop', so we can just let it be dropped automatically

    await executeTransaction(
        player1,
        settleTx,
        'Consuming settlement intent'
    );

    console.log('\n' + '='.repeat(60));
    console.log('🎉 Full game flow completed successfully!');
}

// ============================================================================
// Run the test
// ============================================================================

runFullGameFlow()
    .then(() => {
        console.log('\n✅ All tests passed!');
        process.exit(0);
    })
    .catch((error) => {
        console.error('\n❌ Test failed:', error);
        process.exit(1);
    });
