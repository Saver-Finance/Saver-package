#[test_only]
module saver::saver_tests;
use std::unit_test;
use saver::saver::{Self, Config as SaverConfig, Vault as SaverReserve, Minter as SaverMinter, UserInfo as SaverUserInfo};
use saver::mock_adapter::{Self, AdapterConfig, UnderlyingToken, LiquidateLimiter};
use saver::limiter::{Self, LimiterConfig};
use saver::mock::{Self, Vault as MockVault};
use saver::redeem_pool::{Self, Config as RdConfig, Vault as RdVault};
use saver::yoct::{Self, YOCT};
use saver::sroct::{Self, SROCT};
use saver::error::{Self};
use one::oct::{Self, OCT};
use one::test_scenario::{Self, Scenario};
use one::test_utils::{Self};
use one::coin::{Self, TreasuryCap, Coin};
use one::transfer::{Self};
use one::clock::{Self, Clock};
use std::debug::{Self, print};
use std::string::{Self, String};



const ENotImplemented: u64 = 0;
const AssignWrong: u64 = 1;
const DepositFail: u64 = 2;

const Admin: address = @0xA;
const User1: address = @0xB;
const User2: address = @0xC;
const Keeper: address = @0xD;


const FIXED_POINT_SCALAR: u128 = 1000000000000000000;
const MAXIMUM_LIMIT: u128 = 1000000000000000000;
const MAX_DURATION: u128 = 85000;
const MIN_LIMIT: u128 = 0;
const PROTOCOL_FEE: u128 = 1000;
const MINIMUM_COLLATERLIZATION: u128 = 2 * FIXED_POINT_SCALAR;


fun init_redeem_pool(scenario: &mut Scenario) {
    test_scenario::next_tx(scenario, Admin);
    redeem_pool::test_init(test_scenario::ctx(scenario));
    test_scenario::next_tx(scenario, Admin);

    let rd_config = test_scenario::take_shared<RdConfig>(scenario);
    redeem_pool::create_vault<OCT, SROCT>(
        &rd_config,
        9,
        9,
        test_scenario::ctx(scenario)
    );
    test_scenario::next_tx(scenario, Admin);
    test_scenario::return_shared(rd_config);
}

fun init_limiter(scenario: &mut Scenario) {
    test_scenario::next_tx(scenario, Admin);    
    limiter::test_init(test_scenario::ctx(scenario));
    test_scenario::next_tx(scenario, Admin);
}

fun init_saver(clock: &Clock, scenario: &mut Scenario){
    test_scenario::next_tx(scenario, Admin);

    // init saver config
    saver::test_init(test_scenario::ctx(scenario));

    // create minter for debt token
    test_scenario::next_tx(scenario, Admin);
    
    let limiter_config = test_scenario::take_shared<LimiterConfig>(scenario);
    let treasury_cap = test_scenario::take_from_address<TreasuryCap<SROCT>>(scenario, Admin);
    let saver_config = test_scenario::take_shared<SaverConfig>(scenario);
    saver::create_new_minter(
        treasury_cap,
        &saver_config,
        &limiter_config,
        clock,
        MAXIMUM_LIMIT,
        MIN_LIMIT,
        MAX_DURATION,
        PROTOCOL_FEE,
        Admin,
        MINIMUM_COLLATERLIZATION,
        test_scenario::ctx(scenario)
    );

    // create reserve
    test_scenario::next_tx(scenario, Admin);
    
    saver::init_vault_reserve<YOCT>(
        &saver_config,
        test_scenario::ctx(scenario)
    );

    // ceate vault
    test_scenario::next_tx(scenario, Admin);
    
    let mut yoct_minter = test_scenario::take_shared<SaverMinter<SROCT>>(scenario);
    saver::create_vault<YOCT, SROCT>(
        &saver_config,
        clock,
        &mut yoct_minter,
        9,
        MAXIMUM_LIMIT,
        MAXIMUM_LIMIT / 1000,
        FIXED_POINT_SCALAR / 604800,
        test_scenario::ctx(scenario)
    );
    test_scenario::next_tx(scenario, Admin);
    saver::grant_keeper_cap(
        &saver_config,
        Keeper,
        test_scenario::ctx(scenario)
    );
    test_scenario::next_tx(scenario, Admin);

    // return share object
    test_scenario::return_shared(saver_config);
    test_scenario::return_shared(limiter_config);
    test_scenario::return_shared(yoct_minter);

    test_scenario::next_tx(scenario, Admin);
}

fun init_adapter(clock: &Clock, scenario: &mut Scenario) {
    test_scenario::next_tx(scenario, Admin);

    // take all objects required
    let saver_config = test_scenario::take_shared<SaverConfig>(scenario);
    let limiter_config = test_scenario::take_shared<LimiterConfig>(scenario);

    // create adapter config
    test_scenario::next_tx(scenario, Admin);
    
    
    mock_adapter::create_adapter_config(&saver_config, test_scenario::ctx(scenario));

    test_scenario::next_tx(scenario, Admin);
    let adapter_config = test_scenario::take_shared<AdapterConfig>(scenario);

    // create U T S
    test_scenario::next_tx(scenario, Admin);
    
    mock_adapter::create_underlying_token_object<OCT, YOCT, SROCT>(
        &adapter_config,
        &limiter_config,
        9,
        9,
        MAXIMUM_LIMIT,
        MIN_LIMIT,
        MAX_DURATION,
        clock,
        test_scenario::ctx(scenario)
    );

    // create liquidate limiter
    test_scenario::next_tx(scenario, Admin);
    
    mock_adapter::create_liquidate_limiter<OCT, YOCT, SROCT>(
        &adapter_config,
        &limiter_config,
        MAXIMUM_LIMIT,
        MIN_LIMIT,
        MAX_DURATION,
        clock,
        test_scenario::ctx(scenario)
    );
    test_scenario::next_tx(scenario, Admin);
    // return object
    test_scenario::return_shared(saver_config);
    test_scenario::return_shared(limiter_config);
    test_scenario::return_shared(adapter_config);

    test_scenario::next_tx(scenario, Admin);
}

fun init_shares_vault(_clock: &Clock, scenario: &mut Scenario) {
    test_scenario::next_tx(scenario, Admin);
    
    // create YOCT
    yoct::test_init(test_scenario::ctx(scenario));

    test_scenario::next_tx(scenario, Admin);
    let mut treasury_cap = test_scenario::take_from_sender<TreasuryCap<YOCT>>(scenario);

    test_scenario::next_tx(scenario, Admin);
    
    mock::create_vault<OCT, YOCT>(
        treasury_cap,
        test_scenario::ctx(scenario)
    );
    test_scenario::next_tx(scenario, Admin);
}

fun create_sroct(_clock: &Clock, scenario: &mut Scenario) {
    test_scenario::next_tx(scenario, Admin);
    sroct::test_init( test_scenario::ctx(scenario));
    test_scenario::next_tx(scenario, Admin);
}

fun prepare_state(clock: &Clock, scenario: &mut Scenario) {
    test_scenario::next_tx(scenario, Admin);
    create_sroct(clock, scenario);
    init_shares_vault(clock, scenario);
    init_limiter(scenario);
    init_saver(clock, scenario);
    init_adapter(clock, scenario);
    init_redeem_pool(scenario);
    test_scenario::next_tx(scenario, Admin);
}

fun init_saver_user_info<T, S>(minter: &SaverMinter<S>, scenario: &mut Scenario, sender: address) {
    test_scenario::next_tx(scenario, sender);
    saver::init_user_info<T, S>(minter, test_scenario::ctx(scenario));
    test_scenario::next_tx(scenario, sender);
}

fun grant_coin<T>(
    user: address, 
    amount: u64,
    scenario: &mut Scenario
) {
    test_scenario::next_tx(scenario, Admin);
    let new_coin = coin::mint_for_testing<T>(amount, test_scenario::ctx(scenario));
    transfer::public_transfer(new_coin, user);
}

fun mint_coin<T>(
    amount: u64,
    scenario: &mut Scenario
): Coin<T> {
    test_scenario::next_tx(scenario, Admin);
    coin::mint_for_testing<T>(amount, test_scenario::ctx(scenario))
}


#[test]
fun test_init() {
    // init clock and scenario
    let mut scenario = test_scenario::begin(Admin);
    let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1000);
    prepare_state(&clock, &mut scenario);

    // take all shared objects
    let saver_config = test_scenario::take_shared<SaverConfig>(&scenario);
    let limiter_config = test_scenario::take_shared<LimiterConfig>(&scenario);
    let adapter_config = test_scenario::take_shared<AdapterConfig>(&scenario);
    let mock_share_vault = test_scenario::take_shared<MockVault<OCT, YOCT>>(&scenario);
    let yoct_minter = test_scenario::take_shared<SaverMinter<SROCT>>(&scenario);

    // check saver info 
    let (saver_admin, saver_pending_admin) = saver::get_config(&saver_config);
    print(&saver_config);
    assert!(saver_admin == Admin, AssignWrong);
    assert!(saver_pending_admin == Admin, AssignWrong);
    
    // check share vault
    print(&mock_share_vault);

    // check yoct_minter
    print(&yoct_minter);

    // return all shared objects 
    test_scenario::return_shared(saver_config);
    test_scenario::return_shared(limiter_config);
    test_scenario::return_shared(yoct_minter);
    test_scenario::return_shared(adapter_config);
    test_scenario::return_shared(mock_share_vault);
 

    test_scenario::next_tx(&mut scenario, Admin);

    test_scenario::end(scenario);
    clock::destroy_for_testing(clock);
}

#[test]
fun test_deposit() {

    // init clock and scenario
    let mut scenario = test_scenario::begin(Admin);
    let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1000);
    prepare_state(&clock, &mut scenario);

    // take all shared objects
    let uts = test_scenario::take_shared<UnderlyingToken<OCT, YOCT, SROCT>>(&scenario);
    let mut saver_vault_reserve = test_scenario::take_shared<SaverReserve<YOCT>>(&scenario);
    let saver_config = test_scenario::take_shared<SaverConfig>(&scenario);
    let limiter_config = test_scenario::take_shared<LimiterConfig>(&scenario);
    let adapter_config = test_scenario::take_shared<AdapterConfig>(&scenario);
    let mut mock_share_vault = test_scenario::take_shared<MockVault<OCT, YOCT>>(&scenario);
    let mut sroct_minter = test_scenario::take_shared<SaverMinter<SROCT>>(&scenario);

    // init user info
    init_saver_user_info<YOCT, SROCT>(&sroct_minter, &mut scenario, User1);
    let mut user1_saver_info = test_scenario::take_from_address<SaverUserInfo<YOCT, SROCT>>(&scenario, User1);
    print(&b"User1 saver info: ");
    print(&user1_saver_info);

    init_saver_user_info<YOCT, SROCT>(&sroct_minter, &mut scenario, User2);
    let mut user2_saver_info = test_scenario::take_from_address<SaverUserInfo<YOCT, SROCT>>(&scenario, User2);
    print(&b"User2 saver info: ");
    print(&user2_saver_info);


    // Case 1: deposit using yield token

    test_scenario::next_tx(&mut scenario, User1);
    let amount_to_deposit: u64 = 10000000;
    let yoct_to_deposit = mint_coin<YOCT>(amount_to_deposit, &mut scenario);

    mock_adapter::deposit(
        &adapter_config,
        yoct_to_deposit,
        &mut user1_saver_info,
        &mut saver_vault_reserve,
        &mut sroct_minter,
        &clock,
        &mock_share_vault
    );

    test_scenario::next_tx(&mut scenario, User1);

    print(&b"user info after deposit".to_string());
    print(&user1_saver_info);

    print(&b"vault reserve after deposit".to_string());
    print(&saver_vault_reserve);

    print(&b"minter after deposit".to_string());
    print(&sroct_minter);

    assert!(saver::get_user_info_shares_balance(&user1_saver_info) == amount_to_deposit as u128, AssignWrong);
    assert!(saver::yt_config_active_balance<YOCT, SROCT>(&sroct_minter) == amount_to_deposit as u128, 0);
   
    // Case 2: deposit using underlying token
    test_scenario::next_tx(&mut scenario, User1);
    
    let amount_to_deposit: u64 = 30000000;
    let coin_to_deposit = mint_coin<OCT>(
        amount_to_deposit,
        &mut scenario
    );

    mock_adapter::deposit_underlying(
        &uts,
        &adapter_config,
        coin_to_deposit,
        &mut user1_saver_info,
        &mut saver_vault_reserve,
        &mut sroct_minter,
        &clock,
        &mut mock_share_vault,
        test_scenario::ctx(&mut scenario)
    );
    test_scenario::next_tx(&mut scenario, User1);

    print(&b"user1 balance info after deposit underlying".to_string());
    print(&user1_saver_info);

    // Case 3: deposit after yield token emiss yield

    test_scenario::next_tx(&mut scenario, User2);
    
    // increase timestamp_ms
    clock::increment_for_testing(&mut clock, 1000);

    // donate some token into share vault to shift the price
    let coin_to_donate = mint_coin<OCT>(1000000, &mut scenario);
    mock::donate(
        &mut mock_share_vault,
        coin_to_donate
    );

    let current_price = mock::price(&mock_share_vault);
    print(&b"Current price: ".to_string());
    print(&current_price);
    let (_, total_deposited, total_supply) = mock::read_vault_info(&mock_share_vault);
    print(&total_supply);
    print(&total_deposited);
    assert!(current_price == total_deposited * 10u128.pow(9) / total_supply, 0);

    // user2 deposit yoct

    let amount: u64 = 2000000;
    let current_total_shares = saver::yt_config_total_shares<YOCT, SROCT>(&sroct_minter);
    let current_active_balance = saver::yt_config_active_balance<YOCT, SROCT>(&sroct_minter);
    let current_expected_value = saver::yt_config_expected_value<YOCT, SROCT>(&sroct_minter);
    let current_value = (current_active_balance as u128) * current_price / 10u128.pow(9);
    let current_harvestable = 10u128.pow(9) * (current_value - current_expected_value) / current_price;
    print(&current_active_balance);
    print(&current_expected_value);
    print(&current_value);
    print(&current_harvestable);
    let expected_share_to_receive =  current_total_shares * (amount as u128) / (current_active_balance - current_harvestable);
    let yoct_to_deposit = mint_coin<YOCT>(amount, &mut scenario);
    mock_adapter::deposit(
        &adapter_config,
        yoct_to_deposit,
        &mut user2_saver_info,
        &mut saver_vault_reserve,
        &mut sroct_minter,
        &clock,
        &mock_share_vault
    );
    test_scenario::next_tx(&mut scenario, User2);

    // check user2 deposit info
    print(&b"User2 deposit info after deposit: ".to_string());
    print(&user2_saver_info);
    assert!(expected_share_to_receive == saver::get_user_info_shares_balance(&user2_saver_info), 0);
    
    print(&b"Current harvestable: ".to_string());
    let current_harvestable_balance = saver::yt_config_harvestable_balance<YOCT, SROCT>(&sroct_minter);
    print(&current_harvestable_balance);
    assert!(current_harvestable_balance == current_harvestable, 0);
    
    // return all shared objects 
    test_scenario::return_shared(saver_config);
    test_scenario::return_shared(limiter_config);
    test_scenario::return_shared(sroct_minter);
    test_scenario::return_shared(adapter_config);
    test_scenario::return_shared(mock_share_vault);
    test_scenario::return_shared(saver_vault_reserve);
    test_scenario::return_shared(uts);

    // return to address
    test_scenario::return_to_address(User1, user1_saver_info);
    test_scenario::return_to_address(User2, user2_saver_info);

    test_scenario::next_tx(&mut scenario, Admin);

    test_scenario::end(scenario);
    clock::destroy_for_testing(clock);
}

#[test, expected_failure(abort_code = 4)]
fun test_deposit_fail() {
    // init clock and scenario
    let mut scenario = test_scenario::begin(Admin);
    let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1000);
    prepare_state(&clock, &mut scenario);

    // take all shared objects
    let uts = test_scenario::take_shared<UnderlyingToken<OCT, YOCT, SROCT>>(&scenario);
    let mut saver_vault_reserve = test_scenario::take_shared<SaverReserve<YOCT>>(&scenario);
    let saver_config = test_scenario::take_shared<SaverConfig>(&scenario);
    let limiter_config = test_scenario::take_shared<LimiterConfig>(&scenario);
    let adapter_config = test_scenario::take_shared<AdapterConfig>(&scenario);
    let mut mock_share_vault = test_scenario::take_shared<MockVault<OCT, YOCT>>(&scenario);
    let mut sroct_minter = test_scenario::take_shared<SaverMinter<SROCT>>(&scenario);

    // init user info
    init_saver_user_info<YOCT, SROCT>(&sroct_minter, &mut scenario, User1);
    let mut user1_saver_info = test_scenario::take_from_address<SaverUserInfo<YOCT, SROCT>>(&scenario, User1);
    print(&b"User1 saver info: ");
    print(&user1_saver_info);

    init_saver_user_info<YOCT, SROCT>(&sroct_minter, &mut scenario, User2);
    let mut user2_saver_info = test_scenario::take_from_address<SaverUserInfo<YOCT, SROCT>>(&scenario, User2);
    print(&b"User2 saver info: ");
    print(&user2_saver_info);

    // deposit 1e16 yoct
    test_scenario::next_tx(&mut scenario, User1);
    let amount = 10000000000000000;
    let coin_to_deposit = mint_coin<YOCT>(amount, &mut scenario);
    mock_adapter::deposit(
        &adapter_config,
        coin_to_deposit,
        &mut user1_saver_info,
        &mut saver_vault_reserve,
        &mut sroct_minter,
        &clock,
        &mock_share_vault
    );
    
    // return all shared objects 
    test_scenario::return_shared(saver_config);
    test_scenario::return_shared(limiter_config);
    test_scenario::return_shared(sroct_minter);
    test_scenario::return_shared(adapter_config);
    test_scenario::return_shared(mock_share_vault);
    test_scenario::return_shared(saver_vault_reserve);
    test_scenario::return_shared(uts);

    // return to address
    test_scenario::return_to_address(User1, user1_saver_info);
    test_scenario::return_to_address(User2, user2_saver_info);

    test_scenario::next_tx(&mut scenario, Admin);

    test_scenario::end(scenario);
    clock::destroy_for_testing(clock);
}

#[test]
fun test_withdraw() {
    // init clock and scenario
    let mut scenario = test_scenario::begin(Admin);
    let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1000);
    prepare_state(&clock, &mut scenario);

    // take all shared objects
    let uts = test_scenario::take_shared<UnderlyingToken<OCT, YOCT, SROCT>>(&scenario);
    let mut saver_vault_reserve = test_scenario::take_shared<SaverReserve<YOCT>>(&scenario);
    let saver_config = test_scenario::take_shared<SaverConfig>(&scenario);
    let limiter_config = test_scenario::take_shared<LimiterConfig>(&scenario);
    let adapter_config = test_scenario::take_shared<AdapterConfig>(&scenario);
    let mut mock_share_vault = test_scenario::take_shared<MockVault<OCT, YOCT>>(&scenario);
    let mut sroct_minter = test_scenario::take_shared<SaverMinter<SROCT>>(&scenario);

    // init user info
    init_saver_user_info<YOCT, SROCT>(&sroct_minter, &mut scenario, User1);
    let mut user1_saver_info = test_scenario::take_from_address<SaverUserInfo<YOCT, SROCT>>(&scenario, User1);
    print(&b"User1 saver info: ");
    print(&user1_saver_info);

    init_saver_user_info<YOCT, SROCT>(&sroct_minter, &mut scenario, User2);
    let mut user2_saver_info = test_scenario::take_from_address<SaverUserInfo<YOCT, SROCT>>(&scenario, User2);
    print(&b"User2 saver info: ");
    print(&user2_saver_info);

    // Setting case

    // 1. User 1 deposit 1000000000 YOCT 
    test_scenario::next_tx(&mut scenario, User1);
    let amount_to_deposit = 1000000000;
    let coin_to_deposit = mint_coin<YOCT>(amount_to_deposit, &mut scenario);
    mock_adapter::deposit(
        &adapter_config,
        coin_to_deposit,
        &mut user1_saver_info,
        &mut saver_vault_reserve,
        &mut sroct_minter,
        &clock,
        &mock_share_vault
    );

    // 2. donate some token to increase the price 
    test_scenario::next_tx(&mut scenario, Admin);
    clock::increment_for_testing(&mut clock, 1000);
    let amount_to_donate: u64 = 50000000;
    let coin_to_donate = mint_coin<OCT>(amount_to_donate, &mut scenario);
    mock::donate(
        &mut mock_share_vault,
        coin_to_donate
    );

    // 3. User 2 deposit oct
    test_scenario::next_tx(&mut scenario, User2);
    clock::increment_for_testing(&mut clock, 1000);
    let amount_to_deposit: u64 = 300000000;
    let coin_to_deposit = mint_coin<OCT>(amount_to_deposit, &mut scenario);
    mock_adapter::deposit_underlying(
        &uts,
        &adapter_config,
        coin_to_deposit,
        &mut user2_saver_info,
        &mut saver_vault_reserve,
        &mut sroct_minter,
        &clock,
        &mut mock_share_vault,
        test_scenario::ctx(&mut scenario)
    );

    // 4. User 1 withdraw
    // all information needed
    let current_price = mock::price(&mock_share_vault);
    let current_total_shares = saver::yt_config_total_shares<YOCT, SROCT>(&sroct_minter);
    let current_active_balance = saver::yt_config_active_balance<YOCT, SROCT>(&sroct_minter);
    let current_expected_value = saver::yt_config_expected_value<YOCT, SROCT>(&sroct_minter);
    let current_value = (current_active_balance as u128) * current_price / 10u128.pow(9);
    let current_harvestable = 10u128.pow(9) * (current_value - current_expected_value) / current_price;
    
    test_scenario::next_tx(&mut scenario, User1);
    let share_to_redeem: u128 = 50000000;
    let expected_yoct_to_receive = share_to_redeem * (current_active_balance - current_harvestable) / current_total_shares;
    mock_adapter::withdraw(
        &uts,
        &adapter_config,
        &mut saver_vault_reserve,
        &mut user1_saver_info,
        &mut sroct_minter,
        &clock,
        share_to_redeem as u64,
        User1,
        &mock_share_vault,
        test_scenario::ctx(&mut scenario)
    );
    test_scenario::next_tx(&mut scenario, User2);

    // check token receive
    let coin_receive = test_scenario::take_from_address<Coin<YOCT>>(&scenario, User1);
    assert!(coin::value(&coin_receive) == expected_yoct_to_receive as u64, 0);
    coin::burn_for_testing(coin_receive);

    // 5. User 2 witdraw underlying
    test_scenario::next_tx(&mut scenario, User2);
    let current_price = mock::price(&mock_share_vault);
    let current_total_shares = saver::yt_config_total_shares<YOCT, SROCT>(&sroct_minter);
    let current_active_balance = saver::yt_config_active_balance<YOCT, SROCT>(&sroct_minter);
    let current_expected_value = saver::yt_config_expected_value<YOCT, SROCT>(&sroct_minter);
    let current_value = (current_active_balance as u128) * current_price / 10u128.pow(9);
    let current_harvestable = 10u128.pow(9) * (current_value - current_expected_value) / current_price;
    
    let (_, total_deposited, total_supply) = mock::read_vault_info(&mock_share_vault);
    let share_to_redeem: u128 = 3000000;
    let expected_yoct_to_receive = share_to_redeem * (current_active_balance - current_harvestable) / current_total_shares;
    let expected_oct_to_receive = expected_yoct_to_receive * total_deposited / total_supply;
    mock_adapter::withdraw_underlying(
        &uts,
        &adapter_config,
        &mut saver_vault_reserve,
        &mut user2_saver_info,
        &mut sroct_minter,
        &clock,
        share_to_redeem as u64,
        User2,
        &mut mock_share_vault,
        test_scenario::ctx(&mut scenario)
    );
    test_scenario::next_tx(&mut scenario, User2);
    let coin_receive = test_scenario::take_from_address<Coin<OCT>>(&scenario, User2);
    assert!(coin::value(&coin_receive) == expected_oct_to_receive as u64, 0);
    coin::burn_for_testing(coin_receive);

    // return all shared objects 
    test_scenario::return_shared(saver_config);
    test_scenario::return_shared(limiter_config);
    test_scenario::return_shared(sroct_minter);
    test_scenario::return_shared(adapter_config);
    test_scenario::return_shared(mock_share_vault);
    test_scenario::return_shared(saver_vault_reserve);
    test_scenario::return_shared(uts);

    // return to address
    test_scenario::return_to_address(User1, user1_saver_info);
    test_scenario::return_to_address(User2, user2_saver_info);

    test_scenario::next_tx(&mut scenario, Admin);

    test_scenario::end(scenario);
    clock::destroy_for_testing(clock);
}

#[test]
fun test_mint() {
    // init clock and scenario
    let mut scenario = test_scenario::begin(Admin);
    let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1000);
    prepare_state(&clock, &mut scenario);

    // take all shared objects
    let rd_config = test_scenario::take_shared<RdConfig>(&scenario);
    let mut rd_vault = test_scenario::take_shared<RdVault<OCT, SROCT>>(&scenario);
    let uts = test_scenario::take_shared<UnderlyingToken<OCT, YOCT, SROCT>>(&scenario);
    let mut saver_vault_reserve = test_scenario::take_shared<SaverReserve<YOCT>>(&scenario);
    let saver_config = test_scenario::take_shared<SaverConfig>(&scenario);
    let limiter_config = test_scenario::take_shared<LimiterConfig>(&scenario);
    let adapter_config = test_scenario::take_shared<AdapterConfig>(&scenario);
    let mut mock_share_vault = test_scenario::take_shared<MockVault<OCT, YOCT>>(&scenario);
    let mut sroct_minter = test_scenario::take_shared<SaverMinter<SROCT>>(&scenario);

    // init user info
    init_saver_user_info<YOCT, SROCT>(&sroct_minter, &mut scenario, User1);
    let mut user1_saver_info = test_scenario::take_from_address<SaverUserInfo<YOCT, SROCT>>(&scenario, User1);
    print(&b"User1 saver info: ");
    print(&user1_saver_info);

    init_saver_user_info<YOCT, SROCT>(&sroct_minter, &mut scenario, User2);
    let mut user2_saver_info = test_scenario::take_from_address<SaverUserInfo<YOCT, SROCT>>(&scenario, User2);
    print(&b"User2 saver info: ");
    print(&user2_saver_info);

    // Setting case

    // 1. User 1 deposit 1000000000 YOCT 
    test_scenario::next_tx(&mut scenario, User1);
    let amount_to_deposit = 1000000000;
    let coin_to_deposit = mint_coin<OCT>(amount_to_deposit, &mut scenario);
    let coin_to_deposit = mock::deposit(&mut mock_share_vault, coin_to_deposit, test_scenario::ctx(&mut scenario));
    mock_adapter::deposit(
        &adapter_config,
        coin_to_deposit,
        &mut user1_saver_info,
        &mut saver_vault_reserve,
        &mut sroct_minter,
        &clock,
        &mock_share_vault
    );

    // 4. User 1 mint sroct
    test_scenario::next_tx(&mut scenario, User1);
    let amount_to_mint = 2000000;
    mock_adapter::mint(
        &uts,
        &adapter_config,
        &mut user1_saver_info,
        &mut sroct_minter,
        &clock,
        amount_to_mint as u64,
        User1,
        &mock_share_vault,
        test_scenario::ctx(&mut scenario)
    );
    test_scenario::next_tx(&mut scenario, User2);
    let coin_was_minted = test_scenario::take_from_address<Coin<SROCT>>(&scenario, User1);
    assert!(coin::value(&coin_was_minted) == amount_to_mint as u64, 0);
    assert!(saver::get_user_info_debt(&user1_saver_info) == amount_to_mint as u128, 0);
    coin::burn_for_testing(coin_was_minted);

    // 2. User 2 mint when having profit
    test_scenario::next_tx(&mut scenario, User2);
    // 2.1 deposit some collateral
    let amount_to_deposit: u64 = 6000000;
    let coin_to_deposit = mint_coin<OCT>(amount_to_deposit, &mut scenario);
        mock_adapter::deposit_underlying(
            &uts,
        &adapter_config,
        coin_to_deposit,
        &mut user2_saver_info,
        &mut saver_vault_reserve,
        &mut sroct_minter,
        &clock,
        &mut mock_share_vault,
        test_scenario::ctx(&mut scenario)
    );

    // 2.2 donate to shift the price up
    test_scenario::next_tx(&mut scenario, User2);
    clock::increment_for_testing(&mut clock, 10000);
    let coin_to_donate = mint_coin<OCT>(1000000, &mut scenario);
    mock::donate(
        &mut mock_share_vault,
        coin_to_donate
    );
    let current_price = mock::price(&mock_share_vault);
    test_scenario::next_tx(&mut scenario, User2);
    mock_adapter::poke(
        &adapter_config,
        &mut sroct_minter,
        &mut user2_saver_info,
        &clock,
        &mock_share_vault
    );
    test_scenario::next_tx(&mut scenario, User2);
    let (_, total_deposited, total_supply) = mock::read_vault_info(&mock_share_vault);
    print(&total_deposited);
    
    print(&b"Current info".to_string());
    let current_harvestable_balance = saver::yt_config_harvestable_balance<YOCT, SROCT>(&sroct_minter);
    print(&current_harvestable_balance);

    let amount_oct_harvest = current_harvestable_balance * current_price / 10u128.pow(9);
    print(&amount_oct_harvest);

    assert!(saver::yt_config_pending_credit<YOCT, SROCT>(&sroct_minter) == 0, 0);
    assert!(saver::yt_config_distributed_credit<YOCT, SROCT>(&sroct_minter) == 0, 0);

    // 2.3 harvest
    test_scenario::next_tx(&mut scenario, Keeper);
    let keeper_cap = test_scenario::take_from_address<saver::KeeperCap>(&scenario, Keeper);
    mock_adapter::harvest(
        &adapter_config,
        &uts,
        &keeper_cap,
        &mut sroct_minter,
        &mut saver_vault_reserve,
        &clock,
        0,
        &rd_config,
        &mut rd_vault,
        &mut mock_share_vault,
        test_scenario::ctx(&mut scenario)
    );
    
    clock::increment_for_testing(&mut clock, 100000);
    test_scenario::next_tx(&mut scenario, User2);
    
    mock_adapter::poke(
        &adapter_config,
        &mut sroct_minter,
        &mut user2_saver_info,
        &clock,
        &mock_share_vault
    );
    test_scenario::next_tx(&mut scenario, User2);
    
    print(&saver::get_user_info_profit(&user2_saver_info));
    print(&saver::yt_config_pending_credit<YOCT, SROCT>(&sroct_minter));
    print(&saver::yt_config_distributed_credit<YOCT, SROCT>(&sroct_minter));

    let user2_profit = saver::get_user_info_profit(&user2_saver_info) as u64;
    mock_adapter::mint(
        &uts,
        &adapter_config,
        &mut user2_saver_info,
        &mut sroct_minter,
        &clock,
        user2_profit + 1000u64,
        User2,
        &mock_share_vault,
        test_scenario::ctx(&mut scenario)
    );
    test_scenario::next_tx(&mut scenario, User2);
    let user2_debt = saver::get_user_info_debt(&user2_saver_info);
    print(&user2_debt);
    assert!(user2_debt == 1000, 0);

    // return all shared objects 
    test_scenario::return_shared(saver_config);
    test_scenario::return_shared(limiter_config);
    test_scenario::return_shared(sroct_minter);
    test_scenario::return_shared(adapter_config);
    test_scenario::return_shared(mock_share_vault);
    test_scenario::return_shared(saver_vault_reserve);
    test_scenario::return_shared(uts);
    test_scenario::return_shared(rd_vault);
    test_scenario::return_shared(rd_config);

    // return to address
    test_scenario::return_to_address(User1, user1_saver_info);
    test_scenario::return_to_address(User2, user2_saver_info);
    test_scenario::return_to_address(Keeper, keeper_cap);

    test_scenario::next_tx(&mut scenario, Admin);

    test_scenario::end(scenario);
    clock::destroy_for_testing(clock);
}

#[test]
public fun test_burn() {
    // init clock and scenario
    let mut scenario = test_scenario::begin(Admin);
    let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1000);
    prepare_state(&clock, &mut scenario);

    // take all shared objects
    let rd_config = test_scenario::take_shared<RdConfig>(&scenario);
    let mut rd_vault = test_scenario::take_shared<RdVault<OCT, SROCT>>(&scenario);
    let uts = test_scenario::take_shared<UnderlyingToken<OCT, YOCT, SROCT>>(&scenario);
    let mut saver_vault_reserve = test_scenario::take_shared<SaverReserve<YOCT>>(&scenario);
    let saver_config = test_scenario::take_shared<SaverConfig>(&scenario);
    let limiter_config = test_scenario::take_shared<LimiterConfig>(&scenario);
    let adapter_config = test_scenario::take_shared<AdapterConfig>(&scenario);
    let mut mock_share_vault = test_scenario::take_shared<MockVault<OCT, YOCT>>(&scenario);
    let mut sroct_minter = test_scenario::take_shared<SaverMinter<SROCT>>(&scenario);
    let keeper_cap = test_scenario::take_from_address<saver::KeeperCap>(&scenario, Keeper);

    // init user info
    init_saver_user_info<YOCT, SROCT>(&sroct_minter, &mut scenario, User1);
    let mut user1_saver_info = test_scenario::take_from_address<SaverUserInfo<YOCT, SROCT>>(&scenario, User1);
    print(&b"User1 saver info: ");
    print(&user1_saver_info);

    init_saver_user_info<YOCT, SROCT>(&sroct_minter, &mut scenario, User2);
    let mut user2_saver_info = test_scenario::take_from_address<SaverUserInfo<YOCT, SROCT>>(&scenario, User2);
    print(&b"User2 saver info: ");
    print(&user2_saver_info);

    // Setting case

    // 1. User 1 deposit 1000000000 OCT 
    test_scenario::next_tx(&mut scenario, User1);
    let amount_to_deposit = 1000000000;
    let coin_to_deposit = mint_coin<OCT>(amount_to_deposit, &mut scenario);
    let coin_to_deposit = mock::deposit(&mut mock_share_vault, coin_to_deposit, test_scenario::ctx(&mut scenario));
    mock_adapter::deposit(
        &adapter_config,
        coin_to_deposit,
        &mut user1_saver_info,
        &mut saver_vault_reserve,
        &mut sroct_minter,
        &clock,
        &mock_share_vault
    );

    // 2. User 1 mint sroct
    test_scenario::next_tx(&mut scenario, User1);
    let amount_to_mint = 2000000;
    mock_adapter::mint(
        &uts,
        &adapter_config,
        &mut user1_saver_info,
        &mut sroct_minter,
        &clock,
        amount_to_mint as u64,
        User1,
        &mock_share_vault,
        test_scenario::ctx(&mut scenario)
    );
    test_scenario::next_tx(&mut scenario, User1);
    let coin_was_minted = test_scenario::take_from_address<Coin<SROCT>>(&scenario, User1);
    assert!(coin::value(&coin_was_minted) == amount_to_mint as u64, 0);
    assert!(saver::get_user_info_debt(&user1_saver_info) == amount_to_mint as u128, 0);
    
    // 2.1. User 1 burn full sroct when their is no profit
    mock_adapter::burn(
        &adapter_config,
        &mut user1_saver_info,
        coin_was_minted,
        &mut sroct_minter,
        &clock,
        test_scenario::ctx(&mut scenario)
    );

    test_scenario::next_tx(&mut scenario, User1);
    assert!(saver::get_user_info_debt(&user1_saver_info) == 0, 0);

    // 2.2. Burn when user has profit
    test_scenario::next_tx(&mut scenario, User1);
    let amount_to_mint = 2000000;
    mock_adapter::mint(
        &uts,
        &adapter_config,
        &mut user1_saver_info,
        &mut sroct_minter,
        &clock,
        amount_to_mint as u64,
        User1,
        &mock_share_vault,
        test_scenario::ctx(&mut scenario)
    );
    test_scenario::next_tx(&mut scenario, User1);

    // 2.2.1. donate some oct to shift the price
    clock::increment_for_testing(&mut clock, 10000);
    let coin_to_donate = mint_coin<OCT>(1000000, &mut scenario);
    mock::donate(
        &mut mock_share_vault,
        coin_to_donate
    );

    test_scenario::next_tx(&mut scenario, User1);

    mock_adapter::poke(
        &adapter_config,
        &mut sroct_minter,
        &mut user1_saver_info,
        &clock,
        &mock_share_vault
    );
    test_scenario::next_tx(&mut scenario, User1);
    print(&saver::yt_config_harvestable_balance<YOCT, SROCT>(&sroct_minter));
    // 2.2.2 harvest
    test_scenario::next_tx(&mut scenario, Keeper);
    //let keeper_cap = test_scenario::take_from_address<saver::KeeperCap>(&scenario, Keeper);
    mock_adapter::harvest(
        &adapter_config,
        &uts,
        &keeper_cap,
        &mut sroct_minter,
        &mut saver_vault_reserve,
        &clock,
        1,
        &rd_config,
        &mut rd_vault,
        &mut mock_share_vault,
        test_scenario::ctx(&mut scenario)
    );
    test_scenario::next_tx(&mut scenario, User1);
    clock::increment_for_testing(&mut clock, 10000);
    test_scenario::next_tx(&mut scenario, User1);

    mock_adapter::poke(
        &adapter_config,
        &mut sroct_minter,
        &mut user1_saver_info,
        &clock,
        &mock_share_vault
    );
    test_scenario::next_tx(&mut scenario, User1);

    print(&saver::get_user_info_debt(&user1_saver_info));
    let user1_debt = saver::get_user_info_debt(&user1_saver_info) as u64;
    assert!(user1_debt < 2000000, 0);

    // 2.2.3. Over repay, expect to receive lefover sroct
    test_scenario::next_tx(&mut scenario, User1);
    let sroct_to_repay = test_scenario::take_from_address<Coin<SROCT>>(&scenario, User1);
    mock_adapter::burn(
        &adapter_config,
        &mut user1_saver_info,
        sroct_to_repay,
        &mut sroct_minter,
        &clock,
        test_scenario::ctx(&mut scenario)
    );

    test_scenario::next_tx(&mut scenario, User1);
    let sroct_left = test_scenario::take_from_address<Coin<SROCT>>(&scenario, User1);
    assert!(coin::value(&sroct_left) == 2000000 - user1_debt, 0);
    print(&coin::value(&sroct_left));
    coin::burn_for_testing(sroct_left);

    // return all shared objects 
    test_scenario::return_shared(saver_config);
    test_scenario::return_shared(limiter_config);
    test_scenario::return_shared(sroct_minter);
    test_scenario::return_shared(adapter_config);
    test_scenario::return_shared(mock_share_vault);
    test_scenario::return_shared(saver_vault_reserve);
    test_scenario::return_shared(uts);
    test_scenario::return_shared(rd_vault);
    test_scenario::return_shared(rd_config);

    // return to address
    test_scenario::return_to_address(User1, user1_saver_info);
    test_scenario::return_to_address(User2, user2_saver_info);
    test_scenario::return_to_address(Keeper, keeper_cap);

    test_scenario::next_tx(&mut scenario, Admin);

    test_scenario::end(scenario);
    clock::destroy_for_testing(clock);
}

#[test]
fun test_liquidation() {
    // init clock and scenario
    let mut scenario = test_scenario::begin(Admin);
    let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1000);
    prepare_state(&clock, &mut scenario);

    // take all shared objects
    let rd_config = test_scenario::take_shared<RdConfig>(&scenario);
    let mut rd_vault = test_scenario::take_shared<RdVault<OCT, SROCT>>(&scenario);
    let mut uts = test_scenario::take_shared<UnderlyingToken<OCT, YOCT, SROCT>>(&scenario);
    let mut saver_vault_reserve = test_scenario::take_shared<SaverReserve<YOCT>>(&scenario);
    let saver_config = test_scenario::take_shared<SaverConfig>(&scenario);
    let limiter_config = test_scenario::take_shared<LimiterConfig>(&scenario);
    let adapter_config = test_scenario::take_shared<AdapterConfig>(&scenario);
    let mut mock_share_vault = test_scenario::take_shared<MockVault<OCT, YOCT>>(&scenario);
    let mut sroct_minter = test_scenario::take_shared<SaverMinter<SROCT>>(&scenario);
    let keeper_cap = test_scenario::take_from_address<saver::KeeperCap>(&scenario, Keeper);
    let mut liquidation_limiter = test_scenario::take_shared<LiquidateLimiter<OCT, YOCT, SROCT>>(&scenario);

    // init user info
    init_saver_user_info<YOCT, SROCT>(&sroct_minter, &mut scenario, User1);
    let mut user1_saver_info = test_scenario::take_from_address<SaverUserInfo<YOCT, SROCT>>(&scenario, User1);
    print(&b"User1 saver info: ");
    print(&user1_saver_info);

    init_saver_user_info<YOCT, SROCT>(&sroct_minter, &mut scenario, User2);
    let mut user2_saver_info = test_scenario::take_from_address<SaverUserInfo<YOCT, SROCT>>(&scenario, User2);
    print(&b"User2 saver info: ");
    print(&user2_saver_info);

    // Setting case

    // 1. User 1 deposit 1000000000 OCT 
    test_scenario::next_tx(&mut scenario, User1);
    let amount_to_deposit = 1000000000;
    let coin_to_deposit = mint_coin<OCT>(amount_to_deposit, &mut scenario);
    let coin_to_deposit = mock::deposit(&mut mock_share_vault, coin_to_deposit, test_scenario::ctx(&mut scenario));
    mock_adapter::deposit(
        &adapter_config,
        coin_to_deposit,
        &mut user1_saver_info,
        &mut saver_vault_reserve,
        &mut sroct_minter,
        &clock,
        &mock_share_vault
    );

    // 2. User 1 mint sroct
    test_scenario::next_tx(&mut scenario, User1);
    let amount_to_mint = 2000000;
    mock_adapter::mint(
        &uts,
        &adapter_config,
        &mut user1_saver_info,
        &mut sroct_minter,
        &clock,
        amount_to_mint as u64,
        User1,
        &mock_share_vault,
        test_scenario::ctx(&mut scenario)
    );
    test_scenario::next_tx(&mut scenario, User1);
    let coin_was_minted = test_scenario::take_from_address<Coin<SROCT>>(&scenario, User1);
    assert!(coin::value(&coin_was_minted) == amount_to_mint as u64, 0);
    assert!(saver::get_user_info_debt(&user1_saver_info) == amount_to_mint as u128, 0);
    coin::burn_for_testing(coin_was_minted);
    let user_current_share_balance = saver::get_user_info_shares_balance(&user1_saver_info);
    print(&user_current_share_balance);
    let share_to_liquidate: u128 = 100000;
    mock_adapter::liquidate(
        &adapter_config,
        &mut uts,
        &mut user1_saver_info,
        &mut sroct_minter,
        &mut saver_vault_reserve,
        &clock,
        share_to_liquidate,
        &mut liquidation_limiter,
        0,
        &mut mock_share_vault,
        &rd_config,
        &mut rd_vault,
        test_scenario::ctx(&mut scenario)
    );
    assert!(saver::get_user_info_shares_balance(&user1_saver_info) < user_current_share_balance, 0);
    assert!(saver::get_user_info_debt(&user1_saver_info) < 2000000, 0);

    // return all shared objects 
    test_scenario::return_shared(saver_config);
    test_scenario::return_shared(limiter_config);
    test_scenario::return_shared(sroct_minter);
    test_scenario::return_shared(adapter_config);
    test_scenario::return_shared(mock_share_vault);
    test_scenario::return_shared(saver_vault_reserve);
    test_scenario::return_shared(uts);
    test_scenario::return_shared(rd_vault);
    test_scenario::return_shared(rd_config);
    test_scenario::return_shared(liquidation_limiter);

    // return to address
    test_scenario::return_to_address(User1, user1_saver_info);
    test_scenario::return_to_address(User2, user2_saver_info);
    test_scenario::return_to_address(Keeper, keeper_cap);

    test_scenario::next_tx(&mut scenario, Admin);

    test_scenario::end(scenario);
    clock::destroy_for_testing(clock);
}

#[test]
fun test_repay() {
        // init clock and scenario
    let mut scenario = test_scenario::begin(Admin);
    let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1000);
    prepare_state(&clock, &mut scenario);

    // take all shared objects
    let rd_config = test_scenario::take_shared<RdConfig>(&scenario);
    let mut rd_vault = test_scenario::take_shared<RdVault<OCT, SROCT>>(&scenario);
    let mut uts = test_scenario::take_shared<UnderlyingToken<OCT, YOCT, SROCT>>(&scenario);
    let mut saver_vault_reserve = test_scenario::take_shared<SaverReserve<YOCT>>(&scenario);
    let saver_config = test_scenario::take_shared<SaverConfig>(&scenario);
    let limiter_config = test_scenario::take_shared<LimiterConfig>(&scenario);
    let adapter_config = test_scenario::take_shared<AdapterConfig>(&scenario);
    let mut mock_share_vault = test_scenario::take_shared<MockVault<OCT, YOCT>>(&scenario);
    let mut sroct_minter = test_scenario::take_shared<SaverMinter<SROCT>>(&scenario);
    let keeper_cap = test_scenario::take_from_address<saver::KeeperCap>(&scenario, Keeper);
    let mut liquidation_limiter = test_scenario::take_shared<LiquidateLimiter<OCT, YOCT, SROCT>>(&scenario);

    // init user info
    init_saver_user_info<YOCT, SROCT>(&sroct_minter, &mut scenario, User1);
    let mut user1_saver_info = test_scenario::take_from_address<SaverUserInfo<YOCT, SROCT>>(&scenario, User1);
    print(&b"User1 saver info: ");
    print(&user1_saver_info);

    init_saver_user_info<YOCT, SROCT>(&sroct_minter, &mut scenario, User2);
    let mut user2_saver_info = test_scenario::take_from_address<SaverUserInfo<YOCT, SROCT>>(&scenario, User2);
    print(&b"User2 saver info: ");
    print(&user2_saver_info);

    // Setting case

    // 1. User 1 deposit 1000000000 OCT 
    test_scenario::next_tx(&mut scenario, User1);
    let amount_to_deposit = 1000000000;
    let coin_to_deposit = mint_coin<OCT>(amount_to_deposit, &mut scenario);
    let coin_to_deposit = mock::deposit(&mut mock_share_vault, coin_to_deposit, test_scenario::ctx(&mut scenario));
    mock_adapter::deposit(
        &adapter_config,
        coin_to_deposit,
        &mut user1_saver_info,
        &mut saver_vault_reserve,
        &mut sroct_minter,
        &clock,
        &mock_share_vault
    );

    // 2. User 1 mint sroct
    test_scenario::next_tx(&mut scenario, User1);
    let amount_to_mint = 2000000;
    mock_adapter::mint(
        &uts,
        &adapter_config,
        &mut user1_saver_info,
        &mut sroct_minter,
        &clock,
        amount_to_mint as u64,
        User1,
        &mock_share_vault,
        test_scenario::ctx(&mut scenario)
    );
    test_scenario::next_tx(&mut scenario, User1);
    let coin_was_minted = test_scenario::take_from_address<Coin<SROCT>>(&scenario, User1);
    assert!(coin::value(&coin_was_minted) == amount_to_mint as u64, 0);
    assert!(saver::get_user_info_debt(&user1_saver_info) == amount_to_mint as u128, 0);
    coin::burn_for_testing(coin_was_minted);

    let coin_to_repay = mint_coin<OCT>(1500000, &mut scenario);
    mock_adapter::repay(
        &adapter_config,
        &mut uts,
        coin_to_repay,
        &mut user1_saver_info,
        &mut sroct_minter,
        &clock,
        &rd_config,
        &mut rd_vault,
        &mock_share_vault,
        test_scenario::ctx(&mut scenario)
    );
    test_scenario::next_tx(&mut scenario, User1);
    let current_debt = saver::get_user_info_debt(&user1_saver_info);
    print(&current_debt);
    assert!(current_debt == 500000, 0);

    let rd_current_ut_balance = redeem_pool::get_vault_ut_balance(&rd_vault);
    let rd_current_total_buffer = redeem_pool::get_vault_total_buffer(&rd_vault);
    assert!(rd_current_ut_balance as u128 == rd_current_total_buffer, 0);
    assert!(rd_current_ut_balance == 1500000, 0);

    // return all shared objects 
    test_scenario::return_shared(saver_config);
    test_scenario::return_shared(limiter_config);
    test_scenario::return_shared(sroct_minter);
    test_scenario::return_shared(adapter_config);
    test_scenario::return_shared(mock_share_vault);
    test_scenario::return_shared(saver_vault_reserve);
    test_scenario::return_shared(uts);
    test_scenario::return_shared(rd_vault);
    test_scenario::return_shared(rd_config);
    test_scenario::return_shared(liquidation_limiter);

    // return to address
    test_scenario::return_to_address(User1, user1_saver_info);
    test_scenario::return_to_address(User2, user2_saver_info);
    test_scenario::return_to_address(Keeper, keeper_cap);

    test_scenario::next_tx(&mut scenario, Admin);

    test_scenario::end(scenario);
    clock::destroy_for_testing(clock);
}

#[test]
fun test_harvest() {
    // init clock and scenario
    let mut scenario = test_scenario::begin(Admin);
    let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1000);
    prepare_state(&clock, &mut scenario);

    // take all shared objects
    let rd_config = test_scenario::take_shared<RdConfig>(&scenario);
    let mut rd_vault = test_scenario::take_shared<RdVault<OCT, SROCT>>(&scenario);
    let mut uts = test_scenario::take_shared<UnderlyingToken<OCT, YOCT, SROCT>>(&scenario);
    let mut saver_vault_reserve = test_scenario::take_shared<SaverReserve<YOCT>>(&scenario);
    let saver_config = test_scenario::take_shared<SaverConfig>(&scenario);
    let limiter_config = test_scenario::take_shared<LimiterConfig>(&scenario);
    let adapter_config = test_scenario::take_shared<AdapterConfig>(&scenario);
    let mut mock_share_vault = test_scenario::take_shared<MockVault<OCT, YOCT>>(&scenario);
    let mut sroct_minter = test_scenario::take_shared<SaverMinter<SROCT>>(&scenario);
    let keeper_cap = test_scenario::take_from_address<saver::KeeperCap>(&scenario, Keeper);
    let mut liquidation_limiter = test_scenario::take_shared<LiquidateLimiter<OCT, YOCT, SROCT>>(&scenario);

    // init user info
    init_saver_user_info<YOCT, SROCT>(&sroct_minter, &mut scenario, User1);
    let mut user1_saver_info = test_scenario::take_from_address<SaverUserInfo<YOCT, SROCT>>(&scenario, User1);
    print(&b"User1 saver info: ");
    print(&user1_saver_info);

    init_saver_user_info<YOCT, SROCT>(&sroct_minter, &mut scenario, User2);
    let mut user2_saver_info = test_scenario::take_from_address<SaverUserInfo<YOCT, SROCT>>(&scenario, User2);
    print(&b"User2 saver info: ");
    print(&user2_saver_info);

    // Setting case

    // 1. User 1 deposit 1000000000 OCT 
    test_scenario::next_tx(&mut scenario, User1);
    let amount_to_deposit = 1000000000;
    let coin_to_deposit = mint_coin<OCT>(amount_to_deposit, &mut scenario);
    let coin_to_deposit = mock::deposit(&mut mock_share_vault, coin_to_deposit, test_scenario::ctx(&mut scenario));
    mock_adapter::deposit(
        &adapter_config,
        coin_to_deposit,
        &mut user1_saver_info,
        &mut saver_vault_reserve,
        &mut sroct_minter,
        &clock,
        &mock_share_vault
    );
    test_scenario::next_tx(&mut scenario, Admin);
    let user1_current_share = saver::get_user_info_shares_balance(&user1_saver_info);
    
    // 2. User 2 deposit 2000000 oct
    test_scenario::next_tx(&mut scenario, User2);
    let amount_to_deposit = 2000000;
    let coin_to_deposit = mint_coin<OCT>(amount_to_deposit, &mut scenario);
    let coin_to_deposit = mock::deposit(&mut mock_share_vault, coin_to_deposit, test_scenario::ctx(&mut scenario));
    mock_adapter::deposit(
        &adapter_config,
        coin_to_deposit,
        &mut user2_saver_info,
        &mut saver_vault_reserve,
        &mut sroct_minter,
        &clock,
        &mock_share_vault
    );

    // 3. donate to increase the price
    test_scenario::next_tx(&mut scenario, Admin);
    let coin_to_donate = mint_coin<OCT>(500000, &mut scenario);
    mock::donate(
        &mut mock_share_vault,
        coin_to_donate
    );

    // 3.1. poke to get harvestable balance
    test_scenario::next_tx(&mut scenario, User2);
    mock_adapter::poke(
        &adapter_config,
        &mut sroct_minter,
        &mut user2_saver_info,
        &clock,
        &mock_share_vault
    );
    test_scenario::next_tx(&mut scenario, User2);

    let current_harvestable_balance = saver::yt_config_harvestable_balance<YOCT, SROCT>(&sroct_minter);
    print(&current_harvestable_balance);
    assert!(saver::get_user_info_profit(&user2_saver_info) == 0, 0);
    assert!(saver::yt_config_pending_credit<YOCT, SROCT>(&sroct_minter) == 0, 0);
    let current_price = mock::price(&mock_share_vault);
    let amount_oct_harvested = current_price * current_harvestable_balance / 10u128.pow(9);
    let current_distributed_amount: u128 = amount_oct_harvested - amount_oct_harvested * PROTOCOL_FEE / 10000;

    // 4. harvest
    test_scenario::next_tx(&mut scenario, Keeper);
    
    mock_adapter::harvest(
        &adapter_config,
        &uts,
        &keeper_cap,
        &mut sroct_minter,
        &mut saver_vault_reserve,
        &clock,
        1,
        &rd_config,
        &mut rd_vault,
        &mut mock_share_vault,
        test_scenario::ctx(&mut scenario)
    );

    // 5. User 1 poke and check weight
    test_scenario::next_tx(&mut scenario, User1);
    clock::increment_for_testing(&mut clock, 100000);
    let user1_old_weight = saver::get_user_info_last_accrue_weight(&user1_saver_info);
    test_scenario::next_tx(&mut scenario, User1);
    assert!(saver::yt_config_pending_credit<YOCT, SROCT>(&sroct_minter) == current_distributed_amount, 0);
    mock_adapter::poke(
        &adapter_config,
        &mut sroct_minter,
        &mut user1_saver_info,
        &clock,
        &mock_share_vault
    );
    test_scenario::next_tx(&mut scenario, User2);
    let unlock_rate = FIXED_POINT_SCALAR / 604800;
    let current_weight = saver::yt_config_accrued_weight<YOCT, SROCT>(&sroct_minter);
    let current_unlock_credit = 
    current_distributed_amount * 
    ((clock::timestamp_ms(&clock) - (saver::yt_config_last_distribution<YOCT, SROCT>(&sroct_minter) as u64)) as u128)
    * unlock_rate / FIXED_POINT_SCALAR ;
    assert!(current_weight == current_unlock_credit * FIXED_POINT_SCALAR / saver::yt_config_total_shares<YOCT, SROCT>(&sroct_minter), 0);
    let user1_current_profit = (current_weight - user1_old_weight) * user1_current_share / FIXED_POINT_SCALAR;
    print(&user1_current_share);
    print(&user1_current_profit);
    print(&saver::get_user_info_profit(&user1_saver_info));
    assert!(user1_current_profit == saver::get_user_info_profit(&user1_saver_info));
    
    // return all shared objects 
    test_scenario::return_shared(saver_config);
    test_scenario::return_shared(limiter_config);
    test_scenario::return_shared(sroct_minter);
    test_scenario::return_shared(adapter_config);
    test_scenario::return_shared(mock_share_vault);
    test_scenario::return_shared(saver_vault_reserve);
    test_scenario::return_shared(uts);
    test_scenario::return_shared(rd_vault);
    test_scenario::return_shared(rd_config);
    test_scenario::return_shared(liquidation_limiter);

    // return to address
    test_scenario::return_to_address(User1, user1_saver_info);
    test_scenario::return_to_address(User2, user2_saver_info);
    test_scenario::return_to_address(Keeper, keeper_cap);

    test_scenario::next_tx(&mut scenario, Admin);

    test_scenario::end(scenario);
    clock::destroy_for_testing(clock);
}


#[test, expected_failure(abort_code = 0)]
fun test_mint_fail() { // overmint
    // init clock and scenario
    let mut scenario = test_scenario::begin(Admin);
    let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1000);
    prepare_state(&clock, &mut scenario);

    // take all shared objects
    let rd_config = test_scenario::take_shared<RdConfig>(&scenario);
    let mut rd_vault = test_scenario::take_shared<RdVault<OCT, SROCT>>(&scenario);
    let uts = test_scenario::take_shared<UnderlyingToken<OCT, YOCT, SROCT>>(&scenario);
    let mut saver_vault_reserve = test_scenario::take_shared<SaverReserve<YOCT>>(&scenario);
    let saver_config = test_scenario::take_shared<SaverConfig>(&scenario);
    let limiter_config = test_scenario::take_shared<LimiterConfig>(&scenario);
    let adapter_config = test_scenario::take_shared<AdapterConfig>(&scenario);
    let mut mock_share_vault = test_scenario::take_shared<MockVault<OCT, YOCT>>(&scenario);
    let mut sroct_minter = test_scenario::take_shared<SaverMinter<SROCT>>(&scenario);

    // init user info
    init_saver_user_info<YOCT, SROCT>(&sroct_minter, &mut scenario, User1);
    let mut user1_saver_info = test_scenario::take_from_address<SaverUserInfo<YOCT, SROCT>>(&scenario, User1);
    print(&b"User1 saver info: ");
    print(&user1_saver_info);

    init_saver_user_info<YOCT, SROCT>(&sroct_minter, &mut scenario, User2);
    let mut user2_saver_info = test_scenario::take_from_address<SaverUserInfo<YOCT, SROCT>>(&scenario, User2);
    print(&b"User2 saver info: ");
    print(&user2_saver_info);

    // Setting case

    // 1. User 1 deposit 1000000000 YOCT 
    test_scenario::next_tx(&mut scenario, User1);
    let amount_to_deposit = 1000000000;
    let coin_to_deposit = mint_coin<OCT>(amount_to_deposit, &mut scenario);
    let coin_to_deposit = mock::deposit(&mut mock_share_vault, coin_to_deposit, test_scenario::ctx(&mut scenario));
    mock_adapter::deposit(
        &adapter_config,
        coin_to_deposit,
        &mut user1_saver_info,
        &mut saver_vault_reserve,
        &mut sroct_minter,
        &clock,
        &mock_share_vault
    );

    // 4. User 1 mint sroct
    test_scenario::next_tx(&mut scenario, User1);
    let amount_to_mint = amount_to_deposit * 60 / 100;
    mock_adapter::mint(
        &uts,
        &adapter_config,
        &mut user1_saver_info,
        &mut sroct_minter,
        &clock,
        amount_to_mint as u64,
        User1,
        &mock_share_vault,
        test_scenario::ctx(&mut scenario)
    );
    test_scenario::next_tx(&mut scenario, User2);
    let coin_was_minted = test_scenario::take_from_address<Coin<SROCT>>(&scenario, User1);
    assert!(coin::value(&coin_was_minted) == amount_to_mint as u64, 0);
    assert!(saver::get_user_info_debt(&user1_saver_info) == amount_to_mint as u128, 0);
    coin::burn_for_testing(coin_was_minted);



    // return all shared objects 
    test_scenario::return_shared(saver_config);
    test_scenario::return_shared(limiter_config);
    test_scenario::return_shared(sroct_minter);
    test_scenario::return_shared(adapter_config);
    test_scenario::return_shared(mock_share_vault);
    test_scenario::return_shared(saver_vault_reserve);
    test_scenario::return_shared(uts);
    test_scenario::return_shared(rd_vault);
    test_scenario::return_shared(rd_config);

    // return to address
    test_scenario::return_to_address(User1, user1_saver_info);
    test_scenario::return_to_address(User2, user2_saver_info);
    //test_scenario::return_to_address(Keeper, keeper_cap);

    test_scenario::next_tx(&mut scenario, Admin);

    test_scenario::end(scenario);
    clock::destroy_for_testing(clock);
}

#[test]
public fun test_redeem_pool() {
    // init clock and scenario
    let mut scenario = test_scenario::begin(Admin);
    let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1000);
    prepare_state(&clock, &mut scenario);

    // take all shared objects
    let rd_config = test_scenario::take_shared<RdConfig>(&scenario);
    let mut rd_vault = test_scenario::take_shared<RdVault<OCT, SROCT>>(&scenario);

    // 1. create account
    test_scenario::next_tx(&mut scenario, User1);
    redeem_pool::create_account(
        &rd_config,
        &rd_vault,
        test_scenario::ctx(&mut scenario)
    );

    test_scenario::next_tx(&mut scenario, User1);
    let mut user_account = test_scenario::take_from_address<redeem_pool::Account<OCT, SROCT>>(&scenario, User1);

    // 2. deposit
    let amount_sroct_to_exchange: u64 = 100000000;
    let sroct_to_exchange = mint_coin<SROCT>(amount_sroct_to_exchange, &mut scenario);
    test_scenario::next_tx(&mut scenario, User1);
    redeem_pool::deposit(
        &rd_config,
        sroct_to_exchange,
        &mut user_account,
        &mut rd_vault,
    );
    test_scenario::next_tx(&mut scenario, User1);
    assert!(redeem_pool::get_vault_total_unexchange(&rd_vault) == amount_sroct_to_exchange as u128, 0);
    // 3. donate
    let amount_oct_to_donate: u64 = 30000;
    clock::increment_for_testing(&mut clock, 10000);
    let oct_to_donate = mint_coin<OCT>(amount_oct_to_donate, &mut scenario);
    redeem_pool::donate(
        &rd_config,
        oct_to_donate,
        &mut rd_vault
    );
    test_scenario::next_tx(&mut scenario, User1);
    let current_weight = (amount_oct_to_donate as u128) * FIXED_POINT_SCALAR / (amount_sroct_to_exchange as u128);
    assert!(current_weight == redeem_pool::get_vault_accumulated_weight(&rd_vault), 0);
    let (_, _, _, user_ent_w) = redeem_pool::get_account_info(&user_account);
    assert!(user_ent_w == 0, 0);
    let total_to_exchange = (current_weight) * (amount_sroct_to_exchange as u128) / FIXED_POINT_SCALAR;

    redeem_pool::poke(
        &mut user_account,
        &mut rd_vault
    );
    test_scenario::next_tx(&mut scenario, User1);

    let (_, user_unex, user_ex, user_ent_w) = redeem_pool::get_account_info(&user_account);
    assert!(user_ent_w == current_weight, 0);
    assert!(user_ex == total_to_exchange, 0);
    print(&user_unex);
    print(&user_ex);

    // 4. claim
    test_scenario::next_tx(&mut scenario, User1);
    redeem_pool::claim(
        &mut user_account,
        &mut rd_vault,
        20000,
        User1, 
        test_scenario::ctx(&mut scenario)
    );
    test_scenario::next_tx(&mut scenario, User1);
    let claimed_coin = test_scenario::take_from_address<Coin<OCT>>(&scenario, User1);
    assert!(coin::value(&claimed_coin) == 20000, 0);
    coin::burn_for_testing(claimed_coin);

    // 5. withdraw
    redeem_pool::withdraw(
        &mut user_account,
        &mut rd_vault,
        10000,
        User1,
        test_scenario::ctx(&mut scenario)
    );
    test_scenario::next_tx(&mut scenario, User1);
    let withdrawed_coin = test_scenario::take_from_address<Coin<SROCT>>(&scenario, User1);
    assert!(coin::value(&withdrawed_coin) == 10000, 0);
    coin::burn_for_testing(withdrawed_coin);

    // return all shared objects
    test_scenario::return_shared(rd_vault);
    test_scenario::return_shared(rd_config);

    // return user object
    test_scenario::return_to_address(User1, user_account);

    test_scenario::end(scenario);
    clock::destroy_for_testing(clock);
}

// #[test, expected_failure(abort_code = ::saver::saver_tests::ENotImplemented)]
// fun test_saver_fail() {
//     abort ENotImplemented
// }

