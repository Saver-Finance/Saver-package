import { SuiClient, getFullnodeUrl } from "@onelabs/sui/client";
import * as dotenv from "dotenv";
import { Ed25519Keypair } from '@onelabs/sui/keypairs/ed25519';
import { Transaction } from '@onelabs/sui/transactions';


dotenv.config();
const suiClient = new SuiClient({ url: "https://rpc-testnet.onelabs.cc:443" });

const MY_ADDRESS = process.env.PUBLIC_KEY!;
const secret_key = process.env.PRIVATE_KEY!;
const keypair = Ed25519Keypair.fromSecretKey(secret_key);

console.log(keypair.getPublicKey().toSuiAddress());

const packageId = "0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff";

const limiter_config = "0xc67391154cc2adb68cbd3f2d4bf4795b67d0eb6b042e68dc2e26b51593233bea";
const upgrade_cap = "0x3cdf0027df0dec6b4b0c102b698d422fd6a1b3d7c2e56d072b5f1267d7b92ec1";
const yoct_cap = "0xf67c96c757abc20279ffd738fb921754084f3b6ef5b9643e4c29e264275d3e33";
const rd_config = "0xa2f9729cf6dfa4b64dd63162a0efc8f8f01b9393bf7aacaeeb95bbe5c112ae41";
const saver_config = "0xa56a0b697ab5dadc7650c58559360d29e6671de368034611ae74b55d41b64921";
const sroct_cap = "0x6eb11b1ce86db0a01252b21e3c8e9402d6f3e0bb7c8154b926f09da5f10e83f7";
const mock_vault = "0x32f22551866e2bc3ab674d6cdb5ab08350df6c0ae7e9e8855c9b787504df6471"; // OCT  YOCT 
const clock = "0x6";
const sroct_minter = "0xa400d2b70bb34b3fbbb340e36edea13ad72df00532a459741046723f1e33ae65";
const saver_yoct_vault = "0x08552ef7d945befccde7c07a100e97d28bd5c5cc63f34e51e8c763cb87fd9257";
const keeper_cap = "0x0c3cca2a40ebc7afb4e6cef742d93b06fe406edeb5ed003cfe795ad7d691338a";
const adapter_config = "0x9aed760b1af3b634d742fda92d2c59a1cf57c08a7cedb555932217d825d31650";
const ut = "0xd7f52795f1b97617564c422c90b8f0766077547b6f3e11bb7d769f64d8dc7810";
const liquidate_limiter = "0xae3b7f93c0ab1193573615fbda9eb20654acfc3c62c82640c1e6fe67d16d7dce";
const rd_vault = "0x9c5681c908cec3ae0b5dc31b8a51271c5ff4e39d2b6d0b95fa5d126f20c29b93";
const user_info = "0x828068a7fdf18e6ce95b63a9c00d6c6d6fb70d962ff02d83dc60cc00ea5f677f";
const rd_account = "0x887c351fb6c9151a503b59b2ae3c08f2cea91557ff7806c3dc0e8618df057b3e";

async function init_mock_vault() {
    const moduleName = "mock";
    const functionName = "create_vault";
    const coinType1 = '0x2::oct::OCT';
    const coinType2 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::yoct::YOCT';
    const tx = new Transaction();
    tx.moveCall({
        target: `${packageId}::${moduleName}::${functionName}`,
        typeArguments: [coinType1, coinType2],
        arguments: [
            tx.object(yoct_cap),
        ],
    });
    const result = await suiClient.signAndExecuteTransaction({
        signer: keypair,
        transaction: tx,
        options: {
            showEffects: true,
        }
    });

    console.log(result.digest);
}

async function create_new_minter() {
    const moduleName = "saver";
    const functionName = "create_new_minter";
    const coinType = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::sroct::SROCT';
    const tx = new Transaction();
    tx.moveCall({
        target: `${packageId}::${moduleName}::${functionName}`,
        typeArguments: [coinType],
        arguments: [
            tx.object(sroct_cap),
            tx.object(saver_config),
            tx.object(limiter_config),
            tx.object(clock),
            tx.pure.u128(1e18),
            tx.pure.u128(0),
            tx.pure.u128(85000),
            tx.pure.u128(1000),
            tx.pure.address(MY_ADDRESS),
            tx.pure.u128(2e18),
        ],
    });
    const result = await suiClient.signAndExecuteTransaction({
        signer: keypair,
        transaction: tx,
        options: {
            showEffects: true,
        }
    });

    console.log(result.digest);
}

async function create_saver_reverse() {
    const moduleName = "saver";
    const functionName = "init_vault_reserve";
    const coinType = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::yoct::YOCT';
    const tx = new Transaction();
    tx.moveCall({
        target: `${packageId}::${moduleName}::${functionName}`,
        typeArguments: [coinType],
        arguments: [
            tx.object(saver_config),
        ],
    });
    const result = await suiClient.signAndExecuteTransaction({
        signer: keypair,
        transaction: tx,
        options: {
            showEffects: true,
        }
    });

    console.log(result.digest);
}


async function add_new_token_to_minter(){
    const moduleName = "saver";
    const functionName = "create_vault";
    const coinType1 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::yoct::YOCT';
    const coinType2 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::sroct::SROCT';
    const tx = new Transaction();
    tx.moveCall({
        target: `${packageId}::${moduleName}::${functionName}`,
        typeArguments: [coinType1, coinType2],
        arguments: [
            tx.object(saver_config),
            tx.object(clock),
            tx.object(sroct_minter),
            tx.pure.u8(9),
            tx.pure.u128("1000000000000000000"),
            tx.pure.u128("1000000000000000000"),
            tx.pure.u128("1700000000000"),
        ],
    });
    const result = await suiClient.signAndExecuteTransaction({
        signer: keypair,
        transaction: tx,
        options: {
            showEffects: true,
        }
    });

    console.log(result.digest);
}

async function grant_keeper_cap() {
    const moduleName = "saver";
    const functionName = "grant_keeper_cap";
    const coinType = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::yoct::YOCT';
    const tx = new Transaction();
    tx.moveCall({
        target: `${packageId}::${moduleName}::${functionName}`,
        typeArguments: [],
        arguments: [
            tx.object(saver_config),
            tx.pure.address(MY_ADDRESS)
        ],
    });
    const result = await suiClient.signAndExecuteTransaction({
        signer: keypair,
        transaction: tx,
        options: {
            showEffects: true,
        }
    });

    console.log(result.digest);
}

async function  create_adapter_config() {
    const moduleName = "mock_adapter";
    const functionName = "create_adapter_config";
    const coinType1 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::yoct::YOCT';
    const coinType2 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::sroct::SROCT';
    const tx = new Transaction();
    tx.moveCall({
        target: `${packageId}::${moduleName}::${functionName}`,
        typeArguments: [],
        arguments: [
            tx.object(saver_config),
        ],
    });
    const result = await suiClient.signAndExecuteTransaction({
        signer: keypair,
        transaction: tx,
        options: {
            showEffects: true,
        }
    });

    console.log(result.digest);
}

async function create_ut() {
    const moduleName = "mock_adapter";
    const functionName = "create_underlying_token_object";
    const coinType1 = "0x2::oct::OCT";
    const coinType2 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::yoct::YOCT';
    const coinType3 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::sroct::SROCT';
    const tx = new Transaction();
    tx.moveCall({
        target: `${packageId}::${moduleName}::${functionName}`,
        typeArguments: [coinType1, coinType2, coinType3],
        arguments: [
            tx.object(adapter_config),
            tx.object(limiter_config),
            tx.pure.u8(9),
            tx.pure.u8(9),
            tx.pure.u128("1000000000000000000"),
            tx.pure.u128(0),
            tx.pure.u128(85000),
            tx.object(clock)
        ],
    });
    const result = await suiClient.signAndExecuteTransaction({
        signer: keypair,
        transaction: tx,
        options: {
            showEffects: true,
        }
    });

    console.log(result.digest);
}

async function create_liquidate_limiter() {
    const moduleName = "mock_adapter";
    const functionName = "create_liquidate_limiter";
    const coinType1 = "0x2::oct::OCT";
    const coinType2 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::yoct::YOCT';
    const coinType3 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::sroct::SROCT';
    const tx = new Transaction();
    tx.moveCall({
        target: `${packageId}::${moduleName}::${functionName}`,
        typeArguments: [coinType1, coinType2, coinType3],
        arguments: [
            tx.object(adapter_config),
            tx.object(limiter_config),
            tx.pure.u128("1000000000000000000"),
            tx.pure.u128(0),
            tx.pure.u128(85000),
            tx.object(clock)
        ],
    });
    const result = await suiClient.signAndExecuteTransaction({
        signer: keypair,
        transaction: tx,
        options: {
            showEffects: true,
        }
    });

    console.log(result.digest);
}

async function create_rd_vault() {
    const moduleName = "redeem_pool";
    const functionName = "create_vault";
    const coinType1 = "0x2::oct::OCT";
    const coinType2 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::yoct::YOCT';
    const coinType3 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::sroct::SROCT';
    const tx = new Transaction();
    tx.moveCall({
        target: `${packageId}::${moduleName}::${functionName}`,
        typeArguments: [coinType1, coinType3],
        arguments: [
            tx.object(rd_config),
            tx.pure.u8(9),
            tx.pure.u8(9)
        ],
    });
    const result = await suiClient.signAndExecuteTransaction({
        signer: keypair,
        transaction: tx,
        options: {
            showEffects: true,
        }
    });

    console.log(result.digest);
}

async function init_user_info() {
    const moduleName = "saver";
    const functionName = "init_user_info";
    const coinType1 = "0x2::oct::OCT";
    const coinType2 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::yoct::YOCT';
    const coinType3 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::sroct::SROCT';
    const tx = new Transaction();

    tx.moveCall({
        target: `${packageId}::${moduleName}::${functionName}`,
        typeArguments: [coinType2, coinType3],
        arguments: [
           tx.object(sroct_minter),
        ],
    });
    const result = await suiClient.signAndExecuteTransaction({
        signer: keypair,
        transaction: tx,
        options: {
            showEffects: true,
        }
    });

    console.log(result.digest);
}

async function deposit(amount: string) {
    const moduleName = "mock_adapter";
    const functionName = "deposit_underlying";
    const coinType1 = "0x2::oct::OCT";
    const coinType2 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::yoct::YOCT';
    const coinType3 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::sroct::SROCT';
    const tx = new Transaction();
    const amount_to_deposit = amount;
    let coin_input = tx.splitCoins(
        tx.gas,
        [tx.pure.u64(amount_to_deposit)]
    );
    tx.moveCall({
        target: `${packageId}::${moduleName}::${functionName}`,
        typeArguments: [coinType1, coinType2, coinType3],
        arguments: [
           tx.object(ut),
           tx.object(adapter_config),
           coin_input,
           tx.object(user_info),
           tx.object(saver_yoct_vault),
           tx.object(sroct_minter),
           tx.object(clock),
           tx.object(mock_vault)
        ],
    });
    const result = await suiClient.signAndExecuteTransaction({
        signer: keypair,
        transaction: tx,
        options: {
            showEffects: true,
        }
    });

    console.log(result.digest);
}

async function mint(amount: string) {
    const moduleName = "mock_adapter";
    const functionName = "mint";
    const coinType1 = "0x2::oct::OCT";
    const coinType2 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::yoct::YOCT';
    const coinType3 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::sroct::SROCT';
    const tx = new Transaction();
    // const amount_to_deposit = 1000000;
    // let coin_input = tx.splitCoins(
    //     tx.gas,
    //     [tx.pure.u64(amount_to_deposit)]
    // );
    tx.moveCall({
        target: `${packageId}::${moduleName}::${functionName}`,
        typeArguments: [coinType1, coinType2, coinType3],
        arguments: [
            tx.object(ut),
            tx.object(adapter_config),
            tx.object(user_info),
            tx.object(sroct_minter),
            tx.object(clock),
            tx.pure.u64(amount),
            tx.pure.address(MY_ADDRESS),
            tx.object(mock_vault)
        ],
    });
    const result = await suiClient.signAndExecuteTransaction({
        signer: keypair,
        transaction: tx,
        options: {
            showEffects: true,
        }
    });

    console.log(result.digest);
}



async function burn() {
    const moduleName = "mock_adapter";
    const functionName = "burn";
    const coinType1 = "0x2::oct::OCT";
    const coinType2 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::yoct::YOCT';
    const coinType3 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::sroct::SROCT';
    const tx = new Transaction();
 
    tx.moveCall({
        target: `${packageId}::${moduleName}::${functionName}`,
        typeArguments: [coinType2, coinType3],
        arguments: [
            tx.object(adapter_config),
            tx.object(user_info),
            tx.object("0x2b11de8c0ca9df6d195a9d92c495083595f204667947b2ec99e8f5930a5a542e"),
            tx.object(sroct_minter),
            tx.object(clock),
        ],
    });
    const result = await suiClient.signAndExecuteTransaction({
        signer: keypair,
        transaction: tx,
        options: {
            showEffects: true,
        }
    });

    console.log(result.digest);
}



async function repay(amount: string) {
    const moduleName = "mock_adapter";
    const functionName = "repay";
    const coinType1 = "0x2::oct::OCT";
    const coinType2 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::yoct::YOCT';
    const coinType3 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::sroct::SROCT';
    const tx = new Transaction();
    const amount_to_deposit = amount;
    let coin_input = tx.splitCoins(
        tx.gas,
        [tx.pure.u64(amount_to_deposit)]
    );
    tx.moveCall({
        target: `${packageId}::${moduleName}::${functionName}`,
        typeArguments: [coinType1, coinType2, coinType3],
        arguments: [
            tx.object(adapter_config),
            tx.object(ut),
            coin_input,
            tx.object(user_info),
            tx.object(sroct_minter),
            tx.object(clock),
            tx.object(rd_config),
            tx.object(rd_vault),
            tx.object(mock_vault)
        ],
    });
    const result = await suiClient.signAndExecuteTransaction({
        signer: keypair,
        transaction: tx,
        options: {
            showEffects: true,
        }
    });

    console.log(result.digest);
}

async function change_minter() {
    const moduleName = "saver";
    const functionName = "change_minter";
    const coinType1 = "0x2::oct::OCT";
    const coinType2 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::yoct::YOCT';
    const coinType3 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::sroct::SROCT';
    const tx = new Transaction();
    // const amount_to_deposit = 13600000;
    // let coin_input = tx.splitCoins(
    //     tx.gas,
    //     [tx.pure.u64(amount_to_deposit)]
    // );
    tx.moveCall({
        target: `${packageId}::${moduleName}::${functionName}`,
        typeArguments: [coinType2, coinType3],
        arguments: [
            tx.object(saver_config),
            tx.object(sroct_minter),
            tx.pure.option("u8", 9),        // Some(9)
            tx.pure.option("u128", null),   // None
            tx.pure.option("u128", null),   // None
            tx.pure.option("u128", null),   // None
            tx.pure.option("bool", null),   // None
        ],
    });
    const result = await suiClient.signAndExecuteTransaction({
        signer: keypair,
        transaction: tx,
        options: {
            showEffects: true,
        }
    });

    console.log(result.digest);
}

async function redeem() {
    const moduleName = "redeem_pool";
    const functionName = "redeem";
    const coinType1 = "0x2::oct::OCT";
    const coinType2 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::yoct::YOCT';
    const coinType3 = '0x397c94d79dd96411c770a4d1893a6b23a8487d34db6998cdec772fde475118ff::sroct::SROCT';
    const tx = new Transaction();

    tx.moveCall({
        target: `${packageId}::${moduleName}::${functionName}`,
        typeArguments: [coinType1, coinType3],
        arguments: [
            tx.object(rd_config),
            tx.object(rd_vault),
            tx.object("0x80e5e81883ecc53a832661ee58313f13a2bb8272981fde8ccd6bf58c1f78df99"),
            tx.object(sroct_minter),
            tx.pure.address(MY_ADDRESS),
        ],
    });
    const result = await suiClient.signAndExecuteTransaction({
        signer: keypair,
        transaction: tx,
        options: {
            showEffects: true,
        }
    });

    console.log(result.digest);
}

async function main() {
    //await init_mock_vault();
    //await create_new_minter();
    //await create_saver_reverse();
    //await add_new_token_to_minter();
    //await grant_keeper_cap();
    //await create_adapter_config();
    //await create_ut();
    //await create_liquidate_limiter();
    //await create_rd_vault();
    //await init_user_info();
    //await deposit("1000000000"); // deposit 1e9 OCT, balance hien tai 10004662000
    //await mint("600000000") // mint 1e8, mint them 6e8 de xem co revert khong, ltv = 50%
    //await burn(); // burn 1e7
    // còn 9e7 sroct, debt cũng còn 9e7 , hiện có  8998969252 
    //await repay("90000000"); // repay tất cả debt bằng 9e7 oct, balance sau repay 8907834276, debt = 0
    // redeem pool oct balance: 9e7
    await redeem(); // dùng toàn bộ sroct để redeem, balance hiện tại 8907834276
    // sau redeem đã hết sroct, oct hiện tại 8997101416 
    // chênh lệnh 8997101416 - 8907834276 = 89,267,140 = 9e7 - fee
    //await change_minter();
}

main();