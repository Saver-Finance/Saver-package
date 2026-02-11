import { SuiClient } from '@onelabs/sui/client';
import { Ed25519Keypair } from '@onelabs/sui/keypairs/ed25519';
import { Transaction } from '@onelabs/sui/transactions';
import { decodeSuiPrivateKey } from '@onelabs/sui/cryptography';

import dotenv from 'dotenv';
dotenv.config();

// ============================================================================
// Configuration
// ============================================================================

const PACKAGE_ID = process.env.PACKAGE_ID;
const RPC_URL = process.env.RPC_URL || 'https://rpc-testnet.onelabs.cc:443';

// Shared objects from deployment
const GAME_REGISTRY = process.env.GAME_REGISTRY;
const ADMIN_CAP = process.env.ADMIN_CAP;
// Coin type
const COIN_TYPE = '0x2::oct::OCT';
const HACKATHON_COIN_TYPE = "0x8b76fc2a2317d45118770cefed7e57171a08c477ed16283616b15f099391f120::hackathon::HACKATHON";
// ============================================================================

const ADMIN_PRIVATE_KEY = process.env.ADMIN_PRIVATE_KEY;
const ADMIN_MNEMONIC = process.env.USER_2;
// ============================================================================
// Script
// ============================================================================

const client = new SuiClient({ url: RPC_URL });

async function registerGame() {
    console.log('🔐 Registering Bomb Panic game with GameHub...\n');

    // const adminKeypair = Ed25519Keypair.fromSecretKey(decodeSuiPrivateKey(ADMIN_PRIVATE_KEY!).secretKey);
    // const adminAddress = adminKeypair.getPublicKey().toSuiAddress();

    const adminKeypair = Ed25519Keypair.deriveKeypair(ADMIN_MNEMONIC!);
    const adminAddress = adminKeypair.getPublicKey().toSuiAddress();
    console.log(`Admin address: ${adminAddress}`);
    console.log(`Package ID: ${PACKAGE_ID}`);
    console.log(`Game Registry: ${GAME_REGISTRY}`);
    console.log(`Admin Cap: ${ADMIN_CAP}\n`);

    const tx = new Transaction();

    const [gameCap] = tx.moveCall({
        target: `${PACKAGE_ID}::gamehub::register_game`,
        arguments: [
            tx.object(GAME_REGISTRY!),
            tx.object(ADMIN_CAP!),
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
