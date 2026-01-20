import { SuiClient } from '@onelabs/sui/client';
import { Ed25519Keypair } from '@onelabs/sui/keypairs/ed25519';
import { Transaction } from '@onelabs/sui/transactions';
import { decodeSuiPrivateKey } from '@onelabs/sui/cryptography';
import dotenv from "dotenv";
// ============================================================================
// Configuration
// ============================================================================


const PACKAGE_ID = process.env.PACKAGE_ID;
const RPC_URL = process.env.RPC_URL;

// Shared objects from deployment
const GAME_REGISTRY = "0x2035d9bc13b8f936f25b47ae79026b4363f520bf229386e8d6e107113a5f5b87";
const CONFIG = "0xf4a15593535d4104e49db7ad555c9c7131763a25da2cac25139474a92d63b446";
const ADMIN_CAP = "0x69e07c7611d58d0dc03be8385aaf544ca75e8e37370d1c929e58ea4fa5a8635c";

// Coin type
const COIN_TYPE = '0x2::oct::OCT';

// Admin Private Key (for AdminCap and GameCap access)
const ADMIN_PRIVATE_KEY = process.env.ADMIN!;

// ============================================================================
// Test Setup
// ============================================================================

const client = new SuiClient({ url: process.env.RPC_URL! });

const player1 = Ed25519Keypair.fromSecretKey(process.env.USER_1!);
const player2 = Ed25519Keypair.fromSecretKey(process.env.USER_2!);

const player1Address = player1.getPublicKey().toSuiAddress();
const player2Address = player2.getPublicKey().toSuiAddress();

const adminKeypair = Ed25519Keypair.fromSecretKey(process.env.ADMIN!);
const adminAddress = adminKeypair.getPublicKey().toSuiAddress();

console.log('Player 1:', player1Address);
console.log('Player 2:', player2Address);
console.log('Admin:', adminAddress);

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

// ============================================================================
// Full GameHub Integration Test with Ready Mechanism
// ============================================================================

async function runFullIntegrationTest() {
    console.log('🎮 Starting Full GameHub + Bomb Panic Integration Test (with Ready Mechanism)\n');
    console.log('='.repeat(60));

    // NOTE: Game registration requires AdminCap which is owned by the package publisher
    // For this test, we assume the game is already registered

    // TODO: Replace this with actual GameCap ID after registration
    const gameCapId = "0x9948176a92fb510608de6dd5b8d78c8e51bebe9a631b0882a772c77351328714";

    console.log(`\n📝 Using GameCap: ${gameCapId}`);
    console.log('⚠️  Note: Game must be registered by admin first!');

    await sleep(1000);

    // Step 1: Create GameState
    console.log('\n📦 Step 1: Creating GameState...');

    const createGameTx = new Transaction();
    const dummyHubId = '0x0000000000000000000000000000000000000000000000000000000000000000';

    createGameTx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::initialize_game`,
        arguments: [
            createGameTx.pure.address(dummyHubId),
            createGameTx.pure.vector('u8', Array.from(new TextEncoder().encode('Hub Test Room'))),
            createGameTx.pure.u64(100_000_000), // 0.1 OCT entry fee
            createGameTx.pure.u64(4),
        ],
        typeArguments: [COIN_TYPE],
    });

    const createResult = await executeTransaction(player1, createGameTx, 'Creating GameState');

    const gameStateObject = createResult.objectChanges?.find(
        (change) => change.type === 'created' && change.objectType?.includes('::bomb_panic::GameState')
    );

    if (!gameStateObject || gameStateObject.type !== 'created') {
        throw new Error('Failed to find GameState object');
    }

    const gameStateId = gameStateObject.objectId;
    console.log(`✅ GameState created: ${gameStateId}`);

    await sleep(2000);

    // Step 2: Create Room in GameHub (with zero creation fee)
    console.log('\n🏠 Step 2: Creating Room in GameHub...');

    const createRoomTx = new Transaction();

    // Create zero-value coin for creation fee
    const [creationFeeCoin] = createRoomTx.splitCoins(createRoomTx.gas, [0]);

    createRoomTx.moveCall({
        target: `${PACKAGE_ID}::gamehub::create_room`,
        arguments: [
            createRoomTx.object(GAME_REGISTRY),
            createRoomTx.object(CONFIG),
            createRoomTx.pure.u64(100_000_000), // 0.1 OCT entry fee
            createRoomTx.pure.u8(4), // max 4 players
            creationFeeCoin,
        ],
        typeArguments: [COIN_TYPE, `${PACKAGE_ID}::bomb_panic::GameState<${COIN_TYPE}>`],
    });

    const roomResult = await executeTransaction(player1, createRoomTx, 'Creating Room');

    const roomObject = roomResult.objectChanges?.find(
        (change) => change.type === 'created' && change.objectType?.includes('::gamehub::Room')
    );

    if (!roomObject || roomObject.type !== 'created') {
        throw new Error('Failed to find Room object');
    }

    const roomId = roomObject.objectId;
    console.log(`✅ Room created: ${roomId}`);

    await sleep(2000);

    // Step 3: Player 1 joins (no fee yet) + signals ready (pays fee)
    console.log('\n👥 Step 3: Player 1 joining and readying...');

    const join1Tx = new Transaction();

    // Join room (no coin)
    join1Tx.moveCall({
        target: `${PACKAGE_ID}::gamehub::join_room`,
        arguments: [join1Tx.object(roomId)],
        typeArguments: [COIN_TYPE],
    });

    // Ready to play (with entry fee)
    const [entryFee1] = join1Tx.splitCoins(join1Tx.gas, [100_000_000]);
    join1Tx.moveCall({
        target: `${PACKAGE_ID}::gamehub::ready_to_play`,
        arguments: [join1Tx.object(roomId), entryFee1],
        typeArguments: [COIN_TYPE],
    });

    // Also join bomb_panic game
    join1Tx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::join`,
        arguments: [join1Tx.object(gameStateId)],
        typeArguments: [COIN_TYPE],
    });

    await executeTransaction(player1, join1Tx, 'Player 1 joining + ready');
    await sleep(2000);

    // Step 4: Player 2 joins and readies
    console.log('\n👥 Step 4: Player 2 joining and readying...');

    const join2Tx = new Transaction();

    // Join room (no coin)
    join2Tx.moveCall({
        target: `${PACKAGE_ID}::gamehub::join_room`,
        arguments: [join2Tx.object(roomId)],
        typeArguments: [COIN_TYPE],
    });

    // Ready to play (with entry fee)
    const [entryFee2] = join2Tx.splitCoins(join2Tx.gas, [100_000_000]);
    join2Tx.moveCall({
        target: `${PACKAGE_ID}::gamehub::ready_to_play`,
        arguments: [join2Tx.object(roomId), entryFee2],
        typeArguments: [COIN_TYPE],
    });

    // Also join bomb_panic game
    join2Tx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::join`,
        arguments: [join2Tx.object(gameStateId)],
        typeArguments: [COIN_TYPE],
    });

    await executeTransaction(player2, join2Tx, 'Player 2 joining + ready');
    await sleep(2000);

    console.log('\n💰 Total pool should be: 200,000,000 MIST (0.2 OCT)');

    // Step 5: Start round with hub integration (now collects insurance fee)
    console.log('\n🚀 Step 5: Starting round with GameHub integration...');

    const startTx = new Transaction();
    startTx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::start_round_with_hub`,
        arguments: [
            startTx.object('0x8'), // Random
            startTx.object(gameStateId),
            startTx.object(roomId),
            startTx.object('0x6'), // Clock
            startTx.object(ADMIN_CAP),
            startTx.object(CONFIG), // Config for fee collection
        ],
        typeArguments: [COIN_TYPE],
    });

    const startResult = await executeTransaction(adminKeypair, startTx, 'Starting round');

    const roundStartedEvent = startResult.events?.find((e) =>
        e.type.includes('::bomb_panic::RoundStarted')
    );

    const bombHolder = (roundStartedEvent?.parsedJson as any)?.bomb_holder;

    console.log(`💣 Bomb holder: ${bombHolder}`);
    console.log(`🎲 Using pure probabilistic explosion system`);

    await sleep(2000);

    // Step 6: Wait and explode
    console.log('\n💥 Step 6: Triggering probabilistic explosion...');

    // Wait 15 seconds to enter the probability zone
    const waitTime = 15000;
    console.log(`⏳ Waiting ${waitTime}ms to enter explosion probability zone...`);
    await sleep(waitTime);

    // Try explode until it works
    let exploded = false;
    let attempts = 0;

    while (!exploded && attempts < 100) {
        const explodeTx = new Transaction();
        explodeTx.moveCall({
            target: `${PACKAGE_ID}::bomb_panic::try_explode`,
            arguments: [
                explodeTx.object(gameStateId),
                explodeTx.object('0x6'),
                explodeTx.object('0x8'),
            ],
            typeArguments: [COIN_TYPE],
        });

        const explodeResult = await executeTransaction(player1, explodeTx, `Try explode ${attempts + 1}`);

        const explodedEvent = explodeResult.events?.find((e) =>
            e.type.includes('::bomb_panic::Exploded')
        );

        if (explodedEvent) {
            exploded = true;
            console.log(`💀 Dead player: ${(explodedEvent.parsedJson as any)?.dead_player}`);
        }

        attempts++;
        await sleep(500);
    }

    if (!exploded) {
        throw new Error('Failed to explode');
    }

    await sleep(2000);

    // Step 7: Settle with GameHub (no config param anymore)
    console.log('\n💰 Step 7: Settling with GameHub...');

    const settleTx = new Transaction();
    settleTx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::settle_round_with_hub`,
        arguments: [
            settleTx.object(gameStateId),
            settleTx.object(roomId),
            // CONFIG removed! No longer needed at settlement
            settleTx.object(gameCapId),
        ],
        typeArguments: [COIN_TYPE],
    });

    await executeTransaction(adminKeypair, settleTx, 'Settling round');
    await sleep(2000);

    // Step 8: Survivor claims winnings
    console.log('\n🎁 Step 8: Survivor claiming winnings...');

    // Determine who survived
    const survivorKeypair = bombHolder === player1Address ? player2 : player1;

    const claimTx = new Transaction();
    claimTx.moveCall({
        target: `${PACKAGE_ID}::gamehub::claim`,
        arguments: [
            claimTx.object(roomId),
        ],
        typeArguments: [COIN_TYPE],
    });

    const claimResult = await executeTransaction(survivorKeypair, claimTx, 'Claiming winnings');

    console.log('\n' + '='.repeat(60));
    console.log('🎉 Test Completed!');
    console.log('✅ Join → Ready (escrow) → Start (fee) → Play → Settle → Claim');
}

// ============================================================================
// Run the test
// ============================================================================

runFullIntegrationTest()
    .then(() => {
        console.log('\n✅ All integration tests passed!');
        process.exit(0);
    })
    .catch((error) => {
        console.error('\n❌ Test failed:', error);
        process.exit(1);
    });
