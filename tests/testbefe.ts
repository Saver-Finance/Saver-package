import { SuiClient } from '@onelabs/sui/client';
import { Ed25519Keypair } from '@onelabs/sui/keypairs/ed25519';
import { Transaction } from '@onelabs/sui/transactions';
import { decodeSuiPrivateKey } from '@onelabs/sui/cryptography';
import dotenv from 'dotenv';

dotenv.config();

// --- Configuration ---
const RPC_URL = process.env.RPC_URL || 'https://rpc-testnet.onelabs.cc:443';
const PACKAGE_ID = process.env.PACKAGE_ID;
const LOBBY_ID = process.env.LOBBY_ID;
const GAME_REGISTRY = process.env.GAME_REGISTRY;
const ADMIN_CAP = process.env.ADMIN_CAP;
const CONFIG = process.env.CONFIG;
const GAME_CAP_ID = process.env.GAME_CAP;
const RANDOM_ID = process.env.RANDOM_ID || '0x8';
const CLOCK_ID = process.env.CLOCK_ID || '0x6';
const COIN_TYPE = '0x2::oct::OCT';
const NATIVE_COIN_TYPE = '0x2::oct::OCT';
const GAS_BUDGET = 100_000_000;
const ENTRY_FEE = 50_000_000; 
const MAX_PLAYERS = 2;

const client = new SuiClient({ url: RPC_URL });

// Helper to sign and execute transactions
async function signAndExecute(signer: Ed25519Keypair, tx: Transaction, description: string) {
    console.log(`\n📤 [${description}] Submitting transaction...`);
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

// Helper to log structures
async function logStructure(title: string, data: any) {
    console.log(`\n🔍 --- ${title} ---`);
    console.log(JSON.stringify(data, null, 2));
    console.log('-------------------------------------------');
}

function requireEnv(name: string, value: string | undefined): string {
    if (!value) throw new Error(`Missing ${name} in .env`);
    return value;
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

// Query specific rooms by their IDs
async function queryRooms(roomIds: string[]) {
    console.log('\n🔎 Querying rooms on-chain...');
    console.log(`\n📊 Querying ${roomIds.length} rooms`);

    const rooms = [];
    for (let index = 0; index < roomIds.length; index++) {
        const roomId = roomIds[index];
        try {
            const roomObj = await client.getObject({
                id: roomId,
                options: { showContent: true, showType: true }
            });

            const content = roomObj.data?.content;
            if (!content || content.dataType !== 'moveObject') {
                console.log(`\n  Room #${index + 1}: Invalid content`);
                continue;
            }
            const fields = content.fields as any;

            const status = fields.status?.variant || 'Unknown';
            const entryFee = BigInt(fields.entry_fee ?? 0);
            const maxPlayers = fields.max_players ?? 0;
            const playerCount = BigInt(fields.player_balances?.fields?.size ?? 0);
            const poolValue = BigInt(fields.pool?.fields?.value ?? 0);

            console.log(`\n  Room #${index + 1}:`);
            console.log(`    ID: ${roomId}`);
            console.log(`    Status: ${status}`);
            console.log(`    Entry Fee: ${entryFee} OCT`);
            console.log(`    Max Players: ${maxPlayers}`);
            console.log(`    Current Players: ${playerCount}`);
            console.log(`    Pool Value: ${poolValue} OCT`);

            rooms.push(roomObj);
        } catch (e) {
            console.error(`\n  Room #${index + 1} (${roomId}): Error querying - ${e}`);
        }
    }

    return rooms;
}

// Query specific GameStates by their IDs
async function queryGameStates(gameStateIds: string[]) {
    console.log('\n🔎 Querying GameStates on-chain...');
    console.log(`\n🎮 Querying ${gameStateIds.length} GameStates`);

    const gameStates = [];
    for (let index = 0; index < gameStateIds.length; index++) {
        const gameId = gameStateIds[index];
        try {
            const gameObj = await client.getObject({
                id: gameId,
                options: { showContent: true, showType: true }
            });

            const content = gameObj.data?.content;
            if (!content || content.dataType !== 'moveObject') {
                console.log(`\n  GameState #${index + 1}: Invalid content`);
                continue;
            }
            const fields = content.fields as any;

            const roomId = fields.room_id;
            const phase = fields.phase?.variant || 'Unknown';
            const roundId = fields.round_id ?? 0;
            const playerCount = fields.players?.length ?? 0;

            console.log(`\n  GameState #${index + 1}:`);
            console.log(`    ID: ${gameId}`);
            console.log(`    Room ID: ${roomId}`);
            console.log(`    Phase: ${phase}`);
            console.log(`    Round ID: ${roundId}`);
            console.log(`    Players: ${playerCount}`);

            gameStates.push(gameObj);
        } catch (e) {
            console.error(`\n  GameState #${index + 1} (${gameId}): Error querying - ${e}`);
        }
    }

    return gameStates;
}

// Query Lobby to verify room-to-game mappings
async function queryLobby(lobbyId: string) {
    console.log('\n🔎 Querying Lobby object...');
    try {
        const lobbyObj = await client.getObject({
            id: lobbyId,
            options: { showContent: true }
        });

        if (lobbyObj.data?.content && lobbyObj.data.content.dataType === 'moveObject') {
            const fields = lobbyObj.data.content.fields as any;
            const tableId = fields.room_to_game?.fields?.id?.id;

            console.log(`\n📋 Lobby Details:`);
            console.log(`  Lobby ID: ${lobbyId}`);
            console.log(`  Room-to-Game Table ID: ${tableId}`);

            logStructure("Lobby Full Structure", lobbyObj);
        }

        return lobbyObj;
    } catch (e) {
        console.error(`Failed to query lobby: ${e}`);
        return null;
    }
}

// Create a room and its associated GameState
// async function createRoomAndGame(
//     creator: Ed25519Keypair,
//     lobbyId: string,
//     gameRegistry: string,
//     config: string,
//     entryFee: number,
//     maxPlayers: number,
//     roomName: string
// ) {
//     console.log(`\n\n🏗️  Creating ${roomName}...`);

//     const creatorAddr = creator.toSuiAddress();
//     const tx = new Transaction();

//     // Get gas coin
//     const coins = await client.getCoins({ owner: creatorAddr, coinType: NATIVE_COIN_TYPE });
//     const gas = coins.data.sort((a, b) => Number(b.balance) - Number(a.balance))[0];
//     if (gas) {
//         tx.setGasPayment([{ objectId: gas.coinObjectId, version: gas.version, digest: gas.digest }]);
//     }

//     // Split creation fee (100 units)
//     const [creationFeeCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(100)]);

//     // Create room
//     tx.moveCall({
//         target: `${PACKAGE_ID}::gamehub::create_room`,
//         arguments: [
//             tx.object(gameRegistry),
//             tx.object(config),
//             tx.pure.u64(entryFee),
//             tx.pure.u8(maxPlayers),
//             creationFeeCoin
//         ],
//         typeArguments: [COIN_TYPE, `${PACKAGE_ID}::bomb_panic::GameState<${COIN_TYPE}>`]
//     });

//     tx.setGasBudget(GAS_BUDGET);

//     const createRoomResult = await signAndExecute(creator, tx, `Create ${roomName}`);
//     const roomId = findCreatedObjectId(createRoomResult.objectChanges, '::Room');

//     if (!roomId) throw new Error(`Failed to find Room object ID for ${roomName}`);
//     console.log(`  🏠 Room ID: ${roomId}`);

//     // Wait for indexing
//     console.log(`  ⏳ Waiting 5s for indexing...`);
//     await new Promise(r => setTimeout(r, 5000));

//     // Create GameState for this room
//     const tx2 = new Transaction();
//     const coins2 = await client.getCoins({ owner: creatorAddr, coinType: NATIVE_COIN_TYPE });
//     const gas2 = coins2.data.sort((a, b) => Number(b.balance) - Number(a.balance))[0];
//     if (gas2) {
//         tx2.setGasPayment([{ objectId: gas2.coinObjectId, version: gas2.version, digest: gas2.digest }]);
//     }

//     tx2.moveCall({
//         target: `${PACKAGE_ID}::bomb_panic::create_game_for_room`,
//         arguments: [
//             tx2.object(lobbyId),
//             tx2.pure.address(roomId)
//         ],
//         typeArguments: [COIN_TYPE]
//     });
//     tx2.setGasBudget(GAS_BUDGET);

//     const createGameResult = await signAndExecute(creator, tx2, `Create GameState for ${roomName}`);
//     const gameStateId = findCreatedObjectId(createGameResult.objectChanges, '::GameState');

//     if (!gameStateId) throw new Error(`Failed to find GameState object ID for ${roomName}`);
//     console.log(`  🎮 GameState ID: ${gameStateId}`);

//     // Check for RoomAndGameCreated event
//     const createdEvent = createGameResult.events?.find(e => e.type.includes('::RoomAndGameCreated'));
//     if (createdEvent) {
//         console.log(`  ✅ RoomAndGameCreated event emitted`);
//         logStructure(`${roomName} Creation Event`, createdEvent);
//     }

//     return { roomId, gameStateId };
// }

async function main() {
    console.log('🚀 Starting Lobby Integration Test\n');
    console.log('This test will:');
    console.log('  1. Create multiple rooms with different configurations');
    console.log('  2. Create GameStates for each room (registered in Lobby)');
    console.log('  3. Query all rooms and GameStates on-chain');
    console.log('  4. Verify the Lobby is tracking all room-to-game mappings\n');

    if (!process.env.ADMIN_PRIVATE_KEY) throw new Error("Missing ADMIN_PRIVATE_KEY");
    if (!process.env.USER_1 || !process.env.USER_2) throw new Error("Missing USER_1 or USER_2 mnemonics");
    const packageId = requireEnv("PACKAGE_ID", PACKAGE_ID);
    const lobbyId = requireEnv("LOBBY_ID", LOBBY_ID);
    const gameRegistry = requireEnv("GAME_REGISTRY", GAME_REGISTRY);
    const adminCap = requireEnv("ADMIN_CAP", ADMIN_CAP);
    const config = requireEnv("CONFIG", CONFIG);
    const gameCapId = requireEnv("GAME_CAP_ID", GAME_CAP_ID);

    const adminKp = Ed25519Keypair.fromSecretKey(decodeSuiPrivateKey(process.env.ADMIN_PRIVATE_KEY).secretKey);
    const player1Kp = Ed25519Keypair.deriveKeypair(process.env.USER_1);
    const player2Kp = Ed25519Keypair.deriveKeypair(process.env.USER_2);

    const adminAddr = adminKp.toSuiAddress();
    const p1Addr = player1Kp.toSuiAddress();
    const p2Addr = player2Kp.toSuiAddress();

    console.log(` Admin: ${adminAddr}`);
    console.log(`Player 1: ${p1Addr}`);
    console.log(`Player 2: ${p2Addr}\n`);



    console.log(`📋 Using Lobby ID: ${lobbyId}`);
    console.log(`📋 Using Game Registry: ${gameRegistry}`);
    console.log(`📋 Using Config: ${config}\n`);

    // Check balances
    console.log('💰 Checking balances...');
    async function checkBalance(addr: string, name: string) {
        const bal = await client.getBalance({ owner: addr, coinType: NATIVE_COIN_TYPE });
        console.log(`  ${name}: ${bal.totalBalance} OCT`);
    }
    await checkBalance(adminAddr, "Admin");
    await checkBalance(p1Addr, "Player 1");
    await checkBalance(p2Addr, "Player 2");

    // // Query initial state (no rooms created yet)
    // console.log('\n\n═══════════════════════════════════════════════════════');
    // console.log('INITIAL STATE - Before Creating Rooms');
    // console.log('═══════════════════════════════════════════════════════');
    // console.log('No rooms or GameStates created yet.');
    // await queryLobby(lobbyId);

    // // Create Room 1: Small stakes, 2 players
    // const room1 = await createRoomAndGame(
    //     player1Kp,
    //     lobbyId,
    //     gameRegistry,
    //     config,
    //     50_000_000, // 50 OCT
    //     2,
    //     "Room 1 (Small Stakes)"
    // );

    // // Create Room 2: Medium stakes, 4 players
    // const room2 = await createRoomAndGame(
    //     player2Kp,
    //     lobbyId,
    //     gameRegistry,
    //     config,
    //     100_000_000, // 100 OCT
    //     4,
    //     "Room 2 (Medium Stakes)"
    // );

    // // Create Room 3: High stakes, 8 players
    // const room3 = await createRoomAndGame(
    //     adminKp,
    //     lobbyId,
    //     gameRegistry,
    //     config,
    //     200_000_000, // 200 OCT
    //     8,
    //     "Room 3 (High Stakes)"
    // );

    // Wait for all indexing to complete
    console.log('\n\n⏳ Waiting 10s for final indexing...');
    await new Promise(r => setTimeout(r, 10000));

    // Query final state
    console.log('\n\n═══════════════════════════════════════════════════════');
    console.log('FINAL STATE - After Creating All Rooms');
    console.log('═══════════════════════════════════════════════════════');
    // const roomIds = [room1.roomId, room2.roomId, room3.roomId];
    // const gameStateIds = [room1.gameStateId, room2.gameStateId, room3.gameStateId];
    // const allRooms = await queryRooms(roomIds);
    // const allGameStates = await queryGameStates(gameStateIds);
    await queryLobby(lobbyId);
    // 1) List Lobby entries (room IDs)
    const fields = await client.getDynamicFields({
        parentId: "0x56bda8872572aa2f9223a4240003d0cf4cc412507ecf16562d1a902b544510f0", // lobby.room_to_game.fields.id
        limit: 50,
    });

    // 2) Extract room IDs
    const roomIds: string[] = fields.data.map((f) => f.name.value as string);

    // 3) Fetch room objects
    const rooms = await client.multiGetObjects({
        ids: roomIds,
        options: { showContent: true },
    });

    console.log(rooms);
    rooms.forEach((r) => {
        const content = r.data?.content;
        if (!content || content.dataType !== 'moveObject') return;
        const f = content.fields as any;
        const poolRaw = f.pool;
        const poolValue =
            typeof poolRaw === 'string'     
                ? poolRaw
                : poolRaw?.fields?.value ?? poolRaw?.value ?? '0';

        console.log({ pool: poolValue });
        console.log({
            id: r.data?.objectId,
            status: f.status?.variant,
            entryFee: f.entry_fee,
            maxPlayers: f.max_players,
            players: f.player_balances?.fields?.size,
            pool: f.pool?.fields?.value ?? f.pool?.value,
        });
    });
    // // Summary
    // console.log('\n\n═══════════════════════════════════════════════════════');
    // console.log('TEST SUMMARY');
    // console.log('═══════════════════════════════════════════════════════');
    // console.log(`✅ Created 3 rooms with different configurations`);
    // console.log(`✅ Created 3 GameStates (one for each room)`);
    // console.log(`✅ All rooms registered in Lobby`);
    // console.log(`\n📊 Total Rooms queried: ${allRooms.length}`);
    // console.log(`📊 Total GameStates queried: ${allGameStates.length}`);

    // console.log('\n\n🎯 Room-to-GameState Mappings:');
    // console.log(`  Room 1 → GameState: ${room1.gameStateId}`);
    // console.log(`  Room 2 → GameState: ${room2.gameStateId}`);
    // console.log(`  Room 3 → GameState: ${room3.gameStateId}`);

    // console.log('\n\n✅ Lobby Integration Test Complete!');
    // console.log('The Lobby module is successfully tracking all room-to-game mappings.');

    // // ========================================================================
    // // FULL GAME LIFECYCLE TEST
    // // ========================================================================
    // console.log('\n\n');
    // console.log('════════════════════════════════════════════════════════════');
    // console.log('🎮 STARTING FULL GAME LIFECYCLE TEST');
    // console.log('════════════════════════════════════════════════════════════');
    // console.log('This will test the complete game flow:');
    // console.log('  1. Join Room (Players)');
    // console.log('  2. Ready to Play (Players pay entry fee)');
    // console.log('  3. Start Room (Admin)');
    // console.log('  4. Start Round (Admin)');
    // console.log('  5. Pass Bomb (Players)');
    // console.log('  6. Try Explode (Bot/Admin)');
    // console.log('  7. Settle Round (Admin)');
    // console.log('  8. Reset Game (Admin)\n');

    // // Use Room 1 for the full test
    // const testRoomId = room1.roomId;
    // const testGameStateId = room1.gameStateId;

    // console.log(`🎯 Testing with Room: ${testRoomId}`);
    // console.log(`🎯 Testing with GameState: ${testGameStateId}\n`);

    // // Step 1: Join Room (Player 1 & 2)
    // console.log('\n--- Step 1: Join Room (P1 & P2) ---');

    // async function joinRoom(playerKp: Ed25519Keypair, name: string) {
    //     const tx = new Transaction();
    //     const addr = playerKp.toSuiAddress();

    //     // Gas Selection
    //     const coins = await client.getCoins({ owner: addr, coinType: NATIVE_COIN_TYPE });
    //     const gas = coins.data.sort((a, b) => Number(b.balance) - Number(a.balance))[0];
    //     if (gas) tx.setGasPayment([{ objectId: gas.coinObjectId, version: gas.version, digest: gas.digest }]);

    //     // 1. gamehub::join_room
    //     tx.moveCall({
    //         target: `${PACKAGE_ID}::gamehub::join_room`,
    //         arguments: [tx.object(testRoomId)],
    //         typeArguments: [COIN_TYPE]
    //     });
    //     // 2. bomb_panic::join
    //     tx.moveCall({
    //         target: `${PACKAGE_ID}::bomb_panic::join`,
    //         arguments: [tx.object(testGameStateId)],
    //         typeArguments: [COIN_TYPE]
    //     });
    //     tx.setGasBudget(GAS_BUDGET);
    //     return signAndExecute(playerKp, tx, `Join ${name}`);
    // }

    // await joinRoom(player1Kp, "Player 1");
    // await joinRoom(player2Kp, "Player 2");

    // console.log("⏳ Waiting 5s for indexing...");
    // await new Promise(r => setTimeout(r, 5000));

    // // Step 2: Ready to Play (Player 1 & 2)
    // console.log('\n--- Step 2: Ready to Play ---');

    // async function readyToPlay(playerKp: Ed25519Keypair, name: string) {
    //     const tx = new Transaction();
    //     const addr = playerKp.toSuiAddress();

    //     const coins = await client.getCoins({ owner: addr, coinType: NATIVE_COIN_TYPE });
    //     const gas = coins.data.sort((a, b) => Number(b.balance) - Number(a.balance))[0];
    //     if (gas) {
    //         console.log(`${name} using gas for ready: ${gas.coinObjectId}`);
    //         tx.setGasPayment([{ objectId: gas.coinObjectId, version: gas.version, digest: gas.digest }]);
    //     }

    //     // Split entry fee from gas
    //     const [feeCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(ENTRY_FEE)]);

    //     tx.moveCall({
    //         target: `${PACKAGE_ID}::gamehub::ready_to_play`,
    //         arguments: [tx.object(testRoomId), feeCoin],
    //         typeArguments: [COIN_TYPE]
    //     });
    //     tx.setGasBudget(GAS_BUDGET);
    //     return signAndExecute(playerKp, tx, `Ready ${name}`);
    // }

    // await readyToPlay(player1Kp, "Player 1");
    // await readyToPlay(player2Kp, "Player 2");

    // console.log("⏳ Waiting 5s for indexing...");
    // await new Promise(r => setTimeout(r, 5000));

    // // Step 3: Start Room (Admin/Backend)
    // console.log('\n--- Step 3: Start Room (GameHub) ---');

    // let tx = new Transaction();
    // let adminCoins = await client.getCoins({ owner: adminAddr, coinType: NATIVE_COIN_TYPE });
    // let adminGas = adminCoins.data.sort((a, b) => Number(b.balance) - Number(a.balance))[0];
    // if (adminGas) tx.setGasPayment([{ objectId: adminGas.coinObjectId, version: adminGas.version, digest: adminGas.digest }]);

    // tx.moveCall({
    //     target: `${PACKAGE_ID}::gamehub::start_room`,
    //     arguments: [
    //         tx.object(testRoomId),
    //         tx.object(adminCap),
    //         tx.object(config)
    //     ],
    //     typeArguments: [COIN_TYPE]
    // });
    // tx.setGasBudget(GAS_BUDGET);

    // await signAndExecute(adminKp, tx, "Start Room");

    // console.log("⏳ Waiting 5s for indexing...");
    // await new Promise(r => setTimeout(r, 5000));

    // // Get pool value for start_round
    // const roomState = await client.getObject({ id: testRoomId, options: { showContent: true } });
    // const poolValue = (roomState.data?.content as any)?.fields?.pool?.fields?.value || '0';
    // console.log(`💰 Current Pool Value: ${poolValue} OCT`);

    // // Step 4: Start Round (Bomb Panic)
    // console.log('\n--- Step 4: Start Round (Bomb Panic) ---');

    // tx = new Transaction();
    // adminCoins = await client.getCoins({ owner: adminAddr, coinType: NATIVE_COIN_TYPE });
    // adminGas = adminCoins.data.sort((a, b) => Number(b.balance) - Number(a.balance))[0];
    // if (adminGas) tx.setGasPayment([{ objectId: adminGas.coinObjectId, version: adminGas.version, digest: adminGas.digest }]);

    // tx.moveCall({
    //     target: `${PACKAGE_ID}::bomb_panic::start_round`,
    //     arguments: [
    //         tx.object(RANDOM_ID),
    //         tx.object(testGameStateId),
    //         tx.object(testRoomId),
    //         tx.object(CLOCK_ID)
    //     ],
    //     typeArguments: [COIN_TYPE]
    // });
    // tx.setGasBudget(GAS_BUDGET);

    // const startResult = await signAndExecute(adminKp, tx, "Start Round");
    // logStructure("Start Round Events", startResult.events);

    // console.log("⏳ Waiting 5s for indexing...");
    // await new Promise(r => setTimeout(r, 5000));

    // const playingGame = await client.getObject({ id: testGameStateId, options: { showContent: true } });
    // logStructure("GameState (Playing)", playingGame);

    // const holder = (playingGame.data?.content as any)?.fields?.bomb_holder;
    // console.log(`💣 Initial Bomb Holder: ${holder}`);

    // // Step 5: Pass Bomb
    // console.log('\n--- Step 5: Pass Bomb ---');
    // const holderKp = p1Addr === holder ? player1Kp : player2Kp;
    // const holderName = p1Addr === holder ? "Player 1" : "Player 2";

    // tx = new Transaction();
    // const hAddr = holderKp.toSuiAddress();
    // const hCoins = await client.getCoins({ owner: hAddr, coinType: NATIVE_COIN_TYPE });
    // const hGas = hCoins.data.sort((a, b) => Number(b.balance) - Number(a.balance))[0];
    // if (hGas) tx.setGasPayment([{ objectId: hGas.coinObjectId, version: hGas.version, digest: hGas.digest }]);

    // tx.moveCall({
    //     target: `${PACKAGE_ID}::bomb_panic::pass_bomb`,
    //     arguments: [
    //         tx.object(RANDOM_ID),
    //         tx.object(testGameStateId),
    //         tx.object(CLOCK_ID)
    //     ],
    //     typeArguments: [COIN_TYPE]
    // });
    // tx.setGasBudget(GAS_BUDGET);

    // console.log(`${holderName} passing bomb...`);
    // const passResult = await signAndExecute(holderKp, tx, "Pass Bomb");
    // logStructure("Pass Bomb Events", passResult.events);

    // console.log("⏳ Waiting 3s...");
    // await new Promise(r => setTimeout(r, 3000));

    // // Step 6: Try Explode Loop
    // console.log('\n--- Step 6: Game Loop (Try Explode) ---');
    // let exploded = false;
    // let attempts = 0;
    // const maxAttempts = 20;

    // while (!exploded && attempts < maxAttempts) {
    //     console.log(`💥 Attempt ${attempts + 1}/${maxAttempts}...`);
    //     tx = new Transaction();

    //     adminCoins = await client.getCoins({ owner: adminAddr, coinType: NATIVE_COIN_TYPE });
    //     adminGas = adminCoins.data.sort((a, b) => Number(b.balance) - Number(a.balance))[0];
    //     if (adminGas) tx.setGasPayment([{ objectId: adminGas.coinObjectId, version: adminGas.version, digest: adminGas.digest }]);

    //     tx.moveCall({
    //         target: `${PACKAGE_ID}::bomb_panic::try_explode`,
    //         arguments: [
    //             tx.object(testGameStateId),
    //             tx.object(CLOCK_ID),
    //             tx.object(RANDOM_ID)
    //         ],
    //         typeArguments: [COIN_TYPE]
    //     });
    //     tx.setGasBudget(GAS_BUDGET);

    //     const explodeResult = await signAndExecute(adminKp, tx, `Try Explode #${attempts + 1}`);

    //     const explodeEvent = explodeResult.events?.find(e => e.type.includes('::Exploded'));
    //     const victoryEvent = explodeResult.events?.find(e => e.type.includes('::Victory'));

    //     if (explodeEvent || victoryEvent) {
    //         console.log("💥💥💥 Explosion or Victory Detected! 💥💥💥");
    //         logStructure("End Game Event", explodeEvent || victoryEvent);
    //         exploded = true;
    //     } else {
    //         console.log("... Tick tock ...");
    //         await new Promise(r => setTimeout(r, 1000));
    //     }
    //     attempts++;
    // }

    // if (!exploded) {
    //     console.warn(`⚠️  No explosion after ${maxAttempts} attempts. Continuing anyway...`);
    // }

    // // Step 7: Settle Game
    // console.log('\n--- Step 7: Settle Round (Internal Flow) ---');
    // console.log("⏳ Waiting 10s for indexing before settlement...");
    // await new Promise(r => setTimeout(r, 10000));

    // const endedGame = await client.getObject({ id: testGameStateId, options: { showContent: true } });
    // logStructure("GameState (Before Settlement)", endedGame);

    // tx = new Transaction();
    // adminCoins = await client.getCoins({ owner: adminAddr, coinType: NATIVE_COIN_TYPE });
    // adminGas = adminCoins.data.sort((a, b) => Number(b.balance) - Number(a.balance))[0];
    // if (adminGas) tx.setGasPayment([{ objectId: adminGas.coinObjectId, version: adminGas.version, digest: adminGas.digest }]);

    // // Internal settlement call
    // tx.moveCall({
    //     target: `${PACKAGE_ID}::bomb_panic::settle_round_with_hub`,
    //     arguments: [
    //         tx.object(testGameStateId),  // GameState
    //         tx.object(testRoomId),       // Room
    //         tx.object(gameCapId)         // GameCap
    //     ],
    //     typeArguments: [COIN_TYPE]
    // });
    // tx.setGasBudget(GAS_BUDGET);

    // const settleResult = await signAndExecute(adminKp, tx, "Settle Round");

    // // Log the RoundSettled event
    // const roundSettledEvent = settleResult.events?.find(e => e.type.includes('::RoundSettled'));
    // if (roundSettledEvent) {
    //     console.log("🎯 RoundSettled Event Detected!");
    //     logStructure("RoundSettled Event", roundSettledEvent);
    // } else {
    //     console.warn("⚠️  No RoundSettled event found");
    // }

    // console.log("⏳ Waiting 5s for indexing...");
    // await new Promise(r => setTimeout(r, 5000));

    // // Step 8: Reset Game
    // console.log('\n--- Step 8: Reset Game ---');
    // tx = new Transaction();
    // adminCoins = await client.getCoins({ owner: adminAddr, coinType: NATIVE_COIN_TYPE });
    // adminGas = adminCoins.data.sort((a, b) => Number(b.balance) - Number(a.balance))[0];
    // if (adminGas) tx.setGasPayment([{ objectId: adminGas.coinObjectId, version: adminGas.version, digest: adminGas.digest }]);

    // tx.moveCall({
    //     target: `${PACKAGE_ID}::bomb_panic::reset_game`,
    //     arguments: [tx.object(testGameStateId)],
    //     typeArguments: [COIN_TYPE]
    // });
    // tx.setGasBudget(GAS_BUDGET);

    // await signAndExecute(adminKp, tx, "Reset Game");

    // console.log("⏳ Waiting 5s for indexing...");
    // await new Promise(r => setTimeout(r, 5000));

    // const resetGame = await client.getObject({ id: testGameStateId, options: { showContent: true } });
    // logStructure("GameState (After Reset)", resetGame);

    // console.log('\n\n════════════════════════════════════════════════════════════');
    // console.log('✅✅✅ FULL INTEGRATION TEST COMPLETE! ✅✅✅');
    // console.log('════════════════════════════════════════════════════════════');
    // console.log('Successfully tested:');
    // console.log('  ✅ Lobby tracking of room-to-game mappings');
    // console.log('  ✅ Room creation and GameState initialization');
    // console.log('  ✅ Player joining and readying');
    // console.log('  ✅ Room and round starting');
    // console.log('  ✅ Bomb passing mechanics');
    // console.log('  ✅ Explosion and victory detection');
    // console.log('  ✅ Settlement and payout distribution');
    // console.log('  ✅ Game reset for next round');
    // console.log('════════════════════════════════════════════════════════════\n');
}

main().catch(console.error);
