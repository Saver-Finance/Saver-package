import { SuiClient } from '@onelabs/sui/client';
import { Ed25519Keypair } from '@onelabs/sui/keypairs/ed25519';
import { Transaction } from '@onelabs/sui/transactions';
import { decodeSuiPrivateKey } from '@onelabs/sui/cryptography';
import dotenv from 'dotenv';

dotenv.config();

// --- Configuration ---
const RPC_URL = process.env.RPC_URL || 'https://rpc-testnet.onelabs.cc:443';
const PACKAGE_ID = "0xca3904165c2b81d25a55a4f6203e2c895e63aabe7db6f19b0288504618ea0205";
const GAME_REGISTRY = "0xd53039f92adc911515267d8682eec60bf7a98dd7ec96a08f80501c5f61724e4b";
const GAME_CAP_ID = "0xccaaffcdd574b9e8298e60ee89504fa907dfe3494f988b26c0b63e3e48149c05";
const ADMIN_CAP = "0x9d47cdd1a0d895c7bb5f131131d291ad1adcd6147646b0be635529bdbec881c7";
const COIN_TYPE = '0x2::oct::OCT';
const CLOCK_ID = '0x6';
const RANDOM_ID = '0x8';
// OneChain testnet native token is OCT
const NATIVE_COIN_TYPE = '0x2::oct::OCT';

// --- Constants ---
const ENTRY_FEE = 100_000_000; // 100 OCT
const MAX_PLAYERS = 8;

const client = new SuiClient({ url: RPC_URL });

async function getCoinId(address: string, amount: number) {
    // For native token, we can just use getCoins without type or with explicit type
    // Since we need to pass a specific coin generic to Move, we ensure we find a coin of that type.
    const coins = await client.getCoins({ owner: address, coinType: COIN_TYPE });
    // Filter for coins with enough balance
    const coin = coins.data.find(c => parseInt(c.balance) >= amount);
    if (!coin) {
        // Log all coins to debug
        console.log(`Available coins for ${address}:`, coins.data.map(c => `${c.coinObjectId} (${c.balance})`));
        throw new Error(`No coin with enough balance (${amount}) for ${address}`);
    }
    return coin.coinObjectId;
}

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

async function logStructure(title: string, data: any) {
    console.log(`\n🔍 --- STRUCTURE VERIFICATION: ${title} ---`);
    console.log(JSON.stringify(data, null, 2));
    console.log('-------------------------------------------');
}

async function main() {
    console.log('🚀 Starting Comprehensive Integration Test (FE + BE Flow)\n');

    if (!process.env.ADMIN_PRIVATE_KEY) throw new Error("Missing ADMIN_PRIVATE_KEY");
    if (!process.env.USER_1 || !process.env.USER_2) throw new Error("Missing USER_1 or USER_2 mnemonics");

    const adminKp = Ed25519Keypair.fromSecretKey(decodeSuiPrivateKey(process.env.ADMIN_PRIVATE_KEY).secretKey);
    const player1Kp = Ed25519Keypair.deriveKeypair(process.env.USER_1);
    const player2Kp = Ed25519Keypair.deriveKeypair(process.env.USER_2);

    const adminAddr = adminKp.toSuiAddress();
    const p1Addr = player1Kp.toSuiAddress();
    const p2Addr = player2Kp.toSuiAddress();

    console.log(`Admin: ${adminAddr}`);
    console.log(`Player 1: ${p1Addr}`);
    console.log(`Player 2: ${p2Addr}\n`);

    // Check Balances
    console.log('--- Step 0: Check Balances ---');
    async function checkBalance(addr: string, name: string) {
        const bal = await client.getBalance({ owner: addr, coinType: NATIVE_COIN_TYPE });
        console.log(`${name} Balance: ${bal.totalBalance} OCT`);
        if (BigInt(bal.totalBalance) < BigInt(ENTRY_FEE + 500_000_000)) { // Entry + 0.5 gas
            console.warn(`WARNING: ${name} might be low on funds.`);
        }
    }
    await checkBalance(adminAddr, "Admin");
    await checkBalance(p1Addr, "Player 1");
    await checkBalance(p2Addr, "Player 2");


    // 1. Initialize GameState
    console.log('\n--- Step 1: Initialize GameState ---');
    let tx = new Transaction();

    // Explicitly select gas for Admin to avoid " Balance of gas object ... is lower than needed"
    // Fetch fresh gas
    const adminCoins = await client.getCoins({ owner: adminAddr, coinType: NATIVE_COIN_TYPE });
    // Find biggest coin
    const adminGas = adminCoins.data.sort((a, b) => Number(b.balance) - Number(a.balance))[0];
    if (adminGas && BigInt(adminGas.balance) > 200_000_000n) {
        console.log(`Admin utilizing gas object: ${adminGas.coinObjectId}`);
        tx.setGasPayment([{ objectId: adminGas.coinObjectId, version: adminGas.version, digest: adminGas.digest }]);
    }

    tx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::initialize_game`,
        arguments: [
            tx.pure.address(GAME_REGISTRY),
            tx.pure.string("Integration Test Game"),
            tx.pure.u64(ENTRY_FEE),
            tx.pure.u64(MAX_PLAYERS)
        ],
        typeArguments: [COIN_TYPE]
    });
    tx.setGasBudget(100_000_000);

    const initResult = await signAndExecute(adminKp, tx, "Initialize Game");
    const gameStateId = initResult.objectChanges?.find(c => c.type === 'created' && c.objectType.includes('::GameState'))?.objectId;
    if (!gameStateId) throw new Error("Failed to find GameState object ID");

    console.log(`🎮 GameState Created: ${gameStateId}`);

    console.log("Waiting 10s for indexing...");
    await new Promise(r => setTimeout(r, 10000));

    const gameStateObj = await client.getObject({ id: gameStateId, options: { showContent: true } });
    logStructure("Initial GameState", gameStateObj);


    // 2. Create Room (FE Action)
    console.log('\n--- Step 2: Create Room (FE) ---');
    tx = new Transaction();

    // Fetch gas for Player 1
    const p1Coins = await client.getCoins({ owner: p1Addr, coinType: NATIVE_COIN_TYPE });
    const p1Gas = p1Coins.data.sort((a, b) => Number(b.balance) - Number(a.balance))[0];
    if (p1Gas) {
        console.log(`P1 using gas coin: ${p1Gas.coinObjectId}`);
        tx.setGasPayment([{ objectId: p1Gas.coinObjectId, version: p1Gas.version, digest: p1Gas.digest }]);
    }

    // Create Fee (Use Split from Gas)
    // IMPORTANT: If we set Gas Payment explicitly, we can split from tx.gas
    const [creationFeeCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(100)]);

    const CONFIG_ID = "0xdec029cb292f840d226f4d0f3b8bf20eea7a1f743463e73b50f343c85550375a";

    tx.moveCall({
        target: `${PACKAGE_ID}::gamehub::create_room`,
        arguments: [
            tx.object(GAME_REGISTRY),
            tx.object(CONFIG_ID),
            tx.pure.u64(ENTRY_FEE), // Entry fee for players
            tx.pure.u8(MAX_PLAYERS),
            creationFeeCoin
        ],
        typeArguments: [COIN_TYPE, `${PACKAGE_ID}::bomb_panic::GameState<${COIN_TYPE}>`]
    });
    tx.setGasBudget(100_000_000);

    const createRoomResult = await signAndExecute(player1Kp, tx, "Create Room");
    const roomId = createRoomResult.objectChanges?.find(c => c.type === 'created' && c.objectType.includes('::Room'))?.objectId;
    if (!roomId) throw new Error("Failed to find Room object ID");
    console.log(`🏠 Room Created: ${roomId}`);

    console.log("Waiting 10s for indexing...");
    await new Promise(r => setTimeout(r, 10000));

    const roomObj = await client.getObject({ id: roomId, options: { showContent: true } });
    logStructure("Initial Room", roomObj);


    // 3. Join Game (Player 1 & 2)
    console.log('\n--- Step 3: Join Game (P1 & P2) ---');

    async function joinGame(playerKp: Ed25519Keypair, name: string) {
        const tx = new Transaction();
        const addr = playerKp.toSuiAddress();

        // Gas Selection
        const coins = await client.getCoins({ owner: addr, coinType: NATIVE_COIN_TYPE });
        const gas = coins.data.sort((a, b) => Number(b.balance) - Number(a.balance))[0];
        if (gas) tx.setGasPayment([{ objectId: gas.coinObjectId, version: gas.version, digest: gas.digest }]);

        // 1. gamehub::join_room
        tx.moveCall({
            target: `${PACKAGE_ID}::gamehub::join_room`,
            arguments: [tx.object(roomId)],
            typeArguments: [COIN_TYPE]
        });
        // 2. bomb_panic::join
        tx.moveCall({
            target: `${PACKAGE_ID}::bomb_panic::join`,
            arguments: [tx.object(gameStateId)],
            typeArguments: [COIN_TYPE]
        });
        tx.setGasBudget(100_000_000);
        return signAndExecute(playerKp, tx, `Join ${name}`);
    }

    const join1 = await joinGame(player1Kp, "Player 1");
    logStructure("Join Transaction Result (P1)", join1);

    const join2 = await joinGame(player2Kp, "Player 2");

    console.log("Waiting 10s for indexing...");
    await new Promise(r => setTimeout(r, 10000));


    // 4. Ready (Player 1 & 2)
    console.log('\n--- Step 4: Ready to Play ---');

    async function readyGame(playerKp: Ed25519Keypair, name: string) {
        const tx = new Transaction();
        const addr = playerKp.toSuiAddress();

        const coins = await client.getCoins({ owner: addr, coinType: NATIVE_COIN_TYPE });
        const gas = coins.data.sort((a, b) => Number(b.balance) - Number(a.balance))[0];
        if (gas) {
            console.log(`${name} using gas for ready: ${gas.coinObjectId}`);
            tx.setGasPayment([{ objectId: gas.coinObjectId, version: gas.version, digest: gas.digest }]);
        }

        // Fee Payment: Check if gas coin has enough for Fee + Gas.
        // If we split from Gas, we don't need a separate getCoinId.
        // Assuming user has one big coin (faucet coin).
        // Let's split entry fee from gas.
        const [feeCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(ENTRY_FEE)]);

        tx.moveCall({
            target: `${PACKAGE_ID}::gamehub::ready_to_play`,
            arguments: [tx.object(roomId), feeCoin],
            typeArguments: [COIN_TYPE]
        });
        tx.setGasBudget(100_000_000);
        return signAndExecute(playerKp, tx, `Ready ${name}`);
    }

    await readyGame(player1Kp, "Player 1");
    await readyGame(player2Kp, "Player 2");

    console.log("Waiting 3s for indexing...");
    await new Promise(r => setTimeout(r, 3000));


    // 5. Start Round (Admin/Backend)
    console.log('\n--- Step 5: Start Round (Backend) ---');
    tx = new Transaction();

    // Explicit Admin Gas
    const adminCoins2 = await client.getCoins({ owner: adminAddr, coinType: NATIVE_COIN_TYPE });
    const adminGas2 = adminCoins2.data.sort((a, b) => Number(b.balance) - Number(a.balance))[0];
    if (adminGas2) tx.setGasPayment([{ objectId: adminGas2.coinObjectId, version: adminGas2.version, digest: adminGas2.digest }]);

    const roomState = await client.getObject({ id: roomId, options: { showContent: true } });
    const poolVal = (roomState.data?.content as any).fields.pool;
    console.log(`Current Pool Value: ${poolVal}`);

    // 5a. Start Room (GameHub)
    console.log('\n--- Step 5a: Start Room (GameHub) ---');

    tx.moveCall({
        target: `${PACKAGE_ID}::gamehub::start_room`,
        arguments: [
            tx.object(roomId),
            tx.object(ADMIN_CAP),
            tx.object(CONFIG_ID)
        ],
        typeArguments: [COIN_TYPE]
    });
    tx.setGasBudget(100_000_000);

    await signAndExecute(adminKp, tx, "Start Room");

    console.log("Waiting 3s for indexing...");
    await new Promise(r => setTimeout(r, 3000));


    // 5b. Start Round (Bomb Panic)
    console.log('\n--- Step 5b: Start Round (Bomb Panic) ---');
    tx = new Transaction();

    // Explicit Admin Gas (Refresh)
    const adminCoins3 = await client.getCoins({ owner: adminAddr, coinType: NATIVE_COIN_TYPE });
    const adminGas3 = adminCoins3.data.sort((a, b) => Number(b.balance) - Number(a.balance))[0];
    if (adminGas3) tx.setGasPayment([{ objectId: adminGas3.coinObjectId, version: adminGas3.version, digest: adminGas3.digest }]);

    tx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::start_round`,
        arguments: [
            tx.object(RANDOM_ID),
            tx.object(gameStateId),
            tx.object(roomId),
            tx.object(CLOCK_ID),
            tx.pure.u64(poolVal)
        ],
        typeArguments: [COIN_TYPE]
    });
    tx.setGasBudget(100_000_000);

    const startResult = await signAndExecute(adminKp, tx, "Start Round");
    logStructure("Start Round Event", startResult.events);

    console.log("Waiting 5s for indexing...");
    await new Promise(r => setTimeout(r, 5000));

    const playingGame = await client.getObject({ id: gameStateId, options: { showContent: true } });
    logStructure("GameState (Playing)", playingGame);

    const holder = (playingGame.data?.content as any).fields.bomb_holder;
    console.log(`💣 Bomb Holder: ${holder}`);


    // 6. Pass Bomb
    console.log('\n--- Step 6: Pass Bomb ---');
    let holderKp = p1Addr === holder ? player1Kp : player2Kp;
    let nextPlayer = p1Addr === holder ? p2Addr : p1Addr;

    tx = new Transaction();
    const hAddr = holderKp.toSuiAddress();
    const hCoins = await client.getCoins({ owner: hAddr, coinType: NATIVE_COIN_TYPE });
    const hGas = hCoins.data.sort((a, b) => Number(b.balance) - Number(a.balance))[0];
    if (hGas) tx.setGasPayment([{ objectId: hGas.coinObjectId, version: hGas.version, digest: hGas.digest }]);

    tx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::pass_bomb`,
        arguments: [
            tx.object(RANDOM_ID),
            tx.object(gameStateId),
            tx.object(CLOCK_ID)
        ],
        typeArguments: [COIN_TYPE]
    });
    tx.setGasBudget(100_000_000);

    console.log(`Passing bomb from ${hAddr} to someone...`);
    const passResult = await signAndExecute(holderKp, tx, "Pass Bomb");
    logStructure("Pass Bomb Events", passResult.events);


    // 7. Try Explode Loop
    console.log('\n--- Step 7: Game Loop (Try Explode) ---');
    let exploded = false;
    let attempts = 0;
    while (!exploded && attempts < 10) {
        console.log(`Attempt ${attempts + 1}...`);
        tx = new Transaction();
        // Admin Gas
        const aCoins = await client.getCoins({ owner: adminAddr, coinType: NATIVE_COIN_TYPE });
        const aGas = aCoins.data.sort((a, b) => Number(b.balance) - Number(a.balance))[0];
        if (aGas) tx.setGasPayment([{ objectId: aGas.coinObjectId, version: aGas.version, digest: aGas.digest }]);

        tx.moveCall({
            target: `${PACKAGE_ID}::bomb_panic::try_explode`,
            arguments: [
                tx.object(gameStateId),
                tx.object(CLOCK_ID),
                tx.object(RANDOM_ID)
            ],
            typeArguments: [COIN_TYPE]
        });
        tx.setGasBudget(100_000_000);

        const explodeResult = await signAndExecute(adminKp, tx, "Try Explode");

        const explodeEvent = explodeResult.events?.find(e => e.type.includes('::Exploded'));
        const victoryEvent = explodeResult.events?.find(e => e.type.includes('::Victory'));

        if (explodeEvent || victoryEvent) {
            console.log("💥 Explosion or Victory Detected!");
            logStructure("End Game Event", explodeEvent || victoryEvent);
            exploded = true;
        } else {
            console.log("... Tick tock ...");
            await new Promise(r => setTimeout(r, 1000));
        }
        attempts++;
    }


    // 8. Settle
    console.log('\n--- Step 8: Settle Game ---');
    console.log("Waiting 10s for indexing before Settle...");
    await new Promise(r => setTimeout(r, 10000));

    const endedGame = await client.getObject({ id: gameStateId, options: { showContent: true } });
    logStructure("GameState (Ended)", endedGame);

    tx = new Transaction();
    // Admin Gas
    const sCoins = await client.getCoins({ owner: adminAddr, coinType: NATIVE_COIN_TYPE });
    const sGas = sCoins.data.sort((a, b) => Number(b.balance) - Number(a.balance))[0];
    if (sGas) tx.setGasPayment([{ objectId: sGas.coinObjectId, version: sGas.version, digest: sGas.digest }]);

    // Consume Intent
    tx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::consume_settlement_intent`,
        arguments: [tx.object(gameStateId)],
        typeArguments: [COIN_TYPE]
    });

    // Settle
    const survivorPayouts = [p1Addr, p2Addr];
    const payoutAmounts = [50_000_000, 50_000_000];

    tx.moveCall({
        target: `${PACKAGE_ID}::gamehub::settle`,
        arguments: [
            tx.object(roomId),
            tx.pure.vector('address', survivorPayouts),
            tx.pure.vector('u64', payoutAmounts),
            tx.object(GAME_CAP_ID)
        ],
        typeArguments: [COIN_TYPE]
    });
    tx.setGasBudget(100_000_000);

    await signAndExecute(adminKp, tx, "Consume Intent & Settle");

    // Verify Room Settled
    await new Promise(r => setTimeout(r, 2000));
    const settledRoom = await client.getObject({ id: roomId, options: { showContent: true } });
    logStructure("Room (Settled)", settledRoom);


    // 9. Reset
    console.log('\n--- Step 9: Reset Game ---');
    tx = new Transaction();
    tx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::reset_game`,
        arguments: [tx.object(gameStateId)],
        typeArguments: [COIN_TYPE]
    });
    tx.setGasBudget(100_000_000);

    await signAndExecute(adminKp, tx, "Reset Game");

    console.log("Waiting 5s for indexing...");
    await new Promise(r => setTimeout(r, 5000));

    const resetGame = await client.getObject({ id: gameStateId, options: { showContent: true } });
    logStructure("GameState (Reset)", resetGame);

    console.log('\n✅ Integration Test Complete!');
}

main().catch(console.error);
