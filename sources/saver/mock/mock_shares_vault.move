module saver::mock;

use one::coin::{Self, TreasuryCap, Coin};
use one::balance::{Self, Balance};


public struct Vault<phantom U, phantom T> has key {
    id: UID,
    treasury: TreasuryCap<T>,
    oct_balance: Balance<U>,
    total_supply: u128,
    total_deposited: u128
}

public fun create_vault<U, T>(
    treasury: TreasuryCap<T>,
    ctx: &mut TxContext
) {
    let new_vault = Vault<U, T> {
        id: object::new(ctx),
        treasury,
        oct_balance: balance::zero<U>(),
        total_supply: 1000000000,
        total_deposited: 1000000000
    };
    transfer::share_object(new_vault);
}

public fun deposit<U, T>(
    vault: &mut Vault<U, T>,
    token: Coin<U>,
    ctx: &mut TxContext
): Coin<T> {
    let amount = coin::value(&token) as u128;
    let oct_balance = coin::into_balance(token);
    balance::join(&mut vault.oct_balance, oct_balance);
    let shares_receive = amount * vault.total_supply / vault.total_deposited;
    let coin_receive = coin::mint(&mut vault.treasury, shares_receive as u64, ctx);
    vault.total_supply = vault.total_supply + shares_receive;
    vault.total_deposited = vault.total_deposited + amount;
    coin_receive
}

public fun withdraw<U, T>(
    vault: &mut Vault<U, T>,
    share_coin: Coin<T>,
    ctx: &mut TxContext
): Coin<U> {
    let shares_amount = coin::value(&share_coin) as u128;
    let oct_receive = shares_amount * vault.total_deposited / vault.total_supply;
    //print(&oct_receive);
    vault.total_deposited = vault.total_deposited - oct_receive;
    vault.total_supply = vault.total_supply - shares_amount;
    let oct_balance = balance::split(&mut vault.oct_balance, oct_receive as u64);
    let oct_coin = coin::from_balance(oct_balance, ctx);
    coin::burn(&mut vault.treasury, share_coin);
    oct_coin
}

public fun donate<U, T>(
    vault: &mut Vault<U, T>,
    oct_coin: Coin<U>
){
    let oct_amount = coin::value(&oct_coin) as u128;
    vault.total_deposited = vault.total_deposited + oct_amount;
    let oct_balance = coin::into_balance(oct_coin);
    balance::join(&mut vault.oct_balance, oct_balance);
}

/// For testing purpose
/// We assume that underlying token and yield token has the same decimals which is 9
/// price of 1 T in term of U 
public fun price<U, T>(vault: &Vault<U, T>): u128 {
    if(vault.total_supply == 0) return 1;
    vault.total_deposited * 10u128.pow(9) / vault.total_supply
}

#[test_only]
public fun read_vault_info<U, T>(vault: &Vault<U, T>): (u128, u128, u128) {
    (balance::value(&vault.oct_balance) as u128, vault.total_deposited, vault.total_supply)
}