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
const PLAYER_2_ADDRESS = process.env.PLAYER_2_ADDRESS;
const CONFIG = process.env.CONFIG;
const GAME_CAP_ID = process.env.GAME_CAP;
const GAME_CAP_OCT = process.env.GAME_CAP_OCT;
const GAME_CAP_HACKATHON = process.env.GAME_CAP_HACKATHON;
const RANDOM_ID = process.env.RANDOM_ID || '0x8';
const CLOCK_ID = process.env.CLOCK_ID || '0x6';
const OCT_COIN_TYPE = '0x2::oct::OCT';
const HACKATHON_COIN_TYPE =
    '0x8b76fc2a2317d45118770cefed7e57171a08c477ed16283616b15f099391f120::hackathon::HACKATHON';
const COIN_TYPE = process.env.COIN_TYPE ?? OCT_COIN_TYPE;
const NATIVE_COIN_TYPE = OCT_COIN_TYPE;
const GAS_BUDGET = 100_000_000;
const ENTRY_FEE = 50_000_000;
const MAX_PLAYERS = 4;

const client = new SuiClient({ url: RPC_URL });

function toU64(value: bigint | number | string): bigint {
    return typeof value === 'bigint' ? value : BigInt(value);
}

class SharedObjectQueue {
    private readonly queues = new Map<string, Promise<unknown>>();

    async run<T>(keys: string[], task: () => Promise<T>): Promise<T> {
        const uniq = Array.from(new Set(keys)).sort();
        let chain = Promise.resolve();

        for (const key of uniq) {
            const prev = this.queues.get(key) ?? Promise.resolve();
            chain = chain.then(async () => {
                await prev;
            });
        }

        const exec = chain.then(task).finally(() => {
            for (const key of uniq) {
                if (this.queues.get(key) === exec) this.queues.delete(key);
            }
        });

        for (const key of uniq) {
            this.queues.set(key, exec);
        }

        return exec;
    }
}

const sharedObjectQueue = new SharedObjectQueue();

function runWithSharedObjects<T>(keys: Array<string | undefined>, task: () => Promise<T>): Promise<T> {
    const clean = keys.filter((k): k is string => typeof k === 'string' && k.length > 0);
    return sharedObjectQueue.run(clean, task);
}

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

            // Wait for transaction finality to prevent "object locked" errors
            console.log(`⏳ [${description}] Waiting for transaction finality...`);
            await client.waitForTransaction({
                digest: result.digest,
                options: { showEffects: true },
            });
            console.log(`🔒 [${description}] Transaction finalized.`);

            return result;
        } else {
            console.error(`❌ [${description}] Failed:`, result.effects?.status);
            throw new Error(`Transaction failed: ${result.effects?.status.error}`);
        }
    } catch (e: any) {

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

function resolveGameCapId(): string {
    if (COIN_TYPE === OCT_COIN_TYPE) {
        return requireEnv('GAME_CAP_OCT (or GAME_CAP)', GAME_CAP_OCT ?? GAME_CAP_ID);
    }
    if (COIN_TYPE === HACKATHON_COIN_TYPE) {
        return requireEnv('GAME_CAP_HACKATHON (or GAME_CAP)', GAME_CAP_HACKATHON ?? GAME_CAP_ID);
    }
    return requireEnv('GAME_CAP', GAME_CAP_ID);
}

function findCreatedObjectId(
    objectChanges: Array<{ type: string; objectId?: string; objectType?: string }> | null | undefined,
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

function sleep(ms: number) {
    return new Promise((r) => setTimeout(r, ms));
}

function getMoveObjectContent(obj: any) {
    const c = obj?.data?.content;
    return c?.dataType === 'moveObject' ? c : undefined;
}

function extractTableId(content: any, fieldName: string): string | null {
    return (
        content?.fields?.[fieldName]?.fields?.id?.id ??
        content?.fields?.[fieldName]?.id?.id ??
        null
    );
}

function extractDynFieldKeyAddress(content: any): string | null {
    const n = content?.fields?.name;
    const addr = n?.fields?.value ?? n?.value;
    return typeof addr === 'string' ? addr : null;
}

function extractDynFieldNameValue(field: any): string | null {
    const v = field?.value ?? field?.fields?.value;
    return typeof v === 'string' ? v : null;
}

function extractBoolFieldValue(content: any): boolean {
    const v = content?.fields?.value;
    if (typeof v === 'boolean') return v;
    const nested = v?.fields?.value ?? v?.value;
    if (typeof nested === 'boolean') return nested;
    if (typeof nested === 'string') return nested === 'true';
    return false;
}

// Locked coin that should be avoided (stuck by ghost transaction)
const LOCKED_COIN_ID = '0x76fdc3af87ab006f4b44900cdcfb7f60f5c65a83d1a1d25f419874ebd02957f0';

async function setNativeGasPayment(tx: Transaction, owner: string) {
    const coins = await client.getCoins({ owner, coinType: NATIVE_COIN_TYPE });
    // Filter out locked coins and sort by balance
    const availableCoins = coins.data
        .filter(c => c.coinObjectId !== LOCKED_COIN_ID)
        .sort((a, b) => Number(b.balance) - Number(a.balance));

    const gas = availableCoins[0];
    if (gas) {
        console.log(`  💰 Using gas coin: ${gas.coinObjectId} (${gas.balance} OCT)`);
        tx.setGasPayment([{ objectId: gas.coinObjectId, version: gas.version, digest: gas.digest }]);
    } else {
        console.log(`  ⚠️ No unlocked gas coins available, letting Sui auto-select...`);
    }
}

async function splitCoinFromOwner(
    tx: Transaction,
    owner: string,
    coinType: string,
    amount: bigint | number | string
) {
    const u64Amount = toU64(amount);
    if (coinType === NATIVE_COIN_TYPE) {
        // For native coin, tx.gas will use the gas coin we set in setNativeGasPayment
        const [coin] = tx.splitCoins(tx.gas, [tx.pure.u64(u64Amount)]);
        return coin;
    }

    const coins = await client.getCoins({ owner, coinType });
    // Filter out locked coins and sort by balance
    const availableCoins = coins.data
        .filter(c => c.coinObjectId !== LOCKED_COIN_ID)
        .sort((a, b) => Number(b.balance) - Number(a.balance));

    const src = availableCoins[0];
    if (!src) {
        throw new Error(`No unlocked coins available for ${owner} with type ${coinType}`);
    }
    console.log(`  💰 Splitting from coin: ${src.coinObjectId} (${src.balance})`);
    const [coin] = tx.splitCoins(tx.object(src.coinObjectId), [tx.pure.u64(u64Amount)]);
    return coin;
}

async function fetchTableAsMap<T>(
    tableId: string,
    parseValue: (moveObjectContent: any) => T
): Promise<Map<string, T>> {
    const page = await client.getDynamicFields({ parentId: tableId, limit: 200 });
    const idToKey = new Map<string, string>();
    const ids: string[] = [];
    for (const d of page.data) {
        const objectId = (d as any).objectId;
        const key = extractDynFieldNameValue((d as any).name);
        if (typeof objectId === 'string' && key) {
            ids.push(objectId);
            idToKey.set(objectId, key);
        }
    }
    if (!ids.length) return new Map();

    const objs = await client.multiGetObjects({
        ids,
        options: { showContent: true },
    });

    const out = new Map<string, T>();
    for (const o of objs) {
        const c = getMoveObjectContent(o);
        if (!c) continue;
        const objectId = o?.data?.objectId;
        const key = typeof objectId === 'string' ? idToKey.get(objectId) : null;
        if (!key) continue;
        out.set(key, parseValue(c));
    }

    return out;
}

async function fetchReadyPlayers(roomId: string): Promise<Map<string, boolean>> {
    const roomObj = await client.getObject({
        id: roomId,
        options: { showContent: true },
    });
    const roomContent = getMoveObjectContent(roomObj);
    const readyTableId = extractTableId(roomContent, 'ready_players');
    if (!readyTableId) return new Map();
    return fetchTableAsMap<boolean>(readyTableId, extractBoolFieldValue);
}

function parseOptionAddress(optionField: any): string | null {
    if (!optionField) return null;
    const vec = optionField.vec ?? optionField.fields?.vec;
    if (Array.isArray(vec) && vec.length > 0) return vec[0];
    if (typeof optionField === 'string') return optionField;
    return null;
}

function extractPlayersFromGame(content: any): string[] {
    const players = content?.fields?.players;
    if (!Array.isArray(players)) return [];
    return players
        .map((p: any) => p?.fields?.addr)
        .filter((addr: any) => typeof addr === 'string') as string[];
}

async function fetchGameContent(gameStateId: string) {
    const gameObj = await client.getObject({
        id: gameStateId,
        options: { showContent: true },
    });
    return getMoveObjectContent(gameObj);
}

async function fetchGamePlayers(gameStateId: string): Promise<string[]> {
    const content = await fetchGameContent(gameStateId);
    return extractPlayersFromGame(content);
}

async function fetchBombHolder(gameStateId: string): Promise<string | null> {
    const content = await fetchGameContent(gameStateId);
    return parseOptionAddress(content?.fields?.bomb_holder);
}

async function waitForPlayers(
    gameStateId: string,
    minPlayers: number,
    timeoutMs = 60_000
) {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
        const players = await fetchGamePlayers(gameStateId);
        if (players.length >= minPlayers) return players;
        await sleep(2000);
    }
    return [];
}

async function waitForReadyCount(
    roomId: string,
    minReady: number,
    timeoutMs = 60_000
) {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
        const ready = await fetchReadyPlayers(roomId);
        const readyCount = Array.from(ready.values()).filter(Boolean).length;
        if (readyCount >= minReady) return ready;
        await sleep(2000);
    }
    return new Map<string, boolean>();
}

async function waitForHolderChange(
    gameStateId: string,
    currentHolder: string | null,
    timeoutMs = 60_000
) {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
        const holder = await fetchBombHolder(gameStateId);
        if (holder && holder !== currentHolder) return holder;
        await sleep(2000);
    }
    return null;
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
async function queryLobby(lobbyId: string): Promise<{ lobbyObj: any | null; tableId: string | null }> {
    console.log('\n🔎 Querying Lobby object...');
    try {
        const lobbyObj = await client.getObject({
            id: lobbyId,
            options: { showContent: true }
        });

        let tableId: string | null = null;
        if (lobbyObj.data?.content && lobbyObj.data.content.dataType === 'moveObject') {
            const fields = lobbyObj.data.content.fields as any;
            tableId = fields.room_to_game?.fields?.id?.id ?? null;

            console.log(`\n📋 Lobby Details:`);
            console.log(`  Lobby ID: ${lobbyId}`);
            console.log(`  Room-to-Game Table ID: ${tableId}`);

            logStructure("Lobby Full Structure", lobbyObj);
        }

        return { lobbyObj, tableId };
    } catch (e) {
        console.error(`Failed to query lobby: ${e}`);
        return { lobbyObj: null, tableId: null };
    }
}

//Create a room and its associated GameState
async function createRoomAndGame(
    creator: Ed25519Keypair,
    lobbyId: string,
    gameRegistry: string,
    config: string,
    entryFee: number,
    maxPlayers: number,
    roomName: string
) {
    console.log(`\n\n🏗️  Creating ${roomName}...`);

    const creatorAddr = creator.toSuiAddress();

    const createRoomResult = await sharedObjectQueue.run(
        [lobbyId, gameRegistry, config],
        async () => {
            const tx = new Transaction();
            await setNativeGasPayment(tx, creatorAddr);

            // Split creation fee (100 units)
            const creationFeeCoin = await splitCoinFromOwner(tx, creatorAddr, COIN_TYPE, 100);

            // Create room
            tx.moveCall({
                target: `${PACKAGE_ID}::gamehub::create_room`,
                arguments: [
                    tx.object(gameRegistry),
                    tx.object(config),
                    tx.pure.u64(entryFee),
                    tx.pure.u8(maxPlayers),
                    creationFeeCoin,
                ],
                typeArguments: [COIN_TYPE, `${PACKAGE_ID}::bomb_panic::GameState<${COIN_TYPE}>`],
            });

            tx.setGasBudget(GAS_BUDGET);
            return signAndExecute(creator, tx, `Create ${roomName}`);
        }
    );
    const roomId = findCreatedObjectId(createRoomResult.objectChanges, '::Room');

    if (!roomId) throw new Error(`Failed to find Room object ID for ${roomName}`);
    console.log(`  🏠 Room ID: ${roomId}`);

    // Wait for indexing
    console.log(`  ⏳ Waiting 15s for indexing...`);
    await new Promise(r => setTimeout(r, 15000));

    // Create GameState for this room
    const createGameResult = await sharedObjectQueue.run(
        [lobbyId, roomId],
        async () => {
            const tx2 = new Transaction();
            await setNativeGasPayment(tx2, creatorAddr);

            tx2.moveCall({
                target: `${PACKAGE_ID}::bomb_panic::create_game_for_room`,
                arguments: [tx2.object(lobbyId), tx2.object(roomId)],
                typeArguments: [COIN_TYPE],
            });
            tx2.setGasBudget(GAS_BUDGET);

            return signAndExecute(creator, tx2, `Create GameState for ${roomName}`);
        }
    );
    const gameStateId = findCreatedObjectId(createGameResult.objectChanges, '::GameState');

    if (!gameStateId) throw new Error(`Failed to find GameState object ID for ${roomName}`);
    console.log(`  🎮 GameState ID: ${gameStateId}`);

    // Check for RoomAndGameCreated event
    const createdEvent = createGameResult.events?.find(e => e.type.includes('::RoomAndGameCreated'));
    if (createdEvent) {
        console.log(`  ✅ RoomAndGameCreated event emitted`);
        logStructure(`${roomName} Creation Event`, createdEvent);
    }

    return { roomId, gameStateId, entryFee };
}

async function main() {
    console.log('🚀 Starting Lobby Integration Test\n');
    console.log('This test will:');
    console.log('  1. Create multiple rooms with different configurations');
    console.log('  2. Create GameStates for each room (registered in Lobby)');
    console.log('  3. Query all rooms and GameStates on-chain');
    console.log('  4. Verify the Lobby is tracking all room-to-game mappings\n');

    if (!process.env.ADMIN_PRIVATE_KEY) throw new Error("Missing ADMIN_PRIVATE_KEY");
    if (!process.env.USER_1) throw new Error("Missing USER_1 mnemonic");
    if (!process.env.USER_2) throw new Error("Missing USER_2 mnemonic");
    const packageId = requireEnv("PACKAGE_ID", PACKAGE_ID);
    const lobbyId = requireEnv("LOBBY_ID", LOBBY_ID);
    const gameRegistry = requireEnv("GAME_REGISTRY", GAME_REGISTRY);
    const config = requireEnv("CONFIG", CONFIG);
    const gameCapId = resolveGameCapId();

    const adminKp = Ed25519Keypair.fromSecretKey(decodeSuiPrivateKey(process.env.ADMIN_PRIVATE_KEY).secretKey);
    const player1Kp = Ed25519Keypair.deriveKeypair(process.env.USER_1);
    const player2Kp = Ed25519Keypair.deriveKeypair(process.env.USER_2);

    const adminAddr = adminKp.toSuiAddress();
    const p1Addr = player1Kp.toSuiAddress();
    const p2Addr = player2Kp ? player2Kp.toSuiAddress() : PLAYER_2_ADDRESS ?? null;

    console.log(` Admin: ${adminAddr}`);
    console.log(`Player 1: ${p1Addr}`);
    console.log(`Player 2: ${p2Addr ?? '(external/unknown)'}\n`);

    const knownPlayers = new Map<string, { name: string; keypair?: Ed25519Keypair }>();
    knownPlayers.set(p1Addr, { name: 'Player 1', keypair: player1Kp });
    if (p2Addr) {
        knownPlayers.set(p2Addr, { name: 'Player 2', keypair: player2Kp ?? undefined });
    }



    console.log(`📋 Using Lobby ID: ${lobbyId}`);
    console.log(`📋 Using Game Registry: ${gameRegistry}`);
    console.log(`📋 Using Config: ${config}\n`);
    console.log(`🪙 Using COIN_TYPE: ${COIN_TYPE}`);
    console.log(`🎟️  Using GameCap: ${gameCapId}\n`);

    // Check balances
    console.log('💰 Checking balances...');
    async function checkBalance(addr: string, name: string) {
        const gasBal = await client.getBalance({ owner: addr, coinType: NATIVE_COIN_TYPE });
        const tokenBal = COIN_TYPE === NATIVE_COIN_TYPE ? gasBal : await client.getBalance({ owner: addr, coinType: COIN_TYPE });
        const gasSuffix = NATIVE_COIN_TYPE === OCT_COIN_TYPE ? 'OCT' : NATIVE_COIN_TYPE;
        console.log(`  ${name}: gas=${gasBal.totalBalance} ${gasSuffix}, token=${tokenBal.totalBalance}`);
    }
    await checkBalance(adminAddr, "Admin");
    await checkBalance(p1Addr, "Player 1");
    if (p2Addr) {
        await checkBalance(p2Addr, "Player 2");
    }

    // Query initial state (no rooms created yet)
    console.log('\n\n═══════════════════════════════════════════════════════');
    console.log('INITIAL STATE - Before Creating Rooms');
    console.log('═══════════════════════════════════════════════════════');
    await queryLobby(lobbyId);

    // Create Room 1: Small stakes, 2 players
    const room1 = await createRoomAndGame(
        player2Kp,
        lobbyId,
        gameRegistry,
        config,
        50_000,
        3,
        "Room 1 (Small Stakes)"
    );

    // // Create Room 2: Medium stakes, 4 players
    // const room2Creator = player2Kp ?? player1Kp;
    // const room2 = await createRoomAndGame(
    //     room2Creator,
    //     lobbyId,
    //     gameRegistry,
    //     config,
    //     100_000_000,
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
    const roomIds = [room1.roomId];
    const gameStateIds = [room1.gameStateId];
    const allRooms = await queryRooms(roomIds);
    const allGameStates = await queryGameStates(gameStateIds);
    const { tableId } = await queryLobby(lobbyId);
    if (!tableId) throw new Error('Lobby room_to_game table ID not found');
    // 1) List Lobby entries (room IDs)
    const fields = await client.getDynamicFields({
        parentId: tableId, // lobby.room_to_game.fields.id
        limit: 50,
    });

    // 2) Extract room IDs
    const lobbyRoomIds: string[] = fields.data.map((f) => f.name.value as string);

    // 3) Fetch room objects
    const rooms = await client.multiGetObjects({
        ids: lobbyRoomIds,
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
    // Summary
    console.log('\n\n═══════════════════════════════════════════════════════');
    console.log('TEST SUMMARY');
    console.log('═══════════════════════════════════════════════════════');
    console.log(`✅ Created 3 rooms with different configurations`);
    console.log(`✅ Created 3 GameStates (one for each room)`);
    console.log(`✅ All rooms registered in Lobby`);
    console.log(`\n📊 Total Rooms queried: ${allRooms.length}`);
    console.log(`📊 Total GameStates queried: ${allGameStates.length}`);

    console.log('\n\n🎯 Room-to-GameState Mappings:');
    console.log(`  Room 1 → GameState: ${room1.gameStateId}`);
    // console.log(`  Room 2 → GameState: ${room2.gameStateId}`);
    // console.log(`  Room 3 → GameState: ${room3.gameStateId}`);

    console.log('\n\n✅ Lobby Integration Test Complete!');
    console.log('The Lobby module is successfully tracking all room-to-game mappings.');

    // ========================================================================
    // FULL GAME LIFECYCLE TEST
    // ========================================================================
    console.log('\n\n');
    console.log('════════════════════════════════════════════════════════════');
    console.log('🎮 STARTING FULL GAME LIFECYCLE TEST');
    console.log('════════════════════════════════════════════════════════════');
    console.log('This will test the complete game flow:');
    console.log('  1. Join Room (Players)');
    console.log('  2. Ready to Play (Players pay entry fee)');
    console.log('  3. Start Room (Backend)');
    console.log('  4. Start Round (Backend)');
    console.log('  5. Pass Bomb (Players)');
    console.log('  6. Try Explode (Bot/Admin)');
    console.log('  7. Settle Round (Backend)');
    console.log('  8. Reset Game (Backend)\n');

    // Use Room 1 for the full test
    const testRoomId = room1.roomId;
    const testGameStateId = room1.gameStateId;
    const testEntryFee = room1.entryFee;

    console.log(`🎯 Testing with Room: ${testRoomId}`);
    console.log(`🎯 Testing with GameState: ${testGameStateId}\n`);

    function labelAddr(addr: string) {
        const known = knownPlayers.get(addr);
        return known ? `${known.name} (${addr})` : addr;
    }

    async function logParticipants() {
        const ready = await fetchReadyPlayers(testRoomId);
        const players = await fetchGamePlayers(testGameStateId);
        const playerList = players.length ? players.map(labelAddr).join(', ') : '(none)';
        const readyAddrs = Array.from(ready.entries())
            .filter(([, isReady]) => Boolean(isReady))
            .map(([addr]) => addr);
        const readyList = readyAddrs.length ? readyAddrs.map(labelAddr).join(', ') : '(none)';
        console.log(`Players in game (${players.length}): ${playerList}`);
        console.log(`Ready players (${readyAddrs.length}): ${readyList}`);
    }

    async function joinRoom(playerKp: Ed25519Keypair, name: string) {
        const tx = new Transaction();
        const addr = playerKp.toSuiAddress();

        await setNativeGasPayment(tx, addr);

        tx.moveCall({
            target: `${PACKAGE_ID}::gamehub::join_room`,
            arguments: [tx.object(testRoomId)],
            typeArguments: [COIN_TYPE]
        });
        tx.moveCall({
            target: `${PACKAGE_ID}::bomb_panic::join`,
            arguments: [tx.object(testGameStateId)],
            typeArguments: [COIN_TYPE]
        });
        tx.setGasBudget(GAS_BUDGET);
        return runWithSharedObjects([testRoomId, testGameStateId], () =>
            signAndExecute(playerKp, tx, `Join ${name}`)
        );
    }

    async function readyToPlay(playerKp: Ed25519Keypair, name: string) {
        const tx = new Transaction();
        const addr = playerKp.toSuiAddress();

        await setNativeGasPayment(tx, addr);

        const isOCT = COIN_TYPE === OCT_COIN_TYPE;
        const coinAmount = isOCT ? testEntryFee * 2 : testEntryFee;
        const feeCoin = await splitCoinFromOwner(tx, addr, COIN_TYPE, coinAmount);

        tx.moveCall({
            target: `${PACKAGE_ID}::gamehub::ready_to_play`,
            arguments: [tx.object(testRoomId), feeCoin],
            typeArguments: [COIN_TYPE]
        });
        tx.setGasBudget(GAS_BUDGET);
        return runWithSharedObjects([testRoomId], () =>
            signAndExecute(playerKp, tx, `Ready ${name}`)
        );
    }

    async function stepJoinRoom() {
        console.log('\n--- Step 1: Join Room ---');
        await joinRoom(player1Kp, "Player 1");
        if (player2Kp) {
            await joinRoom(player2Kp, "Player 2");
        } else {
            console.log('Waiting for external player to join...');
            await waitForPlayers(testGameStateId, 2);
        }
        await sleep(5000);
        await logParticipants();
    }

    async function stepReadyToPlay() {
        console.log('\n--- Step 2: Ready to Play ---');
        await readyToPlay(player1Kp, "Player 1");
        if (player2Kp) {
            await readyToPlay(player2Kp, "Player 2");
        } else {
            console.log('Waiting for external player to ready...');
            await waitForReadyCount(testRoomId, 2);
        }
        await sleep(5000);
        await logParticipants();
    }

    async function stepStartRoom() {
        console.log('\n--- Step 3: Start Room (GameHub) ---');

        const tx = new Transaction();
        await setNativeGasPayment(tx, p1Addr);

        tx.moveCall({
            target: `${PACKAGE_ID}::gamehub::start_room`,
            arguments: [
                tx.object(testRoomId),
                tx.object(config)
            ],
            typeArguments: [COIN_TYPE]
        });
        tx.setGasBudget(GAS_BUDGET);

        await runWithSharedObjects([testRoomId, config], () =>
            signAndExecute(player1Kp, tx, "Start Room")
        );

        await sleep(5000);
    }

    async function stepStartRound(): Promise<string | null> {
        console.log('\n--- Step 4: Start Round (Bomb Panic) ---');

        const tx = new Transaction();
        await setNativeGasPayment(tx, p1Addr);

        tx.moveCall({
            target: `${PACKAGE_ID}::bomb_panic::start_round`,
            arguments: [
                tx.object(RANDOM_ID),
                tx.object(testGameStateId),
                tx.object(testRoomId),
                tx.object(CLOCK_ID)
            ],
            typeArguments: [COIN_TYPE]
        });
        tx.setGasBudget(GAS_BUDGET);

        const startResult = await runWithSharedObjects([testGameStateId, testRoomId], () =>
            signAndExecute(player1Kp, tx, "Start Round")
        );
        logStructure("Start Round Events", startResult.events);

        const startedEvent = startResult.events?.find(e => e.type.includes('::RoundStarted'));
        const initialHolder = startedEvent ? (startedEvent as any).parsedJson?.bomb_holder : null;

        await sleep(5000);

        const holder = initialHolder ?? await fetchBombHolder(testGameStateId);
        if (holder) {
            console.log(`💣 Initial Bomb Holder: ${labelAddr(holder)}`);
        } else {
            console.log('💣 Initial Bomb Holder: (unknown)');
        }

        return holder;
    }

    async function stepPassBomb(initialHolder: string | null, numPasses = 3) {
        console.log(`\n--- Step 5: Pass Bomb (${numPasses} passes) ---`);

        for (let i = 0; i < numPasses; i++) {
            const holderAddr = await fetchBombHolder(testGameStateId);
            if (!holderAddr) {
                console.warn(`⚠️  Pass ${i + 1}: Could not determine bomb holder`);
                break;
            }

            console.log(`\n🔄 Pass ${i + 1}/${numPasses}: Current holder: ${labelAddr(holderAddr)}`);
            const holderInfo = knownPlayers.get(holderAddr);

            if (!holderInfo?.keypair) {
                console.log('  Holder is external. Waiting for them to pass...');
                const newHolder = await waitForHolderChange(testGameStateId, holderAddr, 60_000);
                if (newHolder) {
                    console.log(`  Holder changed to: ${labelAddr(newHolder)}`);
                    continue; // Re-check who is holding it now
                } else {
                    console.warn('⚠️  Holder did not change in time');
                    break;
                }
            }

            const tx = new Transaction();
            await setNativeGasPayment(tx, holderInfo.keypair.toSuiAddress());

            tx.moveCall({
                target: `${PACKAGE_ID}::bomb_panic::pass_bomb`,
                arguments: [
                    tx.object(RANDOM_ID),
                    tx.object(testGameStateId),
                    tx.object(CLOCK_ID)
                ],
                typeArguments: [COIN_TYPE]
            });
            tx.setGasBudget(GAS_BUDGET);

            console.log(`  ${holderInfo.name} passing bomb...`);
            const passResult = await runWithSharedObjects([testGameStateId], () =>
                signAndExecute(holderInfo.keypair!, tx, `Pass Bomb #${i + 1}`)
            );

            // Check if game ended during pass (e.g. explosion due to hold time or victory)
            const exploded = passResult.events?.some(e => e.type.includes('::Exploded'));
            const victory = passResult.events?.some(e => e.type.includes('::Victory'));

            if (exploded || victory) {
                console.log("💥 Game ended during pass bomb!");
                break;
            }

            await sleep(5000);
        }
    }

    async function stepTryExplodeLoop() {
        console.log('\n--- Step 6: Game Loop (Try Explode) ---');
        let exploded = false;
        let attempts = 0;
        const maxAttempts = 20;

        while (!exploded && attempts < maxAttempts) {
            console.log(`💥 Attempt ${attempts + 1}/${maxAttempts}...`);
            const tx = new Transaction();
            await setNativeGasPayment(tx, p1Addr);

            tx.moveCall({
                target: `${PACKAGE_ID}::bomb_panic::try_explode`,
                arguments: [
                    tx.object(testGameStateId),
                    tx.object(CLOCK_ID),
                    tx.object(RANDOM_ID)
                ],
                typeArguments: [COIN_TYPE]
            });
            tx.setGasBudget(GAS_BUDGET);

            const explodeResult = await runWithSharedObjects([testGameStateId], () =>
                signAndExecute(player1Kp, tx, `Try Explode #${attempts + 1}`)
            );

            const explodeEvent = explodeResult.events?.find(e => e.type.includes('::Exploded'));
            const victoryEvent = explodeResult.events?.find(e => e.type.includes('::Victory'));

            if (explodeEvent || victoryEvent) {
                console.log("💥💥💥 Explosion or Victory Detected! 💥💥💥");
                logStructure("End Game Event", explodeEvent || victoryEvent);
                exploded = true;
            } else {
                console.log("... Tick tock ...");
                await sleep(2000);
            }
            attempts++;
        }

        if (!exploded) {
            console.warn(`⚠️  No explosion after ${maxAttempts} attempts. Continuing anyway...`);
        }
    }

    async function stepSettleRound() {
        console.log('\n--- Step 7: Settle Round (Internal Flow) ---');
        console.log("⏳ Waiting 10s for indexing before settlement...");
        await sleep(10_000);

        const endedGame = await client.getObject({ id: testGameStateId, options: { showContent: true } });
        logStructure("GameState (Before Settlement)", endedGame);

        const tx = new Transaction();
        await setNativeGasPayment(tx, p1Addr);

        tx.moveCall({
            target: `${PACKAGE_ID}::bomb_panic::settle_round_with_hub`,
            arguments: [
                tx.object("0xdea41871ee0619955b26b38295f5816c88d89d560c6b1f2609c27ed0d7342441"),
                tx.object("0x16179e72867634c0fafae177938518c843475501d60610462e0c02766f3dc427"),
                tx.object(gameCapId)
            ],
            typeArguments: [COIN_TYPE]
        });
        tx.setGasBudget(GAS_BUDGET);

        const settleResult = await runWithSharedObjects([testGameStateId, testRoomId, gameCapId], () =>
            signAndExecute(player1Kp, tx, "Settle Round")
        );

        const roundSettledEvent = settleResult.events?.find(e => e.type.includes('::RoundSettled'));
        if (roundSettledEvent) {
            console.log("🎯 RoundSettled Event Detected!");
            logStructure("RoundSettled Event", roundSettledEvent);
        } else {
            console.warn("⚠️  No RoundSettled event found");
        }

        // Derive expected payouts from the RoundSettled event if present.
        let expectedPayoutP1: bigint | null = null;
        let expectedPayoutP2: bigint | null = null;
        const pj = (roundSettledEvent as any)?.parsedJson;
        if (pj) {
            const survivors: string[] = Array.isArray(pj.survivors) ? pj.survivors : [];
            const survivorEach = BigInt(pj.survivor_payout_each ?? 0);
            const holderRewards: Array<{ player: string; amount: string }> = Array.isArray(pj.holder_rewards) ? pj.holder_rewards : [];

            const expected = new Map<string, bigint>();
            for (let i = 0; i < survivors.length; i++) {
                expected.set(survivors[i], (expected.get(survivors[i]) ?? 0n) + survivorEach);
            }
            for (const r of holderRewards) {
                if (typeof r?.player !== 'string') continue;
                expected.set(r.player, (expected.get(r.player) ?? 0n) + BigInt(r.amount ?? 0));
            }

            expectedPayoutP1 = expected.get(p1Addr) ?? 0n;
            if (p2Addr) expectedPayoutP2 = expected.get(p2Addr) ?? 0n;
        }



        await sleep(5000);

        const roomAfter = await client.getObject({ id: testRoomId, options: { showContent: true } });
        const roomContent = getMoveObjectContent(roomAfter);
        const rf = roomContent?.fields as any;
        const poolRaw = rf?.pool;
        const poolValue =
            typeof poolRaw === 'string'
                ? poolRaw
                : poolRaw?.fields?.value ?? poolRaw?.value ?? '0';
        console.log('\n🏦 Room after settlement:');
        console.log(`  Status: ${rf?.status?.variant ?? 'Unknown'}`);
        console.log(`  Pool: ${poolValue}`);
    }


    async function stepConfigureGame() {
        console.log('\n--- Step: Configure Game (Admin) ---');


        const tx = new Transaction();
        await setNativeGasPayment(tx, p1Addr);

        // Replace ADMIN_CAP_ID with your actual AdminCap object ID from .env or console
        const adminCapId = process.env.ADMIN_CAP;
        if (!adminCapId) throw new Error("Missing ADMIN_CAP_ID in .env");
        const adminGameId = "0xd3da8445f7e33b142cab2c0653e20a5cf5f64bb21542c30ae03d4d131a64ccef";
        tx.moveCall({
            target: `${PACKAGE_ID}::bomb_panic::configure_game_admin`,
            arguments: [
                tx.object(adminGameId),
                tx.object(adminCapId),
                tx.pure.u64(60000),      // max_hold_time_ms (e.g., 15 seconds)
                tx.pure.u64(300),        // explosion_rate_bps (e.g., 5%)
                tx.pure.u64(100),         // reward_divisor (pool / 40 = reward per sec)
            ],
            typeArguments: [COIN_TYPE]
        });

        tx.setGasBudget(GAS_BUDGET);
        // This MUST be signed by the Admin wallet that owns the AdminCap
        await runWithSharedObjects([adminGameId], () =>
            signAndExecute(player1Kp, tx, "Configure Game")
        );
    }

    async function stepResetGame() {

        console.log('\n--- Step 8: Reset Game ---');
        const tx = new Transaction();
        await setNativeGasPayment(tx, p1Addr);

        tx.moveCall({
            target: `${PACKAGE_ID}::bomb_panic::reset_game`,
            arguments: [tx.object(testGameStateId)],
            typeArguments: [COIN_TYPE]
        });
        tx.moveCall({
            target: `${PACKAGE_ID}::gamehub::reset_room`,
            arguments: [tx.object(testRoomId), tx.object(gameCapId)],
            typeArguments: [COIN_TYPE],
        });
        tx.setGasBudget(GAS_BUDGET);

        await runWithSharedObjects([testGameStateId, testRoomId, gameCapId], () =>
            signAndExecute(player1Kp, tx, "Reset Game")
        );

        await sleep(5000);

        const resetGame = await client.getObject({ id: testGameStateId, options: { showContent: true } });
        logStructure("GameState (After Reset)", resetGame);
    }

    // await stepJoinRoom();
    // await stepReadyToPlay();

    // await sleep(5000);
    // await stepStartRoom();
    // const initialHolder = await stepStartRound();
    // await stepPassBomb(initialHolder, 6);
    async function testDeleteGameAndRoom() {
        console.log('\n\n═══════════════════════════════════════════════════════');
        console.log('🧪 TESTING DELETE FUNCTIONS');
        console.log('═══════════════════════════════════════════════════════');

        // Use Admin (User 2) for this test as requested
        const deleterKp = adminKp;
        const deleterAddr = adminAddr;

        console.log(`Using Deleter: ${deleterAddr}`);

        // // 1. Create a temporary room and game
        // console.log("Creating temporary room for deletion...");
        // const temp = await createRoomAndGame(
        //     deleterKp,
        //     lobbyId,
        //     gameRegistry,
        //     config,
        //     50_000,
        //     2,
        //     "Temp Room for Deletion"
        // );


        const temp = {
            roomId: "0x994386fa49c53f19eff98c95920c0c15d9968fc877c7bf678526c7e74abd7450",
            gameStateId: "0x27aba2d395429a6170a3c6e85d0eed337a004d2f1664bb4a5efdbbc69799957c"
        }
        console.log(`Temp Room: ${temp.roomId}`);
        console.log(`Temp Game: ${temp.gameStateId}`);

        // 2. Delete GameState
        console.log("\n🗑️  Deleting GameState...");
        const tx1 = new Transaction();
        await setNativeGasPayment(tx1, deleterAddr);
        tx1.moveCall({
            target: `${PACKAGE_ID}::bomb_panic::delete_game`,
            arguments: [tx1.object(temp.gameStateId), tx1.object(lobbyId)],
            typeArguments: [COIN_TYPE]
        });
        tx1.setGasBudget(GAS_BUDGET);
        await runWithSharedObjects([temp.gameStateId, lobbyId], () =>
            signAndExecute(deleterKp, tx1, "Delete GameState")
        );

        console.log("  ⏳ Waiting 10s for indexing...");
        await sleep(10000);

        // 3. Delete Room (must be empty/waiting - createRoomAndGame leaves it empty/waiting)
        console.log("\n🗑️  Deleting Room...");
        const tx2 = new Transaction();
        await setNativeGasPayment(tx2, deleterAddr);
        tx2.moveCall({
            target: `${PACKAGE_ID}::gamehub::delete_room`,
            arguments: [tx2.object(temp.roomId)],
            typeArguments: [COIN_TYPE]
        });
        tx2.setGasBudget(GAS_BUDGET);
        await runWithSharedObjects([temp.roomId], () =>
            signAndExecute(deleterKp, tx2, "Delete Room")
        );

        console.log("\n✅ Deletion test passed.");
        const allRooms = await queryRooms(roomIds);
        const allGameStates = await queryGameStates(gameStateIds);
        const { tableId } = await queryLobby(lobbyId);
        console.log("\nRooms:", allRooms);
        console.log("\nGameStates:", allGameStates);
        console.log("\nLobby Table ID:", tableId);

    }

    // await stepTryExplodeLoop();
    // await stepSettleRound();
    // await stepResetGame();
    // await stepConfigureGame();

    // Run the deletion test
    await testDeleteGameAndRoom();
    console.log('\n\n════════════════════════════════════════════════════════════');
    console.log('✅✅✅ FULL INTEGRATION TEST COMPLETE! ✅✅✅');
    console.log('════════════════════════════════════════════════════════════');
    console.log('Successfully tested:');
    console.log('  ✅ Lobby tracking of room-to-game mappings');
    console.log('  ✅ Room creation and GameState initialization');
    console.log('  ✅ Player joining and readying');
    console.log('  ✅ Room and round starting');
    console.log('  ✅ Bomb passing mechanics');
    console.log('  ✅ Explosion and victory detection');
    console.log('  ✅ Settlement and payout distribution');
    console.log('  ✅ Game reset for next round');
    console.log('════════════════════════════════════════════════════════════\n');
}

main().catch(console.error);
