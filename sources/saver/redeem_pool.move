module saver::redeem_pool;

use one::coin::{Self, Coin};
use one::balance::{Self, Balance};
use one::transfer::{Self};
use std::u128::{min, max};
use one::object::{Self, UID};
use one::tx_context::{Self, TxContext};

public struct Account<phantom U, phantom S> has key {
    id: UID,
    owner: address,
    unexchanged_balance: u128, // S decimals
    exchange_balance: u128, // U decimals
    entry_weight: u128
}

public struct Config has key {
    id: UID,
    admin: address,
    is_paused: bool
}

public struct Vault<phantom U, phantom S> has key {
    id: UID,
    ut_balance: Balance<U>,
    dt_balance: Balance<S>,
    total_unexchange: u128, // S decimals
    total_buffer: u128, // U deciamls
    accumulated_weight: u128, // S decimals
    conversion_factor: u128,
}

const ONE: u128 = 1000000000000000000;


fun init(ctx: &mut TxContext) {
    let admin = ctx.sender();
    let config = Config {
        id: object::new(ctx),
        admin: admin,
        is_paused: false
    };
    transfer::share_object(config);
}

public fun create_vault<U, D>(
    config: &Config,
    ut_decimals: u8,
    dt_decimals: u8,
    ctx: &mut TxContext
) {
    let sender = ctx.sender();
    assert!(sender == config.admin, 0);
    let new_vault = Vault<U, D> {
        id: object::new(ctx),
        ut_balance: balance::zero<U>(),
        dt_balance: balance::zero<D>(),
        total_unexchange: 0,
        total_buffer: 0,
        accumulated_weight: 0,
        conversion_factor: 10u128.pow(dt_decimals - ut_decimals)
    };
    transfer::share_object(new_vault);
}

public fun create_account<U, S>(
    config: &Config,
    vault: &Vault<U, S>,
    ctx: &mut TxContext
) {
    assert!(config.is_paused == false, 0);
    let sender = ctx.sender();
    let new_account = Account<U, S> {
        id: object::new(ctx),
        owner: sender,
        unexchanged_balance: 0,
        exchange_balance: 0,
        entry_weight: vault.accumulated_weight,
    };
    transfer::transfer(new_account, sender);
}

public fun deposit<U, S>(
    config: &Config,
    token: Coin<S>,
    account: &mut Account<U, S>,
    vault: &mut Vault<U, S>,
) {
    assert!(!config.is_paused, 0);
    let amount = coin::value(&token) as u128;
    assert!(amount > 0, 0);
    i_sync(account, vault);

    account.unexchanged_balance = account.unexchanged_balance + amount;
    vault.total_unexchange = vault.total_unexchange + amount;
    
    let coin_balance = coin::into_balance(token);
    balance::join(&mut vault.dt_balance, coin_balance);

    // TODO: emit event;
}

public fun poke<U, S>(
    account: &mut Account<U, S>,
    vault: &mut Vault<U, S>
) {
    i_sync(account, vault);
}

public fun withdraw<U, S>(
    account: &mut Account<U, S>,
    vault: &mut Vault<U, S>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext
) {
    assert!(amount > 0, 0);
    i_sync(account, vault);
    assert!(account.unexchanged_balance >= amount as u128, 0);
    account.unexchanged_balance = account.unexchanged_balance - (amount as u128);
    vault.total_unexchange = vault.total_unexchange - (amount as u128);

    //TODO: emit event
    let withdraw_balance = balance::split(&mut vault.dt_balance, amount);
    let token = coin::from_balance(withdraw_balance, ctx);
    transfer::public_transfer(token, recipient);
}

public fun claim<U, S>(
    account: &mut Account<U, S>,
    vault: &mut Vault<U, S>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext
) {
    assert!(amount > 0, 0);
    i_sync(account, vault);
    assert!(account.exchange_balance >= amount as u128, 0);
    //let amount_dt = i_normalize_ut_to_dt(amount as u128, vault.conversion_factor);
    account.exchange_balance = account.exchange_balance - (amount as u128);
    let claim_balance = balance::split(&mut vault.ut_balance, amount);
    //let burn_balance = balance::split(&mut vault.dt_balance, amount_dt as u64);
    let claim_ut = coin::from_balance(claim_balance, ctx);
    transfer::public_transfer(claim_ut, recipient);
}

public fun donate<U, S>(
    config: &Config,
    token: Coin<U>,
    vault: &mut Vault<U, S>,
) {
    assert!(!config.is_paused, 0);
    let amount = coin::value(&token) as u128;
    assert!(amount > 0, 0);
    let new_ut = coin::into_balance(token);
    balance::join(&mut vault.ut_balance, new_ut);

    if(vault.total_unexchange == 0) {
        vault.total_buffer = vault.total_buffer + amount;
        return;
    };
    
    let amount_dt = i_normalize_ut_to_dt(amount + vault.total_buffer, vault.conversion_factor);
    vault.accumulated_weight = vault.accumulated_weight + amount_dt * ONE / vault.total_unexchange;
    vault.total_buffer = 0;
}

fun i_sync<U, S>(
    account: &mut Account<U, S>,
    vault: &mut Vault<U, S>
) {
    let current_weight = vault.accumulated_weight;
    if(account.unexchanged_balance == 0) {
        account.entry_weight = current_weight;
        return;
    };
    let weight_diff = current_weight - account.entry_weight;
    if(weight_diff == 0) {
        return;
    };

    let total_to_exchanged = weight_diff * (account.unexchanged_balance as u128) / ONE;
    if(total_to_exchanged >= account.unexchanged_balance as u128) {
        let excess_amount = total_to_exchanged - (account.unexchanged_balance as u128);
        vault.total_buffer = vault.total_buffer + i_normalize_dt_to_ut(excess_amount, vault.conversion_factor);
    };
    let credit = min(total_to_exchanged, account.unexchanged_balance as u128);
    account.exchange_balance = account.exchange_balance + i_normalize_dt_to_ut(credit as u128, vault.conversion_factor);
    account.unexchanged_balance = account.unexchanged_balance - credit;
    vault.total_unexchange = vault.total_unexchange - (credit as u128);
    account.entry_weight = vault.accumulated_weight;
}

fun i_normalize_ut_to_dt(
    amount_ut: u128,
    conversion_factor: u128,
): u128 {
    (amount_ut as u128) * conversion_factor
}

fun i_normalize_dt_to_ut(
    amount_dt: u128,
    conversion_factor: u128,
): u128 {
    (amount_dt as u128) / conversion_factor
}

#[test_only]
public fun get_vault_ut_balance<U, S>(vault: &Vault<U, S>): u64 {
    balance::value(&vault.ut_balance) 
}

#[test_only]
public fun get_vault_dt_balance<U, S>(vault: &Vault<U, S>): u64 {
    balance::value(&vault.dt_balance) 
}

#[test_only]
public fun get_vault_total_unexchange<U, S>(vault: &Vault<U, S>): u128 {
    vault.total_unexchange
}

#[test_only]
public fun get_vault_total_buffer<U, S>(vault: &Vault<U, S>): u128 {
    vault.total_buffer
}

#[test_only]
public fun get_vault_accumulated_weight<U, S>(vault: &Vault<U, S>): u128 {
    vault.accumulated_weight
}

#[test_only]
public fun get_account_info<U, S>(account: &Account<U, S>): (address, u128, u128, u128) {
    (account.owner, account.unexchanged_balance, account.exchange_balance, account.entry_weight)
}

#[test_only]
public fun test_init(ctx: &mut TxContext) {
    let admin = ctx.sender();
    let config = Config {
        id: object::new(ctx),
        admin: admin,
        is_paused: false
    };
    transfer::share_object(config);
}

