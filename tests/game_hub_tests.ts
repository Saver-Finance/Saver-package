import { SuiClient } from '@onelabs/sui/client';
import { Ed25519Keypair } from '@onelabs/sui/keypairs/ed25519';
import { Transaction } from '@onelabs/sui/transactions';
import { fromB64 } from '@onelabs/sui/utils';
import dotenv from 'dotenv';
dotenv.config();

const PACKAGE_ID = '0x003ca0545af98073fc7f7a1c7b658fbcf758995a1ba7f427b78548a66a5ba45b';
const ADMIN_CAP_ID = `0x751b5d91fef1673533bb8ed204ab880e234f3f783289be4a34fec59a6168c267`;
const REGISTRY_ID = `0x8012d57ea196ff5586940f11cebd50cc5e5aaaa89c829f7a327834a8d05223b8`;
const CONFIG_ID = `0x17e091685717bfeb89ee3d9290dd012f92ce5081648b710b3f1cd331d952d1b8`;
const UPGRADE_CAP = `0x0dcaf0958b3daf7d06718a579e235caf68091451d64ac9acb97b20ee19ad62e3`;
const GAME_TYPE = `${PACKAGE_ID}::gamehub::GameInfo`;

const RPC_URL = 'https://rpc-testnet.onelabs.cc:443';
const COIN_TYPE = '0x2::oct::OCT';

const client = new SuiClient({ url: RPC_URL });

const adminKeypair = Ed25519Keypair.fromSecretKey(process.env.ADMIN!);

const player1Keypair = Ed25519Keypair.fromSecretKey(process.env.USER_1!);
const player2Keypair = Ed25519Keypair.fromSecretKey(process.env.USER_2!);


const adminAddr = adminKeypair.toSuiAddress();
const p1Addr = player1Keypair.toSuiAddress();
const p2Addr = player2Keypair.toSuiAddress();

console.log('Admin:', adminAddr);
console.log('Player 1:', p1Addr);
console.log('Player 2:', p2Addr);

let createdRoomId: string;

async function executeTransaction(
    signer: Ed25519Keypair,
    tx: Transaction,
    description: string
) {
    console.log(`\n${description}...`);
    const address = signer.toSuiAddress();

    const coins = await client.getCoins({
        owner: address,
        coinType: COIN_TYPE
    });

    if (coins.data.length > 0) {
        const candidate = coins.data.find(c => BigInt(c.balance) > 50_000_000n);
        if (candidate) {
            const coinData = await client.getObject({ id: candidate.coinObjectId });
            if (coinData.data && coinData.data.version && coinData.data.digest) {
                tx.setGasPayment([{
                    objectId: coinData.data.objectId,
                    version: coinData.data.version,
                    digest: coinData.data.digest,
                }]);
            }
        }
    }

    try {
        const result = await client.signAndExecuteTransaction({
            signer,
            transaction: tx,
            options: {
                showEffects: true,
                showObjectChanges: true,
            },
        });

        if (result.effects?.status.status === 'success') {
            console.log(`✅ Success! Digest: ${result.digest}`);
            return result;
        } else {
            console.error(`Failed:`, result.effects?.status);
            throw new Error(`Transaction failed: ${result.effects?.status.error}`);
        }
    } catch (error) {
        console.error(`Error executing transaction:`, error);
        throw error;
    }
}

async function runGameHubFlow() {
    console.log('Starting GameHub Integration Test on OneChain');

    {
        const tx = new Transaction();
        tx.moveCall({
            target: `${PACKAGE_ID}::gamehub::update_config`,
            arguments: [
                tx.object(CONFIG_ID),
                tx.object(ADMIN_CAP_ID),
                tx.pure.u64(100),
                tx.pure.address(adminAddr),
            ],
        });

        try {
            tx.moveCall({
                target: `${PACKAGE_ID}::gamehub::register_game`,
                typeArguments: [GAME_TYPE],
                arguments: [tx.object(REGISTRY_ID), tx.pure.string("OneChain Game")],
            });
        } catch (e) { }

        await executeTransaction(adminKeypair, tx, "1. Admin Update Config & Register");
    }

    {
        const tx = new Transaction();
        const ENTRY_FEE = 1_000_000_000n;

        tx.moveCall({
            target: `${PACKAGE_ID}::gamehub::create_room`,
            typeArguments: [COIN_TYPE, GAME_TYPE], // Generic <T, G>
            arguments: [
                tx.object(REGISTRY_ID),
                tx.pure.u64(ENTRY_FEE),
                tx.pure.u8(2),
            ],
        });

        const result = await executeTransaction(adminKeypair, tx, "2. Admin Create Room");

        const createdObjects = result.objectChanges?.filter((c: any) => c.type === 'created') as any[];
        const roomObj = createdObjects.find(o => o.objectType.includes("::Room"));
        if (!roomObj) throw new Error("Room Object not found");

        createdRoomId = roomObj.objectId;
        console.log("Room ID:", createdRoomId);
    }

    {
        const tx = new Transaction();
        const ENTRY_FEE = 1_000_000_000n;

        const [feeCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(ENTRY_FEE)]);

        tx.moveCall({
            target: `${PACKAGE_ID}::gamehub::join_room`,
            typeArguments: [COIN_TYPE],
            arguments: [tx.object(createdRoomId), feeCoin],
        });

        await executeTransaction(player1Keypair, tx, "3. Player 1 Join Room");
    }

    {
        try {
            const tx = new Transaction();
            const ENTRY_FEE = 1_000_000_000n;
            const [feeCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(ENTRY_FEE)]);

            tx.moveCall({
                target: `${PACKAGE_ID}::gamehub::join_room`,
                typeArguments: [COIN_TYPE],
                arguments: [tx.object(createdRoomId), feeCoin],
            });

            await executeTransaction(player2Keypair, tx, "4. Player 2 Join Room");
        } catch (e) {
            console.warn(" Player 2 not found");
        }
    }

    {
        const tx = new Transaction();
        tx.moveCall({
            target: `${PACKAGE_ID}::gamehub::start_room`,
            typeArguments: [COIN_TYPE],
            arguments: [tx.object(createdRoomId), tx.object(ADMIN_CAP_ID)],
        });

        await executeTransaction(adminKeypair, tx, "5. Admin Start Room");
    }

    {
        const tx = new Transaction();
        const payoutAddr = [p1Addr, p2Addr];
        const payoutAmount = [2_000_000_000n, 0n];

        tx.moveCall({
            target: `${PACKAGE_ID}::gamehub::settle`,
            typeArguments: [COIN_TYPE],
            arguments: [
                tx.object(createdRoomId),
                tx.pure.vector('address', payoutAddr),
                tx.pure.vector('u64', payoutAmount),
                tx.object(ADMIN_CAP_ID),
            ],
        });

        await executeTransaction(adminKeypair, tx, "6. Admin Settle (P1 Wins)");
    }

    {
        const tx = new Transaction();
        tx.moveCall({
            target: `${PACKAGE_ID}::gamehub::claim`,
            typeArguments: [COIN_TYPE],
            arguments: [tx.object(CONFIG_ID), tx.object(createdRoomId)],
        });

        await executeTransaction(player1Keypair, tx, "7. Player 1 Claim Reward");
    }

    console.log('\n' + '='.repeat(60));
    console.log(' OneChain Test Flow Completed!');
}

await runGameHubFlow();