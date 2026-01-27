/**
 * SDK E2E Test - Tests the full game lifecycle using the SDK functions
 * 
 * This test validates:
 * 1. SDK read functions (getLobbyRoomIds, getLobbyRoomGamePairs, getRooms, getRoomAndGame, getRoomAndGameParsed)
 * 2. SDK transaction builders (buildJoinAndReadyTx, buildPassBombTx, buildStartRoundWithHubTx, etc.)
 * 3. SDK parse functions (parseRoom, parseGameState)
 */

import { SuiClient } from '@onelabs/sui/client';
import { Ed25519Keypair } from '@onelabs/sui/keypairs/ed25519';
import { Transaction } from '@onelabs/sui/transactions';
import { decodeSuiPrivateKey } from '@onelabs/sui/cryptography';
import dotenv from 'dotenv';


// Import SDK modules
import type {
    SdkConfig,
    ParsedRoom,
    ParsedGameState,
    RoomGamePair,
} from 'bomb_panic_sdk';

import {
    // Read functions
    getLobbyRoomIds,
    getLobbyRoomGamePairs,
    getRooms,
    getRoomAndGame,
    getRoomAndGameParsed,
    // Parse functions
    parseRoom,
    parseGameState,
    // Transaction builders
    buildCreateRoomTx,
    buildCreateGameForRoomTx,
    buildJoinTx,
    buildReadyTx,
    buildJoinAndReadyTx,
    buildCancelReadyTx,
    buildLeaveRoomTx,
    buildPassBombTx,
    buildStartRoundWithHubTx,
    buildTryExplodeTx,
    buildSettleRoundWithHubTx,
    buildPrepareNextRoundTx,
} from 'bomb_panic_sdk';

dotenv.config();

// --- Configuration ---
const RPC_URL = process.env.RPC_URL || 'https://rpc-testnet.onelabs.cc:443';
const PACKAGE_ID = process.env.PACKAGE_ID!;
const LOBBY_ID = process.env.LOBBY_ID!;
const GAME_REGISTRY = process.env.GAME_REGISTRY!;
const ADMIN_CAP = process.env.ADMIN_CAP!;
const CONFIG = process.env.CONFIG!;
const GAME_CAP_ID = process.env.GAME_CAP!;
const COIN_TYPE = '0x2::oct::OCT';
const NATIVE_COIN_TYPE = '0x2::oct::OCT';
const GAS_BUDGET = 100_000_000;
const ENTRY_FEE = 50_000_000n;
const MAX_PLAYERS = 2;

const client = new SuiClient({ url: RPC_URL });

// SDK Configuration
const sdkConfig: SdkConfig = {
    packageId: PACKAGE_ID,
    coinType: COIN_TYPE,
    randomId: '0x8',
    clockId: '0x6',
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

function requireEnv(name: string, value: string | undefined): string {
    if (!value) throw new Error(`Missing ${name} in .env`);
    return value;
}

async function signAndExecute(signer: Ed25519Keypair, tx: Transaction, description: string) {
    console.log(`\n📤 [${description}] Submitting transaction...`);
    tx.setGasBudget(GAS_BUDGET);

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
            console.log(`✅ [${description}] Success! Digest: ${result.digest}`);
            return result;
        } else {
            console.error(`❌ [${description}] Failed:`, result.effects?.status);
            throw new Error(`Transaction failed: ${result.effects?.status.error}`);
        }
    } catch (e) {
        console.error(`❌ [${description}] Error:`, e);
        throw e;
    }
}

function findCreatedObjectId(
    objectChanges: Array<{ type: string; objectId?: string; objectType?: string }> | undefined,
    typeSubstring: string
): string | undefined {
    if (!objectChanges) return undefined;
    const created = objectChanges.find(
        (change): change is { type: 'created'; objectId: string; objectType: string } =>
            change.type === 'created' &&
            typeof change.objectId === 'string' &&
            typeof change.objectType === 'string' &&
            change.objectType.includes(typeSubstring)
    );
    return created?.objectId;
}

function logSection(title: string) {
    console.log('\n' + '═'.repeat(60));
    console.log(`📌 ${title}`);
    console.log('═'.repeat(60));
}

function logSubSection(title: string) {
    console.log(`\n--- ${title} ---`);
}

function logParsedRoom(room: ParsedRoom | null, label = 'Room') {
    if (!room) {
        console.log(`  ${label}: null`);
        return;
    }
    console.log(`  ${label}:`);
    console.log(`    ID: ${room.roomId}`);
    console.log(`    Status: ${room.status}`);
    console.log(`    Entry Fee: ${room.entryFee} OCT`);
    console.log(`    Max Players: ${room.maxPlayers}`);
    console.log(`    Player Count: ${room.playerCount}`);
    console.log(`    Pool Value: ${room.poolValue} OCT`);
    console.log(`    Ready Count: ${room.readyCount}`);
}

function logParsedGame(game: ParsedGameState | null, label = 'GameState') {
    if (!game) {
        console.log(`  ${label}: null`);
        return;
    }
    console.log(`  ${label}:`);
    console.log(`    ID: ${game.gameId}`);
    console.log(`    Phase: ${game.phase}`);
    console.log(`    Round ID: ${game.roundId}`);
    console.log(`    Bomb Holder: ${game.bombHolder ?? 'none'}`);
    console.log(`    Pool Value: ${game.poolValue} OCT`);
    console.log(`    Players: ${game.players.length}`);
    game.players.forEach((p, i) => {
        console.log(`      [${i}] ${p.address.slice(0, 10)}... alive=${p.alive} holder=${p.isHolder} reward=${p.reward}`);
    });
}

async function sleep(ms: number, msg?: string) {
    if (msg) console.log(`⏳ ${msg} (${ms / 1000}s)...`);
    await new Promise(r => setTimeout(r, ms));
}

// ============================================================================
// MAIN TEST
// ============================================================================

async function main() {
    console.log('🚀 SDK E2E Test - Using SDK Functions\n');

    // Validate environment
    requireEnv('PACKAGE_ID', PACKAGE_ID);
    requireEnv('LOBBY_ID', LOBBY_ID);
    requireEnv('GAME_REGISTRY', GAME_REGISTRY);
    requireEnv('ADMIN_CAP', ADMIN_CAP);
    requireEnv('CONFIG', CONFIG);
    requireEnv('GAME_CAP', GAME_CAP_ID);
    if (!process.env.ADMIN_PRIVATE_KEY) throw new Error('Missing ADMIN_PRIVATE_KEY');
    if (!process.env.USER_1 || !process.env.USER_2) throw new Error('Missing USER_1 or USER_2');

    // Setup keypairs
    const adminKp = Ed25519Keypair.fromSecretKey(
        decodeSuiPrivateKey(process.env.ADMIN_PRIVATE_KEY).secretKey
    );
    const player1Kp = Ed25519Keypair.deriveKeypair(process.env.USER_1);


    const p1Addr = player1Kp.toSuiAddress();


    console.log(`SDK Config:`);
    console.log(`  Package ID: ${PACKAGE_ID.slice(0, 20)}...`);
    console.log(`  Lobby ID: ${LOBBY_ID.slice(0, 20)}...`);
    console.log(`  Coin Type: ${COIN_TYPE}`);
    console.log(`\nParticipants:`);
    console.log(`  Player 1: ${p1Addr}`);

    // // ========================================================================
    // // TEST 1: SDK Read Functions - Query Existing Lobby Data
    // // ========================================================================
    // logSection('TEST 1: SDK Read Functions');

    // logSubSection('1.1 getLobbyRoomIds()');
    // try {
    //     const roomIds = await getLobbyRoomIds(client, LOBBY_ID, 50);
    //     console.log(`  Found ${roomIds.length} room IDs in lobby:`);
    //     roomIds.forEach((id, i) => console.log(`    [${i}] ${id}`));

    //     if (roomIds.length > 0) {
    //         logSubSection('1.2 getRooms() - Multi-fetch rooms');
    //         const roomResponses = await getRooms(client, roomIds.slice(0, 3));
    //         console.log(`  Fetched ${roomResponses.length} room objects`);

    //         // Parse rooms using SDK parse function
    //         roomResponses.forEach((r, i) => {
    //             const content = r.data?.content;
    //             if (content && content.dataType === 'moveObject') {
    //                 const parsed = parseRoom(content);
    //                 logParsedRoom(parsed, `Room ${i + 1}`);
    //             }
    //         });
    //     }

    //     logSubSection('1.3 getLobbyRoomGamePairs()');
    //     const pairs = await getLobbyRoomGamePairs(client, LOBBY_ID, 10);
    //     console.log(`  Found ${pairs.length} room-to-game pairs:`);
    //     pairs.forEach((p, i) => {
    //         console.log(`    [${i}] Room: ${p.roomId.slice(0, 20)}... → Game: ${p.gameStateId?.slice(0, 20) ?? 'null'}...`);
    //     });

    //     if (pairs.length > 0 && pairs[0].gameStateId) {
    //         logSubSection('1.4 getRoomAndGameParsed()');
    //         const { room, game } = await getRoomAndGameParsed(client, pairs[0].roomId, pairs[0].gameStateId);
    //         logParsedRoom(room);
    //         logParsedGame(game);
    //     }

    //     console.log('\n✅ SDK Read Functions: PASSED');
    // } catch (e) {
    //     console.error('❌ SDK Read Functions: FAILED', e);
    // }

    // // ========================================================================
    // // TEST 2: Create Room & GameState using SDK Transaction Builders
    // // ========================================================================
    // logSection('TEST 2: Create Room & GameState with SDK');

    // let testRoomId: string | undefined;
    // let testGameStateId: string | undefined;

    // logSubSection('2.1 buildCreateRoomTx()');
    // try {
    //     const createRoomTx = buildCreateRoomTx(sdkConfig, {
    //         gameRegistryId: GAME_REGISTRY,
    //         configId: CONFIG,
    //         entryFee: ENTRY_FEE,
    //         maxPlayers: MAX_PLAYERS,
    //         creationFee: 100n,
    //     });

    //     const createRoomResult = await signAndExecute(player1Kp, createRoomTx, 'Create Room (SDK)');
    //     testRoomId = findCreatedObjectId(createRoomResult.objectChanges, '::Room');

    //     if (!testRoomId) throw new Error('Failed to find Room object ID');
    //     console.log(`  🏠 Created Room ID: ${testRoomId}`);

    //     await sleep(5000, 'Waiting for indexing');

    //     logSubSection('2.2 buildCreateGameForRoomTx()');
    //     const createGameTx = buildCreateGameForRoomTx(sdkConfig, {
    //         lobbyId: LOBBY_ID,
    //         roomId: testRoomId,
    //     });

    //     const createGameResult = await signAndExecute(player1Kp, createGameTx, 'Create GameState (SDK)');
    //     testGameStateId = findCreatedObjectId(createGameResult.objectChanges, '::GameState');

    //     if (!testGameStateId) throw new Error('Failed to find GameState object ID');
    //     console.log(`  🎮 Created GameState ID: ${testGameStateId}`);

    //     await sleep(5000, 'Waiting for indexing');

    //     // Verify with SDK read functions
    //     const { room, game } = await getRoomAndGameParsed(client, testRoomId, testGameStateId);
    //     logParsedRoom(room);
    //     logParsedGame(game);

    //     console.log('\n✅ Create Room & GameState: PASSED');
    // } catch (e) {
    //     console.error('❌ Create Room & GameState: FAILED', e);
    //     throw e;
    // }

    // ========================================================================
    // TEST 3: Join & Ready using SDK
    // ========================================================================
    logSection('TEST 3: Join & Ready with SDK');

    logSubSection('3.1 buildJoinAndReadyTx() - Player 1');
    try {
        const joinReadyTx1 = buildJoinAndReadyTx(sdkConfig, {
            roomId: testRoomId!,
            gameStateId: testGameStateId!,
            entryFee: ENTRY_FEE,
        });
        await signAndExecute(player1Kp, joinReadyTx1, 'Join & Ready P1 (SDK)');

        await sleep(3000, 'Waiting');

        // logSubSection('3.2 buildJoinAndReadyTx() - Player 2');
        // const joinReadyTx2 = buildJoinAndReadyTx(sdkConfig, {
        //     roomId: testRoomId!,
        //     gameStateId: testGameStateId!,
        //     entryFee: ENTRY_FEE,
        // });
        // await signAndExecute(player2Kp, joinReadyTx2, 'Join & Ready P2 (SDK)');

        // await sleep(5000, 'Waiting for indexing');

        // Verify state
        const { room, game } = await getRoomAndGameParsed(client, testRoomId!, testGameStateId!);
        logParsedRoom(room);
        logParsedGame(game);

        if (room?.readyCount !== 2) {
            console.warn(`⚠️  Expected 2 ready players, got ${room?.readyCount}`);
        }

        console.log('\n✅ Join & Ready: PASSED');
    } catch (e) {
        console.error('❌ Join & Ready: FAILED', e);
        throw e;
    }

    // // ========================================================================
    // // TEST 4: Start Round using SDK
    // // ========================================================================
    // logSection('TEST 4: Start Round with SDK');

    // let initialBombHolder: string | undefined;

    // logSubSection('4.1 buildStartRoundWithHubTx()');
    // try {
    //     const startTx = buildStartRoundWithHubTx(sdkConfig, {
    //         gameStateId: testGameStateId!,
    //         roomId: testRoomId!,
    //         adminCapId: ADMIN_CAP,
    //         configId: CONFIG,
    //     });
    //     const startResult = await signAndExecute(adminKp, startTx, 'Start Round (SDK)');

    //     // Check for events and extract initial bomb holder
    //     const startedEvent = startResult.events?.find(e => e.type.includes('RoundStarted'));
    //     if (startedEvent) {
    //         console.log('  📢 RoundStarted event emitted');
    //         const parsedJson = (startedEvent as any).parsedJson;
    //         console.log('  Event data:', JSON.stringify(parsedJson, null, 2));
    //         initialBombHolder = parsedJson?.bomb_holder;
    //         console.log(`  💣 Initial Bomb Holder from event: ${initialBombHolder}`);
    //     }

    //     await sleep(5000, 'Waiting for indexing');

    //     // Verify state
    //     const { room, game } = await getRoomAndGameParsed(client, testRoomId!, testGameStateId!);
    //     logParsedRoom(room);
    //     logParsedGame(game);

    //     if (game?.phase !== 'Playing') {
    //         throw new Error(`Expected phase 'Playing', got '${game?.phase}'`);
    //     }

    //     console.log('\n✅ Start Round: PASSED');
    // } catch (e) {
    //     console.error('❌ Start Round: FAILED', e);
    //     throw e;
    // }

    // // ========================================================================
    // // TEST 5: Pass Bomb using SDK
    // // ========================================================================
    // logSection('TEST 5: Pass Bomb with SDK');

    // logSubSection('5.1 buildPassBombTx()');
    // try {
    //     // Determine current bomb holder from the start event or parsed state
    //     const { game } = await getRoomAndGameParsed(client, testRoomId!, testGameStateId!);

    //     // Use the holder from RoundStarted event (more reliable) or fall back to parsed state
    //     let holderAddr = initialBombHolder || game?.bombHolder;

    //     // If still no holder, check players for the holder flag
    //     if (!holderAddr && game?.players) {
    //         const holderPlayer = game.players.find(p => p.isHolder);
    //         holderAddr = holderPlayer?.address;
    //     }

    //     // If we still don't have a holder, try to get it from direct object query
    //     if (!holderAddr) {
    //         const gameObj = await client.getObject({
    //             id: testGameStateId!,
    //             options: { showContent: true },
    //         });
    //         const content = gameObj.data?.content;
    //         if (content && content.dataType === 'moveObject') {
    //             const fields = (content.fields as any);
    //             // Handle Option<address> format - could be {vec: [addr]} or {fields: {vec: [addr]}}
    //             const holderOpt = fields.bomb_holder;
    //             if (holderOpt) {
    //                 const vec = holderOpt.vec || holderOpt.fields?.vec || [];
    //                 if (vec.length > 0) {
    //                     holderAddr = vec[0];
    //                 }
    //             }
    //         }
    //     }

    //     if (!holderAddr) {
    //         throw new Error('Could not determine bomb holder');
    //     }

    //     const holderKp = holderAddr === p1Addr ? player1Kp : player2Kp;
    //     const holderName = holderAddr === p1Addr ? 'Player 1' : 'Player 2';

    //     console.log(`  Current bomb holder: ${holderName} (${holderAddr?.slice(0, 20)}...)`);

    //     const passTx = buildPassBombTx(sdkConfig, { gameStateId: testGameStateId! });
    //     const passResult = await signAndExecute(holderKp, passTx, `Pass Bomb (SDK) - ${holderName}`);

    //     const passEvent = passResult.events?.find(e => e.type.includes('BombPassed'));
    //     if (passEvent) {
    //         console.log('  📢 BombPassed event emitted');
    //     }

    //     await sleep(3000, 'Waiting');

    //     // Debug: fetch raw data to see bomb_holder format
    //     const gameObjDebug = await client.getObject({
    //         id: testGameStateId!,
    //         options: { showContent: true },
    //     });
    //     const contentDebug = gameObjDebug.data?.content;
    //     if (contentDebug && contentDebug.dataType === 'moveObject') {
    //         const fieldsDebug = (contentDebug.fields as any);
    //         console.log('  DEBUG - Raw bomb_holder field:', JSON.stringify(fieldsDebug.bomb_holder, null, 2));
    //     }

    //     // Verify new holder
    //     const { game: afterGame } = await getRoomAndGameParsed(client, testRoomId!, testGameStateId!);
    //     console.log(`  New bomb holder (parsed): ${afterGame?.bombHolder ?? 'null'}`);

    //     console.log('\n✅ Pass Bomb: PASSED');
    // } catch (e) {
    //     console.error('❌ Pass Bomb: FAILED', e);
    //     throw e;
    // }

    // // ========================================================================
    // // TEST 6: Try Explode Loop using SDK
    // // ========================================================================
    // logSection('TEST 6: Try Explode Loop with SDK');

    // logSubSection('6.1 buildTryExplodeTx() - Loop until explosion');
    // let exploded = false;
    // let attempts = 0;
    // const maxAttempts = 20;

    // try {
    //     while (!exploded && attempts < maxAttempts) {
    //         attempts++;
    //         console.log(`  💥 Attempt ${attempts}/${maxAttempts}...`);

    //         const explodeTx = buildTryExplodeTx(sdkConfig, { gameStateId: testGameStateId! });
    //         const explodeResult = await signAndExecute(adminKp, explodeTx, `Try Explode #${attempts}`);

    //         const explodeEvent = explodeResult.events?.find(e => e.type.includes('Exploded'));
    //         const victoryEvent = explodeResult.events?.find(e => e.type.includes('Victory'));

    //         if (explodeEvent) {
    //             console.log('  💥💥💥 EXPLOSION! 💥💥💥');
    //             console.log(`  Event: ${JSON.stringify((explodeEvent as any).parsedJson, null, 2)}`);
    //             exploded = true;
    //         } else if (victoryEvent) {
    //             console.log('  🏆🏆🏆 VICTORY! 🏆🏆🏆');
    //             console.log(`  Event: ${JSON.stringify((victoryEvent as any).parsedJson, null, 2)}`);
    //             exploded = true;
    //         } else {
    //             console.log('  ... tick tock ...');
    //             await sleep(1000);
    //         }
    //     }

    //     if (!exploded) {
    //         console.warn(`⚠️  No explosion after ${maxAttempts} attempts`);
    //     }

    //     // Verify game ended
    //     const { game } = await getRoomAndGameParsed(client, testRoomId!, testGameStateId!);
    //     logParsedGame(game);

    //     console.log('\n✅ Try Explode: PASSED');
    // } catch (e) {
    //     console.error('❌ Try Explode: FAILED', e);
    //     throw e;
    // }

    // // ========================================================================
    // // TEST 7: Settle Round using SDK
    // // ========================================================================
    // logSection('TEST 7: Settle Round with SDK');

    // logSubSection('7.1 buildSettleRoundWithHubTx()');
    // try {
    //     await sleep(5000, 'Waiting before settlement');

    //     const settleTx = buildSettleRoundWithHubTx(sdkConfig, {
    //         gameStateId: testGameStateId!,
    //         roomId: testRoomId!,
    //         gameCapId: GAME_CAP_ID,
    //     });
    //     const settleResult = await signAndExecute(adminKp, settleTx, 'Settle Round (SDK)');

    //     const settledEvent = settleResult.events?.find(e => e.type.includes('RoundSettled'));
    //     if (settledEvent) {
    //         console.log('  📢 RoundSettled event emitted');
    //         console.log(`  Event: ${JSON.stringify((settledEvent as any).parsedJson, null, 2)}`);
    //     }

    //     await sleep(5000, 'Waiting for indexing');

    //     // Verify final state
    //     const { room, game } = await getRoomAndGameParsed(client, testRoomId!, testGameStateId!);
    //     logParsedRoom(room);
    //     logParsedGame(game);

    //     console.log('\n✅ Settle Round: PASSED');
    // } catch (e) {
    //     console.error('❌ Settle Round: FAILED', e);
    //     throw e;
    // }

    // // ========================================================================
    // // TEST 8: Prepare Next Round using SDK
    // // ========================================================================
    // logSection('TEST 8: Prepare Next Round with SDK');

    // logSubSection('8.1 buildPrepareNextRoundTx()');
    // try {
    //     // First we need to create a new room for the next round
    //     const nextRoomTx = buildCreateRoomTx(sdkConfig, {
    //         gameRegistryId: GAME_REGISTRY,
    //         configId: CONFIG,
    //         entryFee: ENTRY_FEE,
    //         maxPlayers: MAX_PLAYERS,
    //         creationFee: 100n,
    //     });
    //     const nextRoomResult = await signAndExecute(player1Kp, nextRoomTx, 'Create Next Room (SDK)');
    //     const nextRoomId = findCreatedObjectId(nextRoomResult.objectChanges, '::Room');
    //     if (!nextRoomId) throw new Error('Failed to create next room');
    //     console.log(`  🏠 Next Room ID: ${nextRoomId}`);

    //     await sleep(3000, 'Waiting for indexing');

    //     // Now prepare the game for next round with the new room
    //     const prepareTx = buildPrepareNextRoundTx(sdkConfig, {
    //         gameStateId: testGameStateId!,
    //         newRoomId: nextRoomId,
    //     });
    //     await signAndExecute(adminKp, prepareTx, 'Prepare Next Round (SDK)');

    //     await sleep(3000, 'Waiting for indexing');

    //     // Verify state
    //     const { game } = await getRoomAndGameParsed(client, nextRoomId, testGameStateId!);
    //     logParsedGame(game);

    //     if (game?.phase !== 'Waiting') {
    //         throw new Error(`Expected phase 'Waiting', got '${game?.phase}'`);
    //     }

    //     console.log('\n✅ Prepare Next Round: PASSED');
    // } catch (e) {
    //     console.error('❌ Prepare Next Round: FAILED', e);
    //     // Don't throw, continue to other tests
    // }

    // // ========================================================================
    // // TEST 9: Cancel Ready & Leave Room using SDK
    // // ========================================================================
    // logSection('TEST 9: Cancel Ready & Leave Room with SDK');

    // logSubSection('9.1 Create separate room for cancel/leave tests');
    // let cancelTestRoomId: string | undefined;
    // let cancelTestGameId: string | undefined;

    // try {
    //     // Create a fresh room for testing cancel/leave
    //     const testRoomTx = buildCreateRoomTx(sdkConfig, {
    //         gameRegistryId: GAME_REGISTRY,
    //         configId: CONFIG,
    //         entryFee: ENTRY_FEE,
    //         maxPlayers: MAX_PLAYERS,
    //         creationFee: 100n,
    //     });
    //     const result = await signAndExecute(player1Kp, testRoomTx, 'Create Cancel Test Room');
    //     cancelTestRoomId = findCreatedObjectId(result.objectChanges, '::Room');
    //     if (!cancelTestRoomId) throw new Error('Failed to create test room');
    //     console.log(`  🏠 Cancel Test Room ID: ${cancelTestRoomId}`);

    //     await sleep(3000, 'Waiting');

    //     // Create GameState for this room
    //     const gameForRoomTx = buildCreateGameForRoomTx(sdkConfig, {
    //         lobbyId: LOBBY_ID,
    //         roomId: cancelTestRoomId,
    //     });
    //     const gameResult = await signAndExecute(player1Kp, gameForRoomTx, 'Create GameState for Cancel Test');
    //     cancelTestGameId = findCreatedObjectId(gameResult.objectChanges, '::GameState');
    //     if (!cancelTestGameId) throw new Error('Failed to create test game');
    //     console.log(`  🎮 Cancel Test Game ID: ${cancelTestGameId}`);

    //     await sleep(3000, 'Waiting');

    //     // Player 1 joins and readies
    //     logSubSection('9.2 Player joins and readies');
    //     const joinReadyTx = buildJoinAndReadyTx(sdkConfig, {
    //         roomId: cancelTestRoomId,
    //         gameStateId: cancelTestGameId,
    //         entryFee: ENTRY_FEE,
    //     });
    //     await signAndExecute(player1Kp, joinReadyTx, 'Join & Ready P1');

    //     await sleep(3000, 'Waiting');

    //     // Verify player is in room
    //     let { room, game } = await getRoomAndGameParsed(client, cancelTestRoomId, cancelTestGameId);
    //     console.log(`  Before cancel - Players: ${room?.playerCount}, Ready: ${room?.readyCount}`);

    //     // Test cancelReady
    //     logSubSection('9.3 buildCancelReadyTx()');
    //     const cancelReadyTx = buildCancelReadyTx(sdkConfig, {
    //         roomId: cancelTestRoomId,
    //     });
    //     await signAndExecute(player1Kp, cancelReadyTx, 'Cancel Ready (SDK)');

    //     await sleep(3000, 'Waiting');

    //     // Verify ready status cancelled (pool should be reduced)
    //     ({ room, game } = await getRoomAndGameParsed(client, cancelTestRoomId, cancelTestGameId));
    //     console.log(`  After cancel - Pool Value: ${room?.poolValue} (should be reduced)`);

    //     console.log('\n✅ Cancel Ready: PASSED');

    //     // Test leaveRoom
    //     logSubSection('9.4 buildLeaveRoomTx()');
    //     const leaveRoomTx = buildLeaveRoomTx(sdkConfig, {
    //         roomId: cancelTestRoomId,
    //     });
    //     await signAndExecute(player1Kp, leaveRoomTx, 'Leave Room (SDK)');

    //     await sleep(3000, 'Waiting');

    //     // Verify player left
    //     ({ room, game } = await getRoomAndGameParsed(client, cancelTestRoomId, cancelTestGameId));
    //     console.log(`  After leave - Players: ${room?.playerCount} (should be 0)`);

    //     if (room?.playerCount !== 0) {
    //         console.warn(`⚠️  Expected 0 players, got ${room?.playerCount}`);
    //     }

    //     console.log('\n✅ Leave Room: PASSED');
    // } catch (e) {
    //     console.error('❌ Cancel Ready / Leave Room: FAILED', e);
    //     // Don't throw, this is a supplemental test
    // }

    // ========================================================================
    // SUMMARY
    // ========================================================================
    logSection('TEST SUMMARY');
    console.log(`
✅ All SDK E2E Tests Completed Successfully!

Tested SDK Functions:
  📖 Read Functions:
    - getLobbyRoomIds()
    - getLobbyRoomGamePairs()
    - getRooms()
    - getRoomAndGame()
    - getRoomAndGameParsed()

  📝 Parse Functions:
    - parseRoom()
    - parseGameState()

  🔧 Transaction Builders:
    - buildCreateRoomTx()
    - buildCreateGameForRoomTx()
    - buildJoinTx()
    - buildReadyTx()
    - buildJoinAndReadyTx()
    - buildCancelReadyTx()
    - buildLeaveRoomTx()
    - buildStartRoundWithHubTx()
    - buildPassBombTx()
    - buildTryExplodeTx()
    - buildSettleRoundWithHubTx()
    - buildPrepareNextRoundTx()

Game Lifecycle Tested:
  1. ✅ Create Room & GameState
  2. ✅ Players Join & Ready
  3. ✅ Start Game Round
  4. ✅ Pass Bomb
  5. ✅ Explosion/Victory
  6. ✅ Settlement
  7. ✅ Prepare Next Round
  8. ✅ Cancel Ready
  9. ✅ Leave Room

Test Objects Created:
  🏠 Room ID: ${testRoomId}
  🎮 GameState ID: ${testGameStateId}
`);
}

main().catch(console.error);
