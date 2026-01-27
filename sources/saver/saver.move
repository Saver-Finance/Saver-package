/// Module: saver
/// //TODO: Refactor struct and variable name
module saver::saver;

use one::balance::{Self, Balance};
use one::coin::{Self, Coin, TreasuryCap, CoinMetadata};
use one::table::{Self, Table};
use saver::error::{Self, unAuthorize, notEnoughBalance, alreadyInitialize, freezeVault, overMaximumExpectedValue, mintingLimitExceed};
use saver::limiter::{Self, Limiter, LimiterConfig, get, LimiterAccessCap, take_limiter_access_cap};
use std::option::{Self, Option};
use one::clock::Clock;
use one::object::{Self, UID};
use one::transfer::{Self};
use one::tx_context::{Self, TxContext};
use one::clock;
use std::type_name::{Self, TypeName};
use std::u128::min;
use std::debug::{print};
use one::linked_table::{Self, LinkedTable};


const BPS: u128 = 10000;
const FIXED_POINT_SCALAR: u128 = 1000000000000000000;

public struct AdapterCap has key, store {
    id: UID,
}

public struct Config has key {
    id: UID,
    admin: address,
    pending_admin: address,
}


public struct AgentCap has key {
    id: UID,
    owner: address
}


public struct SentinelCap has key {
    id: UID,
    owner: address
}

public struct KeeperCap has key {
    id: UID,
    owner: address
}

public struct Vault<phantom T> has key { //NOTE T: Yield Token 
    id: UID,
    reserve: Balance<T>,
}

public struct YieldTokenConfig has store {
    decimals: u8,
    maximum_loss: u128,
    maximum_expected_value: u128,
    credit_unlock_rate: u128,
    active_balance: u128,
    harvestable_balance: u128,
    total_shares: u128, 
    expected_value: u128,
    pending_credit: u128,
    distributed_credit: u128,
    last_distribution: u64,
    accrued_weight: u128,
    enabled: bool
}

public struct UserDepositInfo has store {
    last_accrue_weight: u128,
    shares_balance: u128,
    mint_allowance: u128,
    withdraw_allowance: Table<address, u128>
}

public struct UserInfo<phantom T, phantom S> has key { //NOTE S: Debt Token
    id: UID,
    debt: u128,
    profit: u128,
    owner: address,
    deposited_token: UserDepositInfo,
}

public struct Minter<phantom S> has key { //NOTE S: Share token
    id: UID,
    treasury: TreasuryCap<S>,
    limiter: Limiter, //
    ytc: Table<TypeName, YieldTokenConfig>,
    protocol_fee: u128,
    protocol_fee_receiver: address,
    minimum_collateralization: u128,
    limiter_cap: LimiterAccessCap
}


fun init(ctx: &mut TxContext) {
    let sender = ctx.sender();
    let config = Config {
        id: object::new(ctx),
        admin: sender,
        pending_admin: sender,
    };
    transfer::share_object(config);
}

public fun grant_keeper_cap(
    config: &Config,
    new_keeper: address,
    ctx: &mut TxContext
) {
    let sender = ctx.sender();
    assert!(sender == config.admin, unAuthorize());
    let new_keeper_cap = KeeperCap {
        id:object::new(ctx),
        owner: new_keeper
    };
    transfer::transfer(new_keeper_cap, new_keeper);   
}

entry fun create_new_minter<S>(
    treasury_cap: TreasuryCap<S>, 
    config: &Config,
    limiter_config: &LimiterConfig,
    clock: &Clock,    
    maximum: u128,
    min_limit: u128,
    duration: u128,
    protocol_fee: u128,
    protocol_fee_receiver: address,
    minimum_collateralization: u128,
    ctx: &mut TxContext
) {
    assert!(ctx.sender() == config.admin, unAuthorize());
    let new_minter = Minter<S> {
        id: object::new(ctx),
        treasury: treasury_cap,
        limiter: limiter::create_linear_grow_limiter(maximum, duration, min_limit, limiter_config, clock, ctx),
        ytc: table::new<TypeName, YieldTokenConfig>(ctx),
        protocol_fee,
        protocol_fee_receiver,
        minimum_collateralization,
        limiter_cap: take_limiter_access_cap(limiter_config, ctx)
    }; 
    transfer::share_object(new_minter);
}

/// Admin Function 
entry fun propose_admin(
    config: &mut Config, 
    new_admin: address, 
    ctx: &TxContext
) {
    let sender = ctx.sender();
    assert!(sender == config.admin, unAuthorize());
    config.pending_admin = new_admin;
}

entry fun claim_admin_role(config: &mut Config, ctx: &TxContext) {
    let sender = ctx.sender();
    assert!(sender == config.pending_admin, unAuthorize());
    assert!(sender != config.admin, unAuthorize());
    config.admin = config.pending_admin;
}

entry fun change_minter_config<S>(
    config: &Config,
    minter: &mut Minter<S>, 
    mut new_protocol_fee: Option<u128>, 
    mut new_protocol_fee_receiver: Option<address>,
    mut new_minimum_collateralization: Option<u128>,
    ctx: &TxContext
) {
    assert!(config.admin == ctx.sender(), unAuthorize());
    if (option::is_some(&new_protocol_fee)) {
        let nps = option::extract(&mut new_protocol_fee);
        minter.protocol_fee = nps;
    };

    if (option::is_some(&new_protocol_fee_receiver)) {
        let npfr = option::extract(&mut new_protocol_fee_receiver);
        minter.protocol_fee_receiver = npfr;
    };

    if(option::is_some(&new_minimum_collateralization)) {
        let nmc = option::extract(&mut new_minimum_collateralization);
        minter.minimum_collateralization = nmc;
    }
}

entry fun init_vault_reserve<T>(
    config: &Config,
    ctx: &mut TxContext
) {
    assert!(ctx.sender() == config.admin, unAuthorize());
        let vault = Vault<T> {
        id: object::new(ctx),
        reserve: balance::zero<T>(),
    };
    transfer::share_object(vault);
}

entry fun create_vault<T, S>( // accept a new token to be used to mint S
    config: &Config,
    clock: &Clock,
    minter: &mut Minter<S>,
    decimals: u8,
    maximum_loss: u128,
    maximum_expected_value: u128,
    credit_unlock_rate: u128,
    ctx: &mut TxContext
) {
    let tname = type_name::get<T>();
    assert!(!table::contains(&minter.ytc, tname), 0);
    let sender = ctx.sender();
    assert!(sender == config.admin, unAuthorize());

    let token_config = YieldTokenConfig {
        decimals: decimals,
        maximum_loss: maximum_loss,
        maximum_expected_value: maximum_expected_value,
        credit_unlock_rate: credit_unlock_rate,
        active_balance: 0,
        harvestable_balance: 0,
        total_shares: 0,
        expected_value: 0,
        pending_credit: 0,
        distributed_credit: 0,
        last_distribution: clock::timestamp_ms(clock),
        accrued_weight: 0,
        enabled: true
    };
    table::add(&mut minter.ytc, tname, token_config);
    
}

entry fun change_minter<T, S>(
    config: &Config,
    minter: &mut Minter<S>,
    mut decimals: Option<u8>,
    mut maximum_loss: Option<u128>, 
    mut maximum_expected_value: Option<u128>,
    mut credit_unlock_rate: Option<u128>,
    mut enabled: Option<bool>,
    ctx: &TxContext 
) {
    let tname = type_name::get<T>();
    assert!(table::contains(&minter.ytc, tname), 0);
    assert!(config.admin == ctx.sender(), unAuthorize());
    let vault = table::borrow_mut(&mut minter.ytc, tname);
    if(option::is_some(&decimals)) {
        let decm = option::extract(&mut decimals);
        vault.decimals = decm;
    };
    if(option::is_some(&maximum_loss)) {
        let maxloss = option::extract(&mut maximum_loss);
        vault.maximum_loss = maxloss;
    };
    if(option::is_some(&maximum_expected_value)) {
        let mev = option::extract(&mut maximum_expected_value);
        vault.maximum_expected_value = mev;
    };
    if(option::is_some(&credit_unlock_rate)) {
        let rate = option::extract(&mut credit_unlock_rate);
        vault.credit_unlock_rate = rate;
    };
    if(option::is_some(&enabled)) {
        let enb = option::extract(&mut enabled);
        vault.enabled = enb
    }
}

public fun take_adapter_cap(config: &Config, ctx: &mut TxContext): AdapterCap {
    let sender = ctx.sender();
    assert!(config.admin == sender, unAuthorize());
    let new_adapter_cap = AdapterCap {
        id: object::new(ctx)
    };
    new_adapter_cap
}

public fun snap<T, S>(
    _: &AdapterCap,
    minter: &mut Minter<S>,
    price: u128,
) {
    let tname = type_name::get<T>();
    let yt_info = table::borrow_mut(&mut minter.ytc, tname);
    let expected_value= i_convert_yt_to_ut(price, yt_info.active_balance, yt_info.decimals);
    yt_info.expected_value = expected_value;
}


/// Users Function
entry fun init_user_info<T, S>(minter: &Minter<S>, ctx: &mut TxContext) {
    let tname = type_name::get<T>();
    assert!(table::contains(&minter.ytc, tname), 0);
    let new_user = UserInfo<T, S> {
        id: object::new(ctx),
        debt: 0,
        profit: 0,
        owner: ctx.sender(),
        deposited_token: UserDepositInfo {
            last_accrue_weight: 0,
            shares_balance: 0,
            mint_allowance: 0,
            withdraw_allowance: table::new<address, u128>(ctx)
        },
     
    };
    transfer::transfer(new_user, ctx.sender());
}

public fun poke<T, S>(
    _: &AdapterCap,
    minter: &mut Minter<S>,
    user_info: &mut UserInfo<T, S>,
    clock: &Clock,
    price: u128
) {
    let tname = type_name::get<T>();
    assert!(table::contains(&minter.ytc, tname), 0);
    let yt_info = table::borrow_mut(&mut minter.ytc, tname);
    let user_yt_info = &mut user_info.deposited_token;
    i_preemptively_harvest(yt_info, price);
    i_distribute_unlock_credit(yt_info, clock);
    i_poke(&mut user_info.debt, &mut user_info.profit, user_yt_info, yt_info);
}
 

public fun deposit<T, S>(
    _: &AdapterCap, 
    token: Coin<T>, 
    price: u128,
    user_info: &mut UserInfo<T, S>, 
    vault: &mut Vault<T>,
    minter: &mut Minter<S>,
    clock: &Clock,
) {
    let tname = type_name::get<T>();
    assert!(table::contains(&minter.ytc, tname), 0);
    let yt_info = table::borrow_mut(&mut minter.ytc, tname);
    let user_yt_info = &mut user_info.deposited_token;
    assert!(yt_info.enabled, freezeVault());
    let amount = coin::value(&token) as u128;
    let _ = i_deposit(&mut user_info.debt, &mut user_info.profit, amount, price, user_yt_info, yt_info, clock);
    let coin_balance = coin::into_balance(token);
    balance::join(&mut vault.reserve, coin_balance);   
}

public fun mint<T, S>(
    _: &AdapterCap,
    user_info: &mut UserInfo<T, S>,
    minter: &mut Minter<S>,
    clock: &Clock,
    amount: u64,
    price: u128,
    recipient: address,
    conversion_factor: u128,
    ctx: &mut TxContext
) {
    assert!(amount > 0, notEnoughBalance());
    i_mint(user_info, minter, clock, amount, price, recipient, conversion_factor, ctx);
}

public fun burn<T, S>(
    _: &AdapterCap,
    user_info: &mut UserInfo<T, S>,
    mut token: Coin<S>,
    minter: &mut Minter<S>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let amount = coin::value(&token) as u128;
    let tname = type_name::get<T>();
    let yt_info = table::borrow_mut(&mut minter.ytc, tname);
    i_distribute_unlock_credit(yt_info, clock);
    i_poke(&mut user_info.debt, &mut user_info.profit, &mut user_info.deposited_token, yt_info);
    let debt = user_info.debt;
    if(debt == 0) {
        transfer::public_transfer(token, ctx.sender());
        return;
    };
    let credit = min(amount, debt);
    user_info.debt = user_info.debt - credit;
    let amount_left = amount - credit;
    limiter::increase(&minter.limiter_cap, &mut minter.limiter, clock, credit);
    if(amount_left > 0) {
        let burn_coin = coin::split(&mut token, credit as u64, ctx);
        coin::burn(&mut minter.treasury, burn_coin);
        transfer::public_transfer(token, ctx.sender());
    }
    else {
        coin::burn(&mut minter.treasury, token);
    }

}

public fun repay<T, S>(
    _: &AdapterCap,
    amount: u64,
    user_info: &mut UserInfo<T, S>,
    minter: &mut Minter<S>,
    clock: &Clock,
    _price: u128,
    conversion_factor: u128,
): u64 {
    let tname = type_name::get<T>();
    let yt_info = table::borrow_mut(&mut minter.ytc, tname);
    assert!(amount > 0, 0);
    i_distribute_unlock_credit(yt_info, clock);
    i_poke(&mut user_info.debt, &mut user_info.profit, &mut user_info.deposited_token, yt_info);
    let debt = user_info.debt;
    if(debt == 0) {
        return 0;
    };
    let maximum_amount = i_normalize_dt_to_ut(debt, conversion_factor);
    let actual_amount = min(amount as u128, maximum_amount);
    // TODO: check repay limiter -> call sang adapter (hoac check sau khi tra ve)

    let credit = i_normalize_ut_to_dt(actual_amount, conversion_factor);
    user_info.debt = user_info.debt - credit;

    // TODO: decrease repay limit

    // TODO: transfer token cho transmuter

    // TODO: emit event

    
    actual_amount as u64
}

public fun liquidate<T, S>(
    _: &AdapterCap,
    user_info: &mut UserInfo<T, S>,
    minter: &mut Minter<S>,
    vault: &mut Vault<T>,
    clock: &Clock,
    price: u128,
    shares: u128,
    conversion_factor: u128,
    minimum_amount_out: u128,
    ctx: &mut TxContext
): (u128, Coin<T>) {
    assert!(ctx.sender() == user_info.owner, 0);
    let tname = type_name::get<T>();
    let yt_info = table::borrow_mut(&mut minter.ytc, tname);
    assert!(i_check_loss(price, yt_info.decimals, yt_info.active_balance, yt_info.expected_value, yt_info.maximum_loss));
    let (unrealized_debt, _unrealize_profit) = i_calculate_unrealized_debt_profit(
        user_info,
        yt_info,
        clock
    );
    assert!(unrealized_debt > 0, 0);
    let maximum_shares = i_convert_ut_to_sh(
        yt_info,
        i_normalize_dt_to_ut(unrealized_debt, conversion_factor),
        price
    );
    let actual_shares = min(shares, maximum_shares);
    let amount_yt = i_convert_sh_to_yt(yt_info, actual_shares, price);
    let amount_ut = i_convert_yt_to_ut(price, amount_yt, yt_info.decimals);
    assert!(amount_ut >= minimum_amount_out, 0);
    assert!(amount_ut > 0, 0);
    i_preemptively_harvest(yt_info, price);
    i_distribute_unlock_credit(yt_info, clock);
    let credit = i_normalize_ut_to_dt(amount_ut, conversion_factor);
    i_poke(&mut user_info.debt, &mut user_info.profit, &mut user_info.deposited_token, yt_info);
    i_burn_shares(&mut user_info.deposited_token, yt_info, actual_shares);
    user_info.debt = user_info.debt - credit;
    i_sync(yt_info, amount_yt, price, false);
    i_validate(yt_info, user_info, minter.minimum_collateralization, conversion_factor, price);

    (amount_ut, split_coin(vault, amount_yt as u64, ctx))
}

public fun harvest<T, S>(
    _: &AdapterCap,
    _: &KeeperCap,
    minter: &mut Minter<S>,
    clock: &Clock,
    vault: &mut Vault<T>,
    price: u128,
    minimum_amount_out: u128,
    conversion_factor: u128,
    ctx: &mut TxContext
): (u128, u128, address, Coin<T>) {
    let tname = type_name::get<T>();
    let yt_info = table::borrow_mut(&mut minter.ytc, tname);
    i_preemptively_harvest(yt_info, price);
    let harvestable_amount = yt_info.harvestable_balance;
    yt_info.harvestable_balance = 0;
    assert!(harvestable_amount != 0, 0);
    let amount_ut = i_convert_yt_to_ut(price, harvestable_amount, yt_info.decimals);  
    assert!(amount_ut >= minimum_amount_out, 0);

    let fee_amount = amount_ut * minter.protocol_fee / BPS;
    let distribute_amount = amount_ut - fee_amount;
    let credit = i_normalize_ut_to_dt(distribute_amount, conversion_factor);
    i_distribute_credit(yt_info, credit, clock);

    (distribute_amount, fee_amount, minter.protocol_fee_receiver, split_coin(vault, harvestable_amount as u64, ctx))
}

public fun withdraw<T, S>(
    _: &AdapterCap,
    vault: &mut Vault<T>,
    user_info: &mut UserInfo<T, S>,
    minter: &mut Minter<S>,
    clock: &Clock,
    shares: u128,
    price: u128,
    conversion_factor: u128,
    ctx: &mut TxContext
): (Coin<T>) {
    let tname = type_name::get<T>();
    let yt_info = table::borrow_mut(&mut minter.ytc, tname);
    let amount_yt = i_withdraw(
        yt_info,
        user_info,
        clock,
        shares,
        price,
        conversion_factor,
        minter.minimum_collateralization
    );
    let balance_receive = balance::split(&mut vault.reserve, amount_yt as u64);
    let coin_receive = coin::from_balance(balance_receive, ctx);
    (coin_receive)
}

public fun check_loss<T, S>(
    price: u128,
    minter: &Minter<S>
) {
    let tname = type_name::get<T>();
    let yt = table::borrow(&minter.ytc, tname);
    i_check_loss(price, yt.decimals, yt.active_balance, yt.expected_value, yt.maximum_loss);
}

public fun burn_token<S>(
    coin_to_burn: Coin<S>,
    minter: &mut Minter<S>,
) {
    coin::burn(&mut minter.treasury, coin_to_burn);
}

/// Internal

fun i_mint<T, S>(
    user_info: &mut UserInfo<T, S>,
    minter: &mut Minter<S>,
    clock: &Clock,
    amount: u64,
    price: u128,
    recipient: address,
    conversion_factor: u128,
    ctx: &mut TxContext
) {
    let tname = type_name::get<T>();
    let yt_info = table::borrow_mut(&mut minter.ytc, tname);
    i_check_minting_limit(amount, &minter.limiter, clock);
    i_preemptively_harvest(yt_info, price);
    i_distribute_unlock_credit(yt_info, clock);
    i_poke(&mut user_info.debt, &mut user_info.profit, &mut user_info.deposited_token, yt_info);
    i_update_debt(&mut user_info.debt, &mut user_info.profit, amount);
    i_validate(yt_info, user_info, minter.minimum_collateralization, conversion_factor, price);
    
    limiter::decrease(&minter.limiter_cap, &mut minter.limiter, clock, amount as u128);
    let coin = coin::mint(&mut minter.treasury, amount, ctx);
    transfer::public_transfer(coin, recipient);

    // TODO: emit even
}

fun i_deposit(
    user_debt: &mut u128,
    user_profit: &mut u128,
    amount: u128,
    price: u128,
    user_info: &mut UserDepositInfo,
    vault: &mut YieldTokenConfig,
    clock: &Clock
): u128 {
    assert!(i_check_loss(price, vault.decimals, vault.active_balance, vault.expected_value, vault.maximum_loss));
    i_preemptively_harvest(vault, price);
    i_distribute_unlock_credit(vault, clock); 
    i_poke(user_debt, user_profit, user_info, vault);
    let shares = i_issue_shares_for_amount(user_info, vault, amount, price);
    i_sync(vault, amount, price, true);
    let maximum_expected_value = vault.maximum_expected_value;
    assert!(maximum_expected_value >= vault.expected_value, overMaximumExpectedValue());

    // TODO: emit event

    shares
}

fun i_withdraw<T, S>(
    yt: &mut YieldTokenConfig,
    user_info: &mut UserInfo<T, S>,
    clock: &Clock,
    shares: u128,
    price: u128,
    conversion_factor: u128,
    minimum_collateralization: u128
): u128 {
    assert!(shares <= user_info.deposited_token.shares_balance, 0);
    i_preemptively_harvest(yt, price);
    i_distribute_unlock_credit(yt, clock);
    let amount_yt = i_convert_sh_to_yt(yt, shares, price);
    i_poke(&mut user_info.debt, &mut user_info.profit, &mut user_info.deposited_token, yt);
    i_burn_shares(&mut user_info.deposited_token, yt, shares);
    i_sync(yt, amount_yt, price, false);
    i_validate(yt, user_info, minimum_collateralization, conversion_factor, price);
    amount_yt
}

fun i_sync(vault: &mut YieldTokenConfig, amount: u128, price: u128, isAdd:bool) {
    let value = i_convert_yt_to_ut(price, amount, vault.decimals);
    if(isAdd == true) {
        vault.active_balance = vault.active_balance + amount;
        vault.expected_value = vault.expected_value + value;
    }
    else {
        vault.active_balance = vault.active_balance - amount;
        vault.expected_value = vault.expected_value - value;
    };
}

fun i_poke(user_debt: &mut u128, user_profit: &mut u128, user_info: &mut UserDepositInfo, vault: &YieldTokenConfig) {
    let current_accrue_weighted = vault.accrued_weight;
    let user_last_accrue = user_info.last_accrue_weight;

    if(current_accrue_weighted == user_last_accrue) {
        return;
    };
    let user_balance = user_info.shares_balance;
    let unrealized_credit = (current_accrue_weighted - user_last_accrue) * user_balance / FIXED_POINT_SCALAR;
    
    let credit = min(*user_debt, unrealized_credit);
    *user_debt = *user_debt - credit; // need to minus debt first
    *user_profit = *user_profit + unrealized_credit - credit; // add the remaining credit into profit
    user_info.last_accrue_weight = current_accrue_weighted;
}

fun i_distribute_unlock_credit(vault: &mut YieldTokenConfig, clock: &Clock) {
    let unlock_credit = i_calculate_unlocked_credit(vault, clock);
    if(unlock_credit == 0) {
        return;
    };
    vault.accrued_weight = vault.accrued_weight + unlock_credit * FIXED_POINT_SCALAR / vault.total_shares;
    vault.distributed_credit = vault.distributed_credit + unlock_credit;
}

fun i_calculate_unlocked_credit(vault: &YieldTokenConfig, clock: &Clock): u128 {
    let pending_credit = vault.pending_credit;
    if(pending_credit == 0) {
        return 0;
    };
    let unlock_rate = vault.credit_unlock_rate;
    let distributed_credit = vault.distributed_credit;
    let last_distributed_time = vault.last_distribution;
    let percent_unlock = ((clock::timestamp_ms(clock) - last_distributed_time) as u128) * unlock_rate;
    if(percent_unlock < FIXED_POINT_SCALAR) {
        return pending_credit * percent_unlock / FIXED_POINT_SCALAR - distributed_credit;
    };
    pending_credit - distributed_credit
}

fun i_validate<T, S>(
    vault: &YieldTokenConfig,
    user_info: &UserInfo<T, S>,
    minimum_collateralization: u128,
    conversion_factor: u128,
    price: u128
) {
   let debt = user_info.debt;
   if(debt == 0) return;
   let collateralization = i_total_value(vault, conversion_factor, user_info.deposited_token.shares_balance, price) * FIXED_POINT_SCALAR / debt;

   assert!(collateralization >= minimum_collateralization, 0);
}

fun i_total_value(
    vault: &YieldTokenConfig,
    conversion_factor: u128, 
    shares: u128,
    price: u128
): u128 {
    let amount_ut = i_convert_sh_to_ut(vault, shares, price);
    i_normalize_ut_to_dt(amount_ut, conversion_factor)
}

fun i_preemptively_harvest(vault: &mut YieldTokenConfig, price: u128) {
    let active_balance = vault.active_balance;
    if(active_balance == 0) {
        return;
    };
    let current_value = i_convert_yt_to_ut(price, active_balance, vault.decimals);
    let expected_value = vault.expected_value;
    if(current_value <= expected_value) {
        return;
    };
    let harvestable = i_convert_ut_to_yt(price, current_value - expected_value, vault.decimals);
    if(harvestable == 0) {
        return;
    };
    vault.active_balance = vault.active_balance - harvestable;
    vault.harvestable_balance = vault.harvestable_balance + harvestable;
}

fun i_check_loss(price: u128, decimals: u8, current: u128, expected: u128, maxloss: u128): bool {
    let loss = i_cal_loss(price, decimals, current, expected);
    if(loss > maxloss) {
        return false;
    };
    true
}

fun i_update_debt(debt: &mut u128, profit: &mut u128, amount: u64) {
    let amount = amount as u128;
    let credit = min(*profit, amount);
    *profit = *profit - credit;
    *debt = *debt + amount - credit;
}

fun i_check_minting_limit(amount: u64, limiter: &Limiter, clock: &Clock) {
    let limit = limiter::get(limiter, clock);
    if(amount as u128 > limit) {
        abort mintingLimitExceed();
    }
}

fun i_cal_loss(price: u128, decimals: u8, current_active: u128, expected_value: u128): u128 {
    let current_value = i_convert_yt_to_ut(price, current_active, decimals);
    if(expected_value > current_value) {
        return (expected_value - current_value) * BPS / expected_value;
    };
    0
}

fun i_issue_shares_for_amount(user_info: &mut UserDepositInfo, vault: &mut YieldTokenConfig, amount: u128, price: u128): u128 {
    let shares = i_convert_yt_to_sh(vault, amount, price);
    user_info.shares_balance = user_info.shares_balance + shares;
    vault.total_shares = vault.total_shares + shares;
    shares
}

fun i_convert_yt_to_sh(vault: &YieldTokenConfig, amount : u128, price: u128): u128 {
    if(vault.total_shares == 0) {
        return amount;
    };

    amount * vault.total_shares / i_calculate_unrealized_active_balance(vault, price)
}

fun i_convert_sh_to_yt(vault: &YieldTokenConfig, shares : u128, price: u128): u128 {
    if(vault.total_shares == 0) {
        return shares;
    };

    shares * i_calculate_unrealized_active_balance(vault, price) / vault.total_shares
}

fun i_convert_sh_to_ut(vault: &YieldTokenConfig, amount : u128, price: u128): u128 {
    let amount_yt = i_convert_sh_to_yt(vault, amount, price);
    i_convert_yt_to_ut(price, amount_yt, vault.decimals)
}

fun i_convert_ut_to_sh(vault: &YieldTokenConfig, amount : u128, price: u128): u128 {
    let amount_yt = i_convert_ut_to_yt(price, amount, vault.decimals);
    i_convert_yt_to_sh(vault, amount_yt, price)
}

fun i_convert_yt_to_ut(price: u128, amount: u128, decimals: u8): u128 {
    amount * price / 10u128.pow(decimals)
}

fun i_convert_ut_to_yt(price: u128, amount: u128, decimals: u8): u128 {
    amount * 10u128.pow(decimals) / price
}

fun i_normalize_dt_to_ut(amount: u128, conversion_factor: u128): u128 {
    amount / conversion_factor
}

fun i_normalize_ut_to_dt(amount: u128, conversion_factor: u128): u128 {
    amount * conversion_factor
}

fun i_calculate_unrealized_active_balance(vault: &YieldTokenConfig, price: u128): u128 {
    let active_balance = vault.active_balance;
    if(active_balance == 0) {
        return 0;
    };
    let current_value = i_convert_yt_to_ut(price, active_balance, vault.decimals);
    let expected_value = vault.expected_value;
    if(current_value <= expected_value) {
        return active_balance;
    };
    let harvestable = i_convert_ut_to_yt(price, current_value - expected_value, vault.decimals);
    active_balance - harvestable
}

fun i_calculate_unrealized_debt_profit<T, S>(
    user_info: &UserInfo<T, S>, 
    yt: &YieldTokenConfig, 
    clock: &Clock
): (u128, u128){
    let mut debt = user_info.debt;
    let mut profit = user_info.profit;
    let mut current_weight = yt.accrued_weight;
    let user_last_accrue_weight = user_info.deposited_token.last_accrue_weight;
    let unlock_credit = i_calculate_unlocked_credit(yt, clock);
    if(unlock_credit > 0) {
        current_weight = current_weight + unlock_credit * FIXED_POINT_SCALAR / yt.total_shares;
    };
    if(current_weight == user_last_accrue_weight) {
        return (debt, profit);
    };
    let user_share_balance = user_info.deposited_token.shares_balance;
    let unrealized_credit = (current_weight - user_last_accrue_weight) * user_share_balance / FIXED_POINT_SCALAR;
    debt = debt - min(debt, unrealized_credit);
    profit = profit + unrealized_credit - min(debt, unrealized_credit);
    (debt, profit)
}

fun i_burn_shares(
    userDeposited: &mut UserDepositInfo,
    yt_info: &mut YieldTokenConfig,
    amount: u128
) {
    userDeposited.shares_balance = userDeposited.shares_balance - amount;
    yt_info.total_shares = yt_info.total_shares - amount;
}

fun i_distribute_credit(
    yt: &mut YieldTokenConfig, 
    amount: u128, 
    clock: &Clock,
) {
    let pending_credit = yt.pending_credit;
    let distributed_credit = yt.distributed_credit;
    let unlocked_credit = i_calculate_unlocked_credit(yt, clock);
    let locked_credit = pending_credit - distributed_credit - unlocked_credit;

    if(unlocked_credit > 0) {
        yt.accrued_weight = yt.accrued_weight + unlocked_credit * FIXED_POINT_SCALAR / yt.total_shares;
    };

    yt.pending_credit = amount + locked_credit;
    yt.distributed_credit = 0;
    yt.last_distribution = clock::timestamp_ms(clock);
}

fun split_coin<T>(vault: &mut Vault<T>, amount: u64, ctx: &mut TxContext): Coin<T> {
    let balance_receive = balance::split(&mut vault.reserve, amount as u64);
    let coin_receive = coin::from_balance(balance_receive, ctx);
    (coin_receive)
}

// TEST ONLY FUNCTION

#[test_only]
public fun test_init(ctx: &mut TxContext) {
    let sender = ctx.sender();
    let config = Config {
        id: object::new(ctx),
        admin: sender,
        pending_admin: sender,
    };
    transfer::share_object(config);
}

#[test_only]
public fun get_config(config: &Config): (address, address) {
    (config.admin, config.pending_admin)
}

#[test_only]
public fun get_vault_balance<T>(vault: &Vault<T>): u64 {
    balance::value(&vault.reserve)
}

#[test_only]
public fun get_user_info_debt<T, S>(user: &UserInfo<T, S>): u128 {
    user.debt
}

#[test_only]
public fun get_user_info_profit<T, S>(user: &UserInfo<T, S>): u128 {
    user.profit
}

#[test_only]
public fun get_user_info_owner<T, S>(user: &UserInfo<T, S>): address {
    user.owner
}

#[test_only]
public fun get_user_info_last_accrue_weight<T, S>(user: &UserInfo<T, S>): u128 {
    user.deposited_token.last_accrue_weight
}

#[test_only]
public fun get_user_info_shares_balance<T, S>(user: &UserInfo<T, S>): u128 {
    user.deposited_token.shares_balance
}

#[test_only]
public fun get_user_info_mint_allowance<T, S>(user: &UserInfo<T, S>): u128 {
    user.deposited_token.mint_allowance
}

#[test_only]
public fun yt_config_active_balance<T, S>(minter: &Minter<S>): u128 {
    let tname = type_name::get<T>();
    let yt = table::borrow(&minter.ytc, tname);
    yt.active_balance
}

#[test_only]
public fun yt_config_harvestable_balance<T, S>(minter: &Minter<S>): u128 {
    let tname = type_name::get<T>();
    let yt = table::borrow(&minter.ytc, tname);
    yt.harvestable_balance
}

#[test_only]
public fun yt_config_total_shares<T, S>(minter: &Minter<S>): u128 {
    let tname = type_name::get<T>();
    let yt = table::borrow(&minter.ytc, tname);
    yt.total_shares
}

#[test_only]
public fun yt_config_expected_value<T, S>(minter: &Minter<S>): u128 {
    let tname = type_name::get<T>();
    let yt = table::borrow(&minter.ytc, tname);
    yt.expected_value
}

#[test_only]
public fun yt_config_pending_credit<T, S>(minter: &Minter<S>): u128 {
    let tname = type_name::get<T>();
    let yt = table::borrow(&minter.ytc, tname);
    yt.pending_credit
}


#[test_only]
public fun yt_config_distributed_credit<T, S>(minter: &Minter<S>): u128 {
    let tname = type_name::get<T>();
    let yt = table::borrow(&minter.ytc, tname);
    yt.distributed_credit
}

#[test_only]
public fun yt_config_last_distribution<T, S>(minter: &Minter<S>): u128 {
    let tname = type_name::get<T>();
    let yt = table::borrow(&minter.ytc, tname);
    yt.last_distribution as u128
}

#[test_only]
public fun yt_config_accrued_weight<T, S>(minter: &Minter<S>): u128 {
    let tname = type_name::get<T>();
    let yt = table::borrow(&minter.ytc, tname);
    yt.accrued_weight
}

