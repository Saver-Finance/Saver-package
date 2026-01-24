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
const GAME_REGISTRY = "0x2ce9008e175a6a667b981af5867507901dbbe4cd356d187c4deab6fe14b983bb";
const ADMIN_CAP = "0x302f85f9f2985c80570cccba9e6f0a7c8617c1a4446f019bc200c021087f6b4a";
const UPGRADE_CAP = "0xab196807c7c4b9f8a1a52b46af419c8b0287f7da42bfea76950c11b4a15ca71a";
const CONFIG = "0xff6db047f94a77e90762024533a38f4b6ac24e2a208b5e59c4dd413502a066f1";
// Coin type
const COIN_TYPE = '0x2::oct::OCT';

// ============================================================================

const ADMIN_PRIVATE_KEY = process.env.ADMIN_PRIVATE_KEY;

// ============================================================================
// Script
// ============================================================================

const client = new SuiClient({ url: RPC_URL });

async function registerGame() {
    console.log('🔐 Registering Bomb Panic game with GameHub...\n');

    const adminKeypair = Ed25519Keypair.fromSecretKey(decodeSuiPrivateKey(ADMIN_PRIVATE_KEY!).secretKey);
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
