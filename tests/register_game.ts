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
const ADMIN_CAP_ID = `0x4ccf015d5197b6bf3d6f3f41e3215c5d36e670236709f604f27d673656cea110`;
const REGISTRY_ID = `0xd8faa05df92c73e5ec2d8e1d8e18d71eaec89cd116fdd2d3fc9f4b23f0e848e2`;

// Coin type
const COIN_TYPE = '0x2::oct::OCT';

// ============================================================================

const ADMIN_PRIVATE_KEY = process.env.ADMIN;

// ============================================================================
// Script
// ============================================================================

const client = new SuiClient({ url: RPC_URL });

async function registerGame() {
    console.log('🔐 Registering Bomb Panic game with GameHub...\n');

    const adminKeypair = Ed25519Keypair.deriveKeypair(process.env.ADMIN!);
    const adminAddress = adminKeypair.toSuiAddress();

    console.log(`Admin address: ${adminAddress}`);
    console.log(`Package ID: ${PACKAGE_ID}`);
    console.log(`Game Registry: ${REGISTRY_ID}`);
    console.log(`Admin Cap: ${ADMIN_CAP_ID}\n`);

    const tx = new Transaction();

    const [gameCap] = tx.moveCall({
        target: `${PACKAGE_ID}::gamehub::register_game`,
        arguments: [
            tx.object(REGISTRY_ID),
            tx.object(ADMIN_CAP_ID),
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
