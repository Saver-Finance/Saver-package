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

const packageId = "0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a";

const limiter_config = "0xed5d3a8a367d55964f5dbaba36d02da65e26f033c7e2cdd314ce16771beba06a";
const upgrade_cap = process.env.UPGRADE_CAP!;
const yoct_cap = "0xedb2bec699c90222522239f69200d6464abc40b3a1c8f5aefa52602d85263b47";
const rd_config = "0xf01aba7c4837d10ddc6ab71d827bb9c5b7c46717f6f536994de0cabbba7aabc1";
const saver_config = "0xca3ae4675b05bc32d4a58b20c1c03d7193931d62c63564c5e19b3e9362fd18c4";
const sroct_cap = "0x4183c3f7e0d2f6eafe42c553a12781ccd33b5d483448650c5ab9927c4ffc112c";
const mock_vault = "0xf70e7a95a68a0cf049bbf9425e0c2f6b30c4b6919ca1a2c2934b4cf34797eb75"; // OCT  YOCT 
const clock = "0x6";
const sroct_minter = "0x646cc2bcfe6cccad7581d9e105b626306ee8391b5fa644edf1db8f257f361a3d";
const saver_yoct_vault = "0xe26e439422eeaedc01ef8dcca6638f406c6836d9062c90e701744e6e9a0384ec";
const keeper_cap = "0xac53a2b8314e40dbe58497fb6897a351ce2454f4732700735a5d9ef2adf81163";
const adapter_config = "0xa288c11f7866eeb5ce9d5eb27720881c4982da0468d8cab93f2e6037eeadd56e";
const ut = "0x69ec13a6e9d14a8d77f2622bf568c4bbbd123521f11173d837deef83b88e8a70";
const liquidate_limiter = "0xcacbde553bbb14c615aaf1507e9551acbae5747c2ad76142555df4267f76517c";
const rd_vault = "0x5d8ad3ff5be7acd0d38e7828e82c16668b0fe1f82e1ce47af4c263f6da82ec95";
const user_info = "0x6f39f00f9a47ce962b204b54d8e292ea8c218d9262e2fe46ad9b409f5c08b34d";
const rd_account = "0x887c351fb6c9151a503b59b2ae3c08f2cea91557ff7806c3dc0e8618df057b3e";
const ayoct_cap = "0x9117c0006566ba6d40e3991b4c2e720102f510ff2b9035bf34030b8f7448927c";
const oct = '0x2::oct::OCT';
const yoct = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::yoct::YOCT';
const sroct = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::sroct::SROCT';
const ayoct = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::ayoct::AYOCT';

async function init_mock_vault() {
    const moduleName = "mock";
    const functionName = "create_vault";
    const coinType1 = '0x2::oct::OCT';
    const coinType2 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::yoct::YOCT';
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
    const coinType = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::sroct::SROCT';
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
    const coinType = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::yoct::YOCT';
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
    const coinType1 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::yoct::YOCT';
    const coinType2 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::sroct::SROCT';
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
    const coinType = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::yoct::YOCT';
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
    const coinType1 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::yoct::YOCT';
    const coinType2 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::sroct::SROCT';
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
    const coinType2 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::yoct::YOCT';
    const coinType3 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::sroct::SROCT';
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
    const coinType2 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::yoct::YOCT';
    const coinType3 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::sroct::SROCT';
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
    const coinType2 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::yoct::YOCT';
    const coinType3 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::sroct::SROCT';
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
    const coinType2 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::yoct::YOCT';
    const coinType3 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::sroct::SROCT';
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
    const coinType2 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::yoct::YOCT';
    const coinType3 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::sroct::SROCT';
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
    const coinType2 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::yoct::YOCT';
    const coinType3 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::sroct::SROCT';
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
    const coinType2 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::yoct::YOCT';
    const coinType3 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::sroct::SROCT';
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
    const coinType2 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::yoct::YOCT';
    const coinType3 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::sroct::SROCT';
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
    const coinType2 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::yoct::YOCT';
    const coinType3 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::sroct::SROCT';
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
    const coinType2 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::yoct::YOCT';
    const coinType3 = '0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::sroct::SROCT';
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
    await mint("100000000") // mint 1e8, mint them 6e8 de xem co revert khong, ltv = 50%
    //await burn(); // burn 1e7
    // còn 9e7 sroct, debt cũng còn 9e7 , hiện có  8998969252 
    //await repay("90000000"); // repay tất cả debt bằng 9e7 oct, balance sau repay 8907834276, debt = 0
    // redeem pool oct balance: 9e7
    //await redeem(); // dùng toàn bộ sroct để redeem, balance hiện tại 8907834276
    // sau redeem đã hết sroct, oct hiện tại 8997101416 
    // chênh lệnh 8997101416 - 8907834276 = 89,267,140 = 9e7 - fee
    //await change_minter();
}

main();