module saver::redeem_pool;

use one::coin::{Self, Coin};
use one::balance::{Self, Balance};
use saver::saver::{Self, Minter};


public struct Config has key {
    id: UID,
    admin: address,
    is_paused: bool
}

public struct Vault<phantom U, phantom S> has key {
    id: UID,
    ut_balance: Balance<U>,
    conversion_factor: u128,
}


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
        conversion_factor: 10u128.pow(dt_decimals - ut_decimals)
    };
    transfer::share_object(new_vault);
}

public fun redeem<U, S>(
    config: &Config,
    vault: &mut Vault<U, S>,
    coin_to_redeem: Coin<S>,
    minter: &mut Minter<S>,
    recipient: address,
    ctx: &mut TxContext
) {
    assert!(!config.is_paused, 0);
    let amount_to_redeem = coin::value(&coin_to_redeem) as u128;
    saver::burn_token(coin_to_redeem, minter);
    let amount_to_receive = i_normalize_dt_to_ut(amount_to_redeem, vault.conversion_factor);
    assert!(amount_to_receive as u64 <= balance::value(&vault.ut_balance), 0);
    let split_balance = balance::split(&mut vault.ut_balance, amount_to_receive as u64);
    let coin_receive = coin::from_balance(split_balance, ctx);
    transfer::public_transfer(coin_receive, recipient);
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
public fun test_init(ctx: &mut TxContext) {
    let admin = ctx.sender();
    let config = Config {
        id: object::new(ctx),
        admin: admin,
        is_paused: false
    };
    transfer::share_object(config);
}

