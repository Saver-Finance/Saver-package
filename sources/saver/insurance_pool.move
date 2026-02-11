module saver::insurance_pool;

use one::coin::{Self, Coin};
use one::balance::{Self, Balance};
use one::transfer;
use one::object::{Self, UID};
use one::tx_context::TxContext;

public struct InsurancePool<phantom U> has key {
    id: UID,
    reserve: Balance<U>,
    admin: address,
}

public fun create<U>(ctx: &mut TxContext) {
    let pool = InsurancePool<U> {
        id: object::new(ctx),
        reserve: balance::zero(),
        admin: ctx.sender()
    };
    transfer::share_object(pool);
}

public fun deposit_fee<U>(
    pool: &mut InsurancePool<U>,
    fee: Coin<U>,
) {
    let balance = coin::into_balance(fee);
    balance::join(&mut pool.reserve, balance);
}

/// Withdraw from insurance reserve to cover yield loss.
/// Returns Balance<U> (underlying token) — adapter must wrap U→T 
/// and call saver::deposit_to_vault() to top up the vault.
public fun cover_loss<U>(
    pool: &mut InsurancePool<U>,
    amount: u64,
): Balance<U> {
    balance::split(&mut pool.reserve, amount)
}

public fun withdraw_for_loss<U>(
     pool: &mut InsurancePool<U>,
     amount: u64,
     ctx: &mut TxContext
): Coin<U> {

    //Only modules/admins can withdraw.

    assert!(ctx.sender() == pool.admin, 0);
    
    let split = balance::split(&mut pool.reserve, amount);
    coin::from_balance(split, ctx)
}
