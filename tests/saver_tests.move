#[test_only]
module saver::saver_tests;
use std::unit_test;
use saver::saver::{Self, Config as SaverConfig, Vault as SaverReserve, Minter as SaverMinter, UserInfo as SaverUserInfo};
use saver::mock_adapter::{Self, AdapterConfig, UnderlyingToken};
use saver::limiter::{Self, LimiterConfig};
use saver::mock::{Self, Vault as MockVault};
use saver::redeem_pool::{Self, Config as RdConfig};
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

const FIXED_POINT_SCALAR: u128 = 1000000000000000000;
const MAXIMUM_LIMIT: u128 = 1000000000000000000;
const MAX_DURATION: u128 = 85000;
const MIN_LIMIT: u128 = 0;
const PROTOCOL_FEE: u128 = 1000;
const MINIMUM_COLLATERLIZATION: u128 = 50;


fun init_redeem_pool(scenario: &mut Scenario) {
    test_scenario::next_tx(scenario, Admin);
    
    redeem_pool::test_init(test_scenario::ctx(scenario));
}

fun init_limiter(scenario: &mut Scenario) {
    test_scenario::next_tx(scenario, Admin);
    
    limiter::test_init(test_scenario::ctx(scenario));
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
        FIXED_POINT_SCALAR / 86400,
        test_scenario::ctx(scenario)
    );

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

    {
        // for admin
        let yoct_coin = coin::mint(&mut treasury_cap, 10000000000000, test_scenario::ctx(scenario));
        transfer::public_transfer(yoct_coin, Admin);

        // for user
        let yoct_coin = coin::mint(&mut treasury_cap, 10000000000000, test_scenario::ctx(scenario));
        transfer::public_transfer(yoct_coin, User1);
    };

    test_scenario::next_tx(scenario, Admin);
    
    mock::create_vault<OCT, YOCT>(
        treasury_cap,
        test_scenario::ctx(scenario)
    );
}

fun create_sroct(_clock: &Clock, scenario: &mut Scenario) {
    test_scenario::next_tx(scenario, Admin);
    sroct::test_init( test_scenario::ctx(scenario));
}

fun prepare_state(clock: &Clock, scenario: &mut Scenario) {
    create_sroct(clock, scenario);
    init_shares_vault(clock, scenario);
    init_limiter(scenario);
    init_saver(clock, scenario);
    init_adapter(clock, scenario);
    init_redeem_pool(scenario);
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

    // check admin balance
    let yoct_coin1 = test_scenario::take_from_address<Coin<YOCT>>(&scenario, Admin);
    print(&yoct_coin1);
    assert!(coin::value(&yoct_coin1) == 10000000000000, 0);

    let yoct_coin2 = test_scenario::take_from_address<Coin<YOCT>>(&scenario, User1);
    print(&yoct_coin2);
    assert!(coin::value(&yoct_coin2) == 10000000000000, 0);


    // return all shared objects 
    test_scenario::return_shared(saver_config);
    test_scenario::return_shared(limiter_config);
    test_scenario::return_shared(yoct_minter);
    test_scenario::return_shared(adapter_config);
    test_scenario::return_shared(mock_share_vault);
    test_scenario::return_to_address(Admin, yoct_coin1);
    test_scenario::return_to_address(User1, yoct_coin2);

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

}

// #[test, expected_failure(abort_code = ::saver::saver_tests::ENotImplemented)]
// fun test_saver_fail() {
//     abort ENotImplemented
// }

