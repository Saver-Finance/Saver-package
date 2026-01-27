import { SuiClient } from '@onelabs/sui/client';
import { decodeSuiPrivateKey } from '@onelabs/sui/cryptography';
import { Ed25519Keypair } from '@onelabs/sui/keypairs/ed25519';
import { Transaction } from '@onelabs/sui/transactions';
// import { decodeSuiPrivateKey, fromB64 } from '@onelabs/sui/utils';
import dotenv from 'dotenv';
import { log } from 'node:console';
dotenv.config();

const RPC_URL = 'https://rpc-testnet.onelabs.cc:443';
const OCT_COIN_TYPE = '0x2::oct::OCT';
const TESTOCT_COIN_TYPE = '0x491543f6fa719b0fda3ad054355bae1849f468e326af88f83f3f1f4d9649e52f::testoct::TESTOCT';

const PACKAGE_ID = '0x37248427dc1d4b02503c716b8f16b9cf48893ce2f0d6746b9cfaceca65a16a1c';
const ADMIN_CAP_ID = `0x4ccf015d5197b6bf3d6f3f41e3215c5d36e670236709f604f27d673656cea110`;
const REGISTRY_ID = `0xd8faa05df92c73e5ec2d8e1d8e18d71eaec89cd116fdd2d3fc9f4b23f0e848e2`;
const CONFIG_ID = `0x8afa79678ecaccbf5705dac01d09cff2eb4351aa07b02d2ff47d74853813b1d0`;
const UPGRADE_CAP = `0x9f81b0fa8eefd345ff3345186243d5cd26773f8d340d3110a6b99d620b1d7f9c`;
const BOMB_PANIC_OCT_TYPE = `${PACKAGE_ID}::bomb_panic::GameState<${OCT_COIN_TYPE}>`;
const GAME_CAP_ID = `0x826d342eb5c4fedd9012fd311997d04904db9e55f49779754ab5a7dced6839f8`;
const ROOM_ID = `0x2ca090968e4e9cc003ce7c7fe851be957b27122b1f3f5fb4b8dfd6b10e238217`;

const client = new SuiClient({ url: RPC_URL });

const adminKeypair = Ed25519Keypair.deriveKeypair(process.env.ADMIN!);
const player1Keypair = Ed25519Keypair.deriveKeypair(process.env.USER_1!);
const player2Keypair = Ed25519Keypair.deriveKeypair(process.env.USER_2!);

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
        coinType: OCT_COIN_TYPE
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

    // {
        // const tx = new Transaction();
        // tx.moveCall({
        //     target: `${PACKAGE_ID}::gamehub::update_config`,
        //     arguments: [
        //         tx.object(CONFIG_ID),
        //         tx.object(ADMIN_CAP_ID),
        //         tx.pure.u64(100),
        //         tx.pure.address(adminAddr),
        //     ],
        // });
        // tx.moveCall({
        //     target: `${PACKAGE_ID}::gamehub::add_whitelist`,
        //     typeArguments: [OCT_COIN_TYPE],
        //     arguments: [
        //         tx.object(CONFIG_ID),
        //         tx.object(ADMIN_CAP_ID)
        //     ]
        // });

        // tx.moveCall({
        //     target: `${PACKAGE_ID}::gamehub::add_whitelist`,
        //     typeArguments: [TESTOCT_COIN_TYPE],
        //     arguments: [
        //         tx.object(CONFIG_ID),
        //         tx.object(ADMIN_CAP_ID)
        //     ]
        // });
    //     try {
    //         tx.moveCall({
    //             target: `${PACKAGE_ID}::gamehub::register_game`,
    //             typeArguments: [GAME_TYPE],
    //             arguments: [
    //                 tx.object(REGISTRY_ID),
    //                 tx.object(ADMIN_CAP_ID),
    //                 tx.pure.string("OneChain Game")
    //             ],
    //         });
    //     } catch (e) { }

    //     await executeTransaction(adminKeypair, tx, "1. Admin Update Config & Register");
    // }

    // Add Whitelist
    // await addWhitelist(COIN_TYPE);

    // {
    //     const tx = new Transaction();
    //     const FEE_AMOUNT = 1_000n;

    // // 1. Lấy tất cả coin loại OCT của Admin
    // const { data: coins } = await client.getCoins({ 
    //     owner: adminAddr, 
    //     coinType: OCT_COIN_TYPE 
    // });

    // // if (coins.length === 0) throw new Error("Admin");

    // let gasObjectId: string;
    // let paymentCoin: any;

    // if (coins.length === 1) {
    //     const [feeCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(FEE_AMOUNT)]);
    //     paymentCoin = feeCoin;
    // } else {
    //     tx.setGasPayment([{ 
    //         objectId: coins[0].coinObjectId, 
    //         version: coins[0].version, 
    //         digest: coins[0].digest 
    //     }]);
    //     const [feeCoin] = tx.splitCoins(
    //         tx.object(coins[1].coinObjectId), 
    //         [tx.pure.u64(FEE_AMOUNT)]
    //     );
    //     paymentCoin = feeCoin;
    // }

    //     tx.moveCall({
    //         target: `${PACKAGE_ID}::gamehub::create_room`,
    //         typeArguments: [OCT_COIN_TYPE, BOMB_PANIC_OCT_TYPE], // <T, G>
    //         arguments: [
    //             tx.object(REGISTRY_ID),   // registry
    //             tx.object(CONFIG_ID),     // config 
    //             tx.pure.u64(FEE_AMOUNT), // entry_fee
    //             tx.pure.u8(2),            // max_players
    //             paymentCoin                   // creation_fee 
    //         ],
    //     });

    //     const result = await executeTransaction(adminKeypair, tx, "2. Admin Create Room");

    //     const createdObjects = result.objectChanges?.filter((c: any) => c.type === 'created') as any[];
    //     const roomObj = createdObjects.find(o => o.objectType.includes("::Room"));
    //     if (!roomObj) throw new Error("Room Object not found");

    //     createdRoomId = roomObj.objectId;
    //     console.log("Room ID:", createdRoomId);
    // }

    // {
    //     const tx = new Transaction();
    //     const ENTRY_FEE = 1_000_000_000n;

    //     const [feeCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(ENTRY_FEE)]);

    //     tx.moveCall({
    //         target: `${PACKAGE_ID}::gamehub::join_room`,
    //         typeArguments: [TESTOCT_COIN_TYPE],
    //         arguments: [tx.object(createdRoomId), feeCoin],
    //     });

    //     await executeTransaction(player1Keypair, tx, "3. Player 1 Join Room");
    // }

    // {
    //     try {
    //         const tx = new Transaction();
    //         // const ENTRY_FEE = 1_000_000_000n;
    //         // const [feeCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(ENTRY_FEE)]);

    //         tx.moveCall({
    //             target: `${PACKAGE_ID}::gamehub::join_room`,
    //             typeArguments: [OCT_COIN_TYPE],
    //             arguments: [tx.object(ROOM_ID)],
    //         });

    //         await executeTransaction(player1Keypair, tx, "4. Player 1 Join Room");
    //     } catch (e) {
    //         console.warn(" Player 1 not found");
    //     }
    // }

    // {
    //     // const roomData = await client.getObject({
    //     //     id: ROOM_ID,
    //     //     options: { showContent: true }
    //     // });

    //     // // Truy cập vào field pool
    //     // const content = roomData.data?.content as any;
    //     // const poolAmount = content.fields.pool; 

    //     // console.log(`💰 Số tiền hiện tại trong Pool: ${poolAmount} OCT`);
    //     const tx = new Transaction();
    //     const ENTRY_FEE = 2_000n;
    //     const [feeCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(ENTRY_FEE)]);
    //     try {
    //         tx.moveCall({
    //             target: `${PACKAGE_ID}::gamehub::ready_to_play_entry`,
    //             typeArguments: [OCT_COIN_TYPE],
    //             arguments: [tx.object(ROOM_ID), feeCoin],
    //         });
    //         await executeTransaction(player1Keypair, tx, "5. Player 1 Ready To Play Entry");
    //     } catch (e) {
    //         console.warn(e);
    //     }
    // }

    // {
    //     const tx = new Transaction();
    //     tx.moveCall({
    //         target: `${PACKAGE_ID}::gamehub::start_room`,
    //         typeArguments: [OCT_COIN_TYPE],
    //         arguments: [tx.object(ROOM_ID), tx.object(ADMIN_CAP_ID)],
    //     });

    //     await executeTransaction(adminKeypair, tx, "5. Admin Start Room");
    // }

    // {
    //     const tx = new Transaction();
    //     const payoutAddr = [p1Addr, p2Addr];
    //     const payoutAmount = [2_000_000_000n, 0n];

    //     tx.moveCall({
    //         target: `${PACKAGE_ID}::gamehub::settle`,
    //         typeArguments: [OCT_COIN_TYPE],
    //         arguments: [
    //             tx.object(createdRoomId),
    //             tx.pure.vector('address', payoutAddr),
    //             tx.pure.vector('u64', payoutAmount),
    //             tx.object(ADMIN_CAP_ID),
    //         ],
    //     });

    //     await executeTransaction(adminKeypair, tx, "6. Admin Settle (P1 Wins)");
    // }

    // {
    //     const tx = new Transaction();
    //     tx.moveCall({
    //         target: `${PACKAGE_ID}::gamehub::claim`,
    //         typeArguments: [OCT_COIN_TYPE],
    //         arguments: [tx.object(CONFIG_ID), tx.object(createdRoomId)],
    //     });

    //     await executeTransaction(player1Keypair, tx, "7. Player 1 Claim Reward");
    // }

    // console.log('\n' + '='.repeat(60));
    // console.log(' OneChain Test Flow Completed!');
}

await runGameHubFlow();