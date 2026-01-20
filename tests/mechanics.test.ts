
import { SuiClient } from '@onelabs/sui/client';
import { Ed25519Keypair } from '@onelabs/sui/keypairs/ed25519';
import { Transaction } from '@onelabs/sui/transactions';

// ============================================================================
// Configuration
// ============================================================================

const PACKAGE_ID = process.env.PACKAGE_ID!;
const RPC_URL = process.env.RPC_URL!;
const COIN_TYPE = '0x2::oct::OCT';

// ============================================================================
// Setup
// ============================================================================

const client = new SuiClient({ url: RPC_URL });

// Same keys as integration test
const player1 = Ed25519Keypair.deriveKeypair(
    "REDACTED_MNEMONIC_3"
);
const player2 = Ed25519Keypair.deriveKeypair(
    "REDACTED_MNEMONIC_2"
);

const player1Address = player1.getPublicKey().toSuiAddress();
const player2Address = player2.getPublicKey().toSuiAddress();

// ============================================================================
// Helpers
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

    const coins = await client.getCoins({ owner: address, coinType: COIN_TYPE });
    if (coins.data.length > 0) {
        const candidate = coins.data.find(c => BigInt(c.balance) > 20_000_000n) || coins.data[0];
        if (candidate) {
            const coinData = await client.getObject({ id: candidate.coinObjectId });
            if (coinData.data?.version && coinData.data?.digest) {
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
            options: { showEffects: true, showEvents: true, showObjectChanges: true },
        });

        if (result.effects?.status.status === 'success') {
            console.log(`✅ Success! Digest: ${result.digest}`);
            return result;
        } else {
            throw new Error(`Transaction failed: ${result.effects?.status.error}`);
        }
    } catch (error) {
        console.error(`❌ Error executing transaction:`, error);
        throw error;
    }
}

async function createRoom(): Promise<string> {
    const createTx = new Transaction();
    const dummyHubId = '0x0000000000000000000000000000000000000000000000000000000000000000';

    createTx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::initialize_game`,
        arguments: [
            createTx.pure.address(dummyHubId),
            createTx.pure.vector('u8', Array.from(new TextEncoder().encode('Mechanics Test'))),
            createTx.pure.u64(1000),
            createTx.pure.u64(4),
        ],
        typeArguments: [COIN_TYPE],
    });

    const result = await executeTransaction(player1, createTx, 'Creating Room');
    const created = result.objectChanges?.find((c: any) => c.type === 'created' && c.objectType.includes('::GameState'));
    if (!created) throw new Error('GameState not created');
    return (created as any).objectId;
}

// ============================================================================
// Test: Max Hold Time (Camping)
// ============================================================================

async function testMaxHoldTime() {
    console.log('\n🧪 Testing Max Hold Time (Anti-Camping)...');
    console.log('='.repeat(60));

    const gameStateId = await createRoom();
    await sleep(2000); // Wait for indexer

    // Both Join
    const join1 = new Transaction();
    join1.moveCall({ target: `${PACKAGE_ID}::bomb_panic::join`, arguments: [join1.object(gameStateId)], typeArguments: [COIN_TYPE] });
    await executeTransaction(player1, join1, 'P1 Join');

    const join2 = new Transaction();
    join2.moveCall({ target: `${PACKAGE_ID}::bomb_panic::join`, arguments: [join2.object(gameStateId)], typeArguments: [COIN_TYPE] });
    await executeTransaction(player2, join2, 'P2 Join');
    await sleep(1000);

    // Start Round
    const startTx = new Transaction();
    startTx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::start_round`,
        arguments: [
            startTx.object('0x8'),
            startTx.object(gameStateId),
            startTx.object('0x6'),
            startTx.pure.u64(1000000n),
        ],
        typeArguments: [COIN_TYPE],
    });
    const startResult = await executeTransaction(player1, startTx, 'Start Round');

    const roundEvent = startResult.events?.find(e => e.type.includes('::RoundStarted'));
    const holder = (roundEvent?.parsedJson as any).bomb_holder;
    console.log(`💣 Holder is: ${holder === player1Address ? 'Player 1' : 'Player 2'}`);

    const holderKeypair = holder === player1Address ? player1 : player2;

    // WAIT for > 10s (Max Hold Time)
    console.log('⏳ Waiting 12 seconds to trigger Anti-Camping...');
    await sleep(12000);

    // Holder tries to pass
    console.log('🔄 Holder trying to pass (Should explode due to holding too long)...');
    const passTx = new Transaction();
    passTx.moveCall({
        target: `${PACKAGE_ID}::bomb_panic::pass_bomb`,
        arguments: [
            passTx.object('0x8'),
            passTx.object(gameStateId),
            passTx.object('0x6'),
        ],
        typeArguments: [COIN_TYPE],
    });

    // We expect this transaction to SUCCEED (gas paid), but result in an EXPLOSION event
    const passResult = await executeTransaction(holderKeypair, passTx, 'Attempting Pass');

    const explodedEvent = passResult.events?.find(e => e.type.includes('::Exploded'));

    if (explodedEvent) {
        console.log('✅ PASS DETECTED AS EXPLOSION! Anti-Camping verified.');
        console.log(`💀 Dead Player: ${(explodedEvent.parsedJson as any).dead_player}`);
    } else {
        throw new Error('❌ Test Failed: Player was able to pass after 12s! Camping check failed.');
    }
}

testMaxHoldTime().then(() => process.exit(0)).catch(e => {
    console.error(e);
    process.exit(1);
});
