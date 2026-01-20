import { SuiClient } from '@onelabs/sui/client';
import { Ed25519Keypair } from '@onelabs/sui/keypairs/ed25519';
import { Transaction } from '@onelabs/sui/transactions';
import { decodeSuiPrivateKey } from '@onelabs/sui/cryptography';

// ============================================================================
// Configuration
// ============================================================================

const PACKAGE_ID = "0xc971f316476fb1bf5d1c502e1bd7e45fa69dd00744953282db48d2385158d755";
const RPC_URL = 'https://rpc-testnet.onelabs.cc:443';

// Shared objects from deployment
const GAME_REGISTRY = "0x2035d9bc13b8f936f25b47ae79026b4363f520bf229386e8d6e107113a5f5b87";
const ADMIN_CAP = "0x69e07c7611d58d0dc03be8385aaf544ca75e8e37370d1c929e58ea4fa5a8635c";

// Coin type
const COIN_TYPE = '0x2::oct::OCT';

// ============================================================================

const ADMIN_PRIVATE_KEY = "REDACTED_PRIVATE_KEY";

// ============================================================================
// Script
// ============================================================================

const client = new SuiClient({ url: RPC_URL });

async function registerGame() {
    console.log('🔐 Registering Bomb Panic game with GameHub...\n');

    const adminKeypair = Ed25519Keypair.fromSecretKey(decodeSuiPrivateKey(ADMIN_PRIVATE_KEY).secretKey);
    const adminAddress = adminKeypair.getPublicKey().toSuiAddress();

    console.log(`Admin address: ${adminAddress}`);
    console.log(`Package ID: ${PACKAGE_ID}`);
    console.log(`Game Registry: ${GAME_REGISTRY}`);
    console.log(`Admin Cap: ${ADMIN_CAP}\n`);

    const tx = new Transaction();

    const [gameCap] = tx.moveCall({
        target: `${PACKAGE_ID}::gamehub::register_game`,
        arguments: [
            tx.object(GAME_REGISTRY),
            tx.object(ADMIN_CAP),
            tx.pure.vector('u8', Array.from(new TextEncoder().encode('Bomb Panic'))),
        ],
        typeArguments: [`${PACKAGE_ID}::bomb_panic::GameState<${COIN_TYPE}>`],
    });

    // set admin as game cap 
    tx.transferObjects([gameCap], adminAddress);

    tx.setGasBudget(100_000_000n);

    console.log('📤 Submitting transaction...');

    const result = await client.signAndExecuteTransaction({
        signer: adminKeypair,
        transaction: tx,
        options: {
            showEffects: true,
            showEvents: true,
            showObjectChanges: true,
        },
    });

    if (result.effects?.status.status === 'success') {
        console.log(`✅ Success! Digest: ${result.digest}\n`);

        // Find the GameCap object
        const gameCapObject = result.objectChanges?.find(
            (change) => change.type === 'created' && change.objectType?.includes('::gamehub::GameCap')
        );

        if (gameCapObject && gameCapObject.type === 'created') {
            console.log('🎮 GameCap Created!');
            console.log(`   Object ID: ${gameCapObject.objectId}`);
            console.log(`   Owner: ${gameCapObject.owner}\n`);
            console.log('📋 Copy this GameCap ID and use it in your integration test!');
            console.log(`   GAME_CAP_ID = "${gameCapObject.objectId}"`);
        } else {
            console.error('❌ Failed to find GameCap object');
        }
    } else {
        console.error(`❌ Failed:`, result.effects?.status);
    }
}

registerGame()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error('❌ Error:', error);
        process.exit(1);
    });
