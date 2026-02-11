import { SuiClient, getFullnodeUrl } from "@onelabs/sui/client";
import * as dotenv from "dotenv";
import { Ed25519Keypair } from '@onelabs/sui/keypairs/ed25519';
import { Transaction } from '@onelabs/sui/transactions';


dotenv.config();
const suiClient = new SuiClient({ url: "https://rpc-testnet.onelabs.cc:443" });

const MY_ADDRESS = process.env.PUBLIC_KEY!;
const private_key = process.env.ADMIN!;
console.log(private_key);
//const keypair = Ed25519Keypair.deriveKeypair(private_key);
const keypair = Ed25519Keypair.fromSecretKey(private_key);

console.log(keypair.getPublicKey().toSuiAddress());

const packageId = "0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624";
const limiter_config = "0xc3dec3631e7f9e6e92cad026616dc82986124ba7b3a423725fe2fc7410c9b226";
const upgrade_cap = process.env.UPGRADE_CAP!;
const yoct_cap = "0xa4481144a0b15c4a7d37474e23bda3ca4cfe7c4715bacdeeb327031114f30d0f";
const rd_config = "0xd8404ef25f77e5dcb079b6483b56a553dfa5960d0ab9cfbccb585c3328bfe1f1";
const saver_config = "0xae863a179fdaaf82174115467311d182120c9c31e806b1e43abb8f809201c45d";
const sroct_cap = "0x78406325cb38ce881ac3100651f802723f5017743ce07da8b6c9d088f3bc804f";
const mock_vault = "0x63b79d58f5f890a24f3472c7e8d7e0969d11f7194a50e58f9a274bcff41c3b28"; // OCT  YOCT 
const clock = "0x6";
const sroct_minter = "0x54ae61550d7ab81956d628ca1b221bbcdf1220f70a937d1d3615359a587607e6";
const saver_yoct_vault = "0x71252e654cc5246fb9716cf65aa115467d0f594af4fb35f685ea4021fb75a4e9";
const keeper_cap = "0xc675414b31ecc1867e64b601891a0455f3bddae98e191fba1887f675aa00ee64";
const adapter_config = "0x13011b4c8a91583b00e402ed21530a95d299e974d003836a983d5bc0cbf53c71";
const ut = "0xb59b2c8aeea33f0d80865e7c154f0d2647f1c2db8678b6b3d78d122e029c7b29";
const liquidate_limiter = "0x067c26050d6dcb837c9c5cc2e1f3e9b51b47ff52d655565f07ae4cb26d0dfde4";
const rd_vault = "0xfc061a28b7b2c249bdcf0e99e04b00f5a09783aa92c8a938438346bbf0c1fb25";
const user_info = "0x6f39f00f9a47ce962b204b54d8e292ea8c218d9262e2fe46ad9b409f5c08b34d";

const ayoct_cap = "0x5836e6d4179e0aa7a21f2365894fc8ee93d891e5b8241e7bcb74ff0c871a89d1";
const oct = '0x2::oct::OCT';
const yoct = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::yoct::YOCT';
const sroct = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::sroct::SROCT';
const ayoct = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::ayoct::AYOCT';

async function init_mock_vault() {
    const moduleName = "mock";
    const functionName = "create_vault";
    const coinType1 = '0x2::oct::OCT';
    const coinType2 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::yoct::YOCT';
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
    const coinType = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::sroct::SROCT';
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
    const coinType = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::yoct::YOCT';
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


async function add_new_token_to_minter() {
    const moduleName = "saver";
    const functionName = "create_vault";
    const coinType1 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::yoct::YOCT';
    const coinType2 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::sroct::SROCT';
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
    const coinType = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::yoct::YOCT';
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

async function create_adapter_config() {
    const moduleName = "mock_adapter";
    const functionName = "create_adapter_config";
    const coinType1 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::yoct::YOCT';
    const coinType2 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::sroct::SROCT';
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
    const coinType2 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::yoct::YOCT';
    const coinType3 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::sroct::SROCT';
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
    const coinType2 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::yoct::YOCT';
    const coinType3 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::sroct::SROCT';
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
    const coinType2 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::yoct::YOCT';
    const coinType3 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::sroct::SROCT';
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
    const coinType2 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::yoct::YOCT';
    const coinType3 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::sroct::SROCT';
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
    const coinType2 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::yoct::YOCT';
    const coinType3 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::sroct::SROCT';
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
    const coinType2 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::yoct::YOCT';
    const coinType3 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::sroct::SROCT';
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
    const coinType2 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::yoct::YOCT';
    const coinType3 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::sroct::SROCT';
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
    const coinType2 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::yoct::YOCT';
    const coinType3 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::sroct::SROCT';
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
    const coinType2 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::yoct::YOCT';
    const coinType3 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::sroct::SROCT';
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
    const coinType2 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::yoct::YOCT';
    const coinType3 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::sroct::SROCT';
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

async function deposit2(amount: string) {

    const moduleName = "mock_adapter";
    const functionName = "deposit_underlying2";
    const coinType1 = "0x2::oct::OCT";
    const coinType2 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::yoct::YOCT';
    const coinType3 = '0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::sroct::SROCT';
    const tx = new Transaction();
    const amount_to_deposit = amount;
    const user_info_type = `0x9273d2ad5cfa2802ae43e71e52dd32951112b2beb49fdf91e535997172b5d624::saver::UserInfo<${coinType2},${coinType3}>`;
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
            tx.object.option({ type: user_info_type, value: null }),
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
    // await init_user_info();
    // await deposit("1000000000"); 
    // await mint("2000000") 
    //await burn(); 
    //await repay("90000000"); 
    //await redeem();
    //await change_minter();
    await deposit2("1000000000");
}

main();