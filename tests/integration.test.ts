import { SuiClient } from '@onelabs/sui/client';
import { Ed25519Keypair } from '@onelabs/sui/keypairs/ed25519';
import { Transaction } from '@onelabs/sui/transactions';
import { fromB64 } from '@onelabs/sui/utils';

// ============================================================================
// Configuration
// ============================================================================

const PACKAGE_ID = "0x23f55e8a3b0b8935f5f7cff3f0ba8746e912973684c660ef11fc882b9b137003";
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

async function sleep(ms: number) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

async function executeTransaction(
    signer: Ed25519Keypair,
    tx: Transaction,
    description: string
) {
    console.log(`\n📤 ${description}...`);

    const address = signer.getPublicKey().toSuiAddress();

    // Refresh gas coins and explicitly pick one to avoid stale versions
    const coins = await client.getCoins({
        owner: address,
        coinType: COIN_TYPE
    });

    if (coins.data.length > 0) {
        // Try to find a candidate with enough balance
        const candidate = coins.data.find(c => BigInt(c.balance) > 20_000_000n) || coins.data[0];

        if (candidate) {
            // Fetch the LATEST version from the full node to bypass indexer lag
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

    tx.setGasBudget(100_000_000n);

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

        if (result.effects?.status.status === 'success') {
            console.log(`✅ Success! Digest: ${result.digest}`);

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
// Test Functions
// ============================================================================


async function queryGameState(gameStateId: string) {
    console.log(`\n🔍 Querying GameState: ${gameStateId}...`);

    let retries = 5;
    while (retries > 0) {
        const object = await client.getObject({
            id: gameStateId,
            options: {
                showContent: true,
            },
        });

        if (object.data?.content?.dataType === 'moveObject') {
            const fields = object.data.content.fields as any;
            console.log('--- Room Details ---');
            console.log(`Name: ${fields.name}`);
            console.log(`Phase: ${JSON.stringify(fields.phase)}`);
            console.log(`Entry Fee: ${fields.entry_fee}`);
            console.log(`Max Players: ${fields.max_players}`);
            console.log(`Current Players: ${fields.players.length}`);
            console.log(`Pool Value: ${fields.pool_value}`);
            console.log('--------------------');
            return fields;
        }

        console.log(`  (Object not found yet, retrying in 1s... ${retries} left)`);
        await sleep(1000);
        retries--;
    }

    throw new Error('GameState object not found or invalid after several retries');
}

async function testCreateAndQueryRoom() {
    console.log('🧪 Testing Create and Query Room\n');
    console.log('='.repeat(60));

    const gameStateId = await createRoom();
    const fields = await queryGameState(gameStateId);

    if (fields.name === 'Test Room' && fields.entry_fee === '1000') {
        console.log('\n✅ Create and Query Room test passed!');
    } else {
        throw new Error('Query result does not match expected values');
    }

    return gameStateId;
}

async function createRoom(): Promise<string> {
    console.log('\n📦 Creating GameState object...');

    const createTx = new Transaction();
    const dummyHubId = '0x0000000000000000000000000000000000000000000000000000000000000000';

    createTx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::initialize_game`,
        arguments: [
            createTx.pure.address(dummyHubId),
            createTx.pure.address(player1Address), // server_authority
            createTx.pure.vector('u8', Array.from(new TextEncoder().encode('Test Room'))),
            createTx.pure.u64(1000),
            createTx.pure.u64(4),
        ],
        typeArguments: [COIN_TYPE],
    });

    const createResult = await executeTransaction(
        player1,
        createTx,
        'Creating GameState'
    );

    const createdObjects = createResult.objectChanges?.filter(
        (change) => change.type === 'created'
    );

    const gameStateObject = createdObjects?.find((obj) =>
        obj.objectType?.includes('::bomb_panic::GameState')
    );

    if (!gameStateObject || gameStateObject.type !== 'created') {
        throw new Error('Failed to find created GameState object');
    }

    return gameStateObject.objectId;
}

async function runFullGameFlow() {
    console.log('🎮 Starting Bomb Panic Integration Test\n');
    console.log('='.repeat(60));

    // Check connection
    const chainId = await client.getChainIdentifier();
    console.log('🔗 Connected to chain:', chainId);

    const gameStateId = await testCreateAndQueryRoom();

    // Add leave test
    await testLeaveWhileWaiting(gameStateId);

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
    await sleep(1000);

    // Player 2 joins
    const join2Tx = new Transaction();
    join2Tx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::join`,
        arguments: [join2Tx.object(gameStateId)],
        typeArguments: [COIN_TYPE],
    });

    await executeTransaction(player2, join2Tx, 'Player 2 joining');
    await sleep(1000);

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
    await sleep(1000);

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
    await sleep(1000);

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
            explodeTx.object('0x8'), // Random
        ],
        typeArguments: [COIN_TYPE],
    });

    const explodeResult = await executeTransaction(
        player1, // Anyone can call this (permissionless)
        explodeTx,
        'Triggering explosion'
    );
    await sleep(2000);

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
    await sleep(1000);

    // ========================================================================
    // Step 7: Reset Game (to play again)
    // ========================================================================

    console.log('\n🔄 Step 7: Resetting game state for next round...');

    const resetTx = new Transaction();
    resetTx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::reset_game`,
        arguments: [resetTx.object(gameStateId)],
        typeArguments: [COIN_TYPE],
    });

    await executeTransaction(player1, resetTx, 'Resetting game');

    // Verify room is back to Waiting phase and survivor stays
    let middleFields;
    let resetRetries = 5;
    while (resetRetries > 0) {
        middleFields = await queryGameState(gameStateId);

        if ((middleFields.phase as any).variant === 'Waiting' && middleFields.players.length === 1) {
            console.log('\n✅ Reset Game test passed! Survivor (Player 2) is still in the room.');
            break;
        }

        console.log(`  (Waiting for reset to reflect... ${resetRetries} left)`);
        console.log(`  Current State -> Phase: ${(middleFields.phase as any).variant}, Players: ${middleFields.players.length}`);
        await sleep(1000);
        resetRetries--;
    }

    if (!middleFields || (middleFields.phase as any).variant !== 'Waiting' || middleFields.players.length !== 1) {
        throw new Error(`Game reset failed: expected 1 survivor, got ${middleFields?.players.length} (Phase: ${(middleFields?.phase as any)?.variant})`);
    }

    // ========================================================================
    // Step 8: Dead Player Rejoins and Round 2 Starts
    // ========================================================================

    console.log('\n🔄 Step 8: Dead player (Player 1) rejoining...');

    const rejoinTx = new Transaction();
    rejoinTx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::join`,
        arguments: [rejoinTx.object(gameStateId)],
        typeArguments: [COIN_TYPE],
    });

    await executeTransaction(player1, rejoinTx, 'Player 1 rejoining');

    // Retry check for rejoining player
    let fieldsWithJoin;
    let retries = 5;
    while (retries > 0) {
        fieldsWithJoin = await queryGameState(gameStateId);
        console.log(`Players in room: ${fieldsWithJoin.players.length}`);

        if (fieldsWithJoin.players.length === 2) {
            console.log('✅ Rejoin successful!');
            break;
        }

        console.log(`  (Waiting for rejoin to reflect... ${retries} left)`);
        await sleep(1000);
        retries--;
    }

    if (!fieldsWithJoin || fieldsWithJoin.players.length !== 2) {
        throw new Error('Rejoin failed');
    }

    console.log('\n🚀 Starting Round 2...');
    const start2Tx = new Transaction();
    start2Tx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::start_round`,
        arguments: [
            start2Tx.object('0x8'),
            start2Tx.object(gameStateId),
            start2Tx.object('0x6'),
            start2Tx.pure.u64(1000000n),
        ],
        typeArguments: [COIN_TYPE],
    });

    await executeTransaction(player1, start2Tx, 'Starting Round 2');

    console.log('\n' + '='.repeat(60));
    console.log('🎉 Full "Play Again" cycle completed successfully!');
}

async function testLeaveWhileWaiting(gameStateId: string) {
    console.log('\n👥 Testing leave function (Waiting phase)...');

    // Player 2 joins
    const joinTx = new Transaction();
    joinTx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::join`,
        arguments: [joinTx.object(gameStateId)],
        typeArguments: [COIN_TYPE],
    });
    await executeTransaction(player2, joinTx, 'Player 2 joining to leave');
    await sleep(2000);

    let fields = await queryGameState(gameStateId);
    console.log(`Players before leave: ${fields.players.length}`);

    // Player 2 leaves
    const leaveTx = new Transaction();
    leaveTx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::leave`,
        arguments: [leaveTx.object(gameStateId), leaveTx.object('0x6')],
        typeArguments: [COIN_TYPE],
    });
    await executeTransaction(player2, leaveTx, 'Player 2 leaving');
    await sleep(2000);

    fields = await queryGameState(gameStateId);
    console.log(`Players after leave: ${fields.players.length}`);

    if (fields.players.length === 0) {
        console.log('✅ Leave test passed!');
    } else {
        throw new Error('Leave test failed: player still in list');
    }
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
