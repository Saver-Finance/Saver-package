module saver::mock_adapter;

use saver::mock::{Self, Vault as MockVault};
use saver::redeem_pool::{Self, Config as RedeemPoolConfig, Vault as RedeemPoolVault};
use saver::limiter::{Self, Limiter, LimiterAccessCap, LimiterConfig};
use saver::insurance_pool::{Self, InsurancePool};
use saver::saver::{Self, AdapterCap, Config, UserInfo, Vault, Minter, KeeperCap};
use saver::error::{unAuthorize, freezeVault};
use std::option;
use one::clock::Clock;
use one::coin::{Self, Coin};



public struct AdapterConfig has key {
    id: UID,
    adapter_cap: AdapterCap,
    admin: address,
}

public struct UnderlyingToken<phantom U, phantom T, phantom S> has key {
    id: UID,
    enable: bool,
    decimals: u8,
    dt_decimals: u8,
    limiter: Limiter,
    limiter_cap: LimiterAccessCap,
}

public struct LiquidateLimiter<phantom U, phantom T, phantom S> has key {
    id: UID,
    limiter: Limiter,
}

public fun create_adapter_config(config: &Config, ctx: &mut TxContext) {
    let new_adapter_cap = saver::take_adapter_cap(config, ctx); // only admin in saver
    let new_adapter_config = AdapterConfig {
        id: object::new(ctx),
        adapter_cap: new_adapter_cap,
        admin : ctx.sender()
    };
    transfer::share_object(new_adapter_config);
}

public fun snap<U, T, S>(
    _ut: &UnderlyingToken<U, T, S>, 
    config: &AdapterConfig,
    minter: &mut Minter<S>,
    mock_vault: &MockVault<U, T>,
    ctx: &TxContext
) {
    assert!(ctx.sender() == config.admin, 0);
    let price = get_price(mock_vault);
    saver::snap<T, S>(
        &config.adapter_cap,
        minter,
        price
    );
}

public fun create_underlying_token_object<U, T, S>(
    config: &AdapterConfig, 
    limiter_config: &LimiterConfig,
    decimals: u8, 
    dt_decimals: u8,
    maximum: u128,
    min_limit: u128,
    duration: u128,
    clock: &Clock,
    ctx: &mut TxContext, 
) {
    let sender = ctx.sender();
    assert!(sender == config.admin, unAuthorize());
    let new_underlying = UnderlyingToken<U, T, S> {
        id: object::new(ctx),
        enable: true,
        decimals,
        dt_decimals,
        limiter: limiter::create_linear_grow_limiter(maximum, duration, min_limit, limiter_config, clock, ctx),
        limiter_cap: limiter::take_limiter_access_cap(limiter_config, ctx)

    };
    transfer::share_object(new_underlying);
}

public fun create_liquidate_limiter<U, T, S>(
    config: &AdapterConfig,
    limiter_config: &LimiterConfig,
    maximum: u128,
    min_limit: u128,
    duration: u128,
    clock: &Clock,
    ctx: &mut TxContext, 
) {
    let sender = ctx.sender();
    assert!(sender == config.admin, unAuthorize());
    let new_limiter =  LiquidateLimiter<U, T, S> {
        id: object::new(ctx),
        limiter: limiter::create_linear_grow_limiter(maximum, duration, min_limit, limiter_config, clock, ctx),
    };
    transfer::share_object(new_limiter);
}

public fun poke<U, T, S>(
    config: &AdapterConfig,
    minter: &mut Minter<S>,
    user_info: &mut UserInfo<T, S>,
    clock: &Clock,
    mock_vault: &MockVault<U, T>,
) {
    let price = get_price(mock_vault);
    saver::poke(
        &config.adapter_cap,
        minter,
        user_info,
        clock,
        price
    );
}

public fun deposit<U, T, S>(
    config: &AdapterConfig, 
    token_in: Coin<T>,
    user_info: &mut UserInfo<T, S>, 
    vault: &mut Vault<T>, 
    minter: &mut Minter<S>,
    clock: &Clock,
    mock_vault: &MockVault<U, T>
) {
    let price = get_price(mock_vault);
    saver::deposit(
        &config.adapter_cap,
        token_in,
        price,
        user_info,
        vault,
        minter,
        clock,
  
    );
}

public fun deposit2<U, T, S>(
    config: &AdapterConfig, 
    token_in: Coin<T>,
    user_info: Option<UserInfo<T, S>>, 
    vault: &mut Vault<T>, 
    minter: &mut Minter<S>,
    clock: &Clock,
    mock_vault: &MockVault<U, T>,
    ctx: &mut TxContext
) {
    let price = get_price(mock_vault);
    saver::deposit2(
        &config.adapter_cap,
        token_in,
        price,
        user_info,
        vault,
        minter,
        clock,
        ctx
    );
}

public fun deposit_underlying<U, T, S>(
    ut: &UnderlyingToken<U, T, S>, 
    config: &AdapterConfig, 
    token_in: Coin<U>, 
    user_info: &mut UserInfo<T, S>,
    vault: &mut Vault<T>,
    minter: &mut Minter<S>,
    clock: &Clock,
    mock_vault:&mut MockVault<U, T>,
    ctx: &mut TxContext
) {
    assert!(ut.enable == true, freezeVault());
    let yt_coin = wrap<U, T>(token_in, mock_vault, ctx);
    let price = get_price(mock_vault);
    saver::deposit(
        &config.adapter_cap,
        yt_coin,
        price,
        user_info,
        vault,
        minter,
        clock,
  
    );
}

public fun deposit_underlying2<U, T, S>(
    ut: &UnderlyingToken<U, T, S>, 
    config: &AdapterConfig, 
    token_in: Coin<U>, 
    user_info: Option<UserInfo<T, S>>,
    vault: &mut Vault<T>,
    minter: &mut Minter<S>,
    clock: &Clock,
    mock_vault:&mut MockVault<U, T>,
    ctx: &mut TxContext
) {
    assert!(ut.enable == true, freezeVault());
    let yt_coin = wrap<U, T>(token_in, mock_vault, ctx);
    let price = get_price(mock_vault);
    saver::deposit2(
        &config.adapter_cap,
        yt_coin,
        price,
        user_info,
        vault,
        minter,
        clock,
        ctx
    );
}


public fun withdraw<U, T, S>(    
    ut: &UnderlyingToken<U, T ,S>,
    config: &AdapterConfig,
    vault: &mut Vault<T>,
    user_info: &mut UserInfo<T, S>,
    minter: &mut Minter<S>,
    clock: &Clock,
    shares: u64,
    recipient: address,
    mock_vault: &MockVault<U, T>,
    ctx: &mut TxContext
) {
    assert!(ut.enable == true, freezeVault());
    let price = get_price(mock_vault);
    let conversion_factor = 10u128.pow(ut.dt_decimals - ut.decimals);
    let coin_to_withdraw = saver::withdraw(
        &config.adapter_cap,
        vault,
        user_info,
        minter,
        clock,
        shares as u128,
        price,
        conversion_factor,
        ctx
    );
    transfer::public_transfer(coin_to_withdraw, recipient);
}

public fun withdraw_underlying<U, T, S>(
    ut: &UnderlyingToken<U, T ,S>,
    config: &AdapterConfig,
    vault: &mut Vault<T>,
    user_info: &mut UserInfo<T, S>,
    minter: &mut Minter<S>,
    clock: &Clock,
    shares: u64,
    recipient: address,
    mock_vault: &mut MockVault<U, T>,
    ctx: &mut TxContext
) {
    assert!(ut.enable == true, freezeVault());
    let price = get_price(mock_vault);
    let conversion_factor = 10u128.pow(ut.dt_decimals - ut.decimals);
    let coin_to_unwrap = saver::withdraw(
        &config.adapter_cap,
        vault,
        user_info,
        minter,
        clock,
        shares as u128,
        price,
        conversion_factor,
        ctx
    );

    let yt_coin = unwrap(coin_to_unwrap, mock_vault, ctx);
    transfer::public_transfer(yt_coin, recipient);
}

public fun mint<U, T, S>(
    ut: &UnderlyingToken<U, T ,S>,
    config: &AdapterConfig,
    user_info: &mut UserInfo<T, S>,
    minter: &mut Minter<S>,
    clock: &Clock,
    amount: u64,
    recipient: address,
    mock_vault: &MockVault<U, T>,
    ctx: &mut TxContext,
) {
    assert!(ut.enable == true, freezeVault());
    let price = get_price(mock_vault);
    let conversion_factor = 10u128.pow(ut.dt_decimals - ut.decimals);
    saver::mint(
        &config.adapter_cap,
        user_info,
        minter,
        clock,
        amount,
        price,
        recipient,
        conversion_factor,
        ctx
    );
}

public fun burn<T, S>(
    config: &AdapterConfig,
    user_info: &mut UserInfo<T, S>,
    token: Coin<S>,
    minter: &mut Minter<S>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    //let price = get_price();
    saver::burn(
        &config.adapter_cap,
        user_info,
        token,
        minter,
        clock,
        ctx
    );
}

#[allow(lint(self_transfer))]
public fun repay<U, T, S>(     
    config: &AdapterConfig,
    ut: &mut UnderlyingToken<U, T ,S>,
    mut token: Coin<U>,
    user_info: &mut UserInfo<T, S>,
    minter: &mut Minter<S>,
    clock: &Clock,
    rp_config: &RedeemPoolConfig,
    rp_vault: &mut RedeemPoolVault<U, S>,
    mock_vault: &MockVault<U, T>,
    ctx: &mut TxContext
) {
    let amount = coin::value(&token);
    let price = get_price(mock_vault);
    let conversion_factor = 10u128.pow(ut.dt_decimals - ut.decimals);
    let amount_to_repay = saver::repay(
        &config.adapter_cap,
        amount,
        user_info,
        minter,
        clock,
        price,
        conversion_factor,
        &mut ut.limiter,
        &ut.limiter_cap
    );
 

    
    if(amount_to_repay < amount) {
        let coin_to_repay = coin::split(&mut token, amount_to_repay, ctx);
        redeem_pool::donate(rp_config, coin_to_repay, rp_vault);
        transfer::public_transfer(token, ctx.sender());
    }
    else {
        redeem_pool::donate(rp_config, token, rp_vault);
    }
}

public fun liquidate<U, T, S> (
    config: &AdapterConfig,
    ut: &mut UnderlyingToken<U, T ,S>,
    user_info: &mut UserInfo<T, S>,
    minter: &mut Minter<S>,
    vault: &mut Vault<T>,
    clock: &Clock,
    shares: u128, 
    liquidation_limiter: &mut LiquidateLimiter<U, T, S>,
    minimum_amount_out: u128,
    mock_vault: &mut MockVault<U, T>,
    rp_config: &RedeemPoolConfig,
    rp_vault: &mut RedeemPoolVault<U, S>,
    ctx: &mut TxContext
) {
    let price = get_price(mock_vault);
    let conversion_factor = 10u128.pow(ut.dt_decimals - ut.decimals);
    let (amount_ut, yt_coin) = saver::liquidate(
        &config.adapter_cap,
        user_info,
        minter,
        vault,
        clock,
        price,
        shares,
        conversion_factor,
        minimum_amount_out,
        ctx
    );
    let limiter = &mut liquidation_limiter.limiter;
    let liquidation_limit = limiter::get(limiter, clock);
    assert!(amount_ut as u128 <= liquidation_limit, 0);
    limiter::decrease(&ut.limiter_cap, limiter, clock, amount_ut as u128);
    let ut_coin = unwrap<U, T>(yt_coin, mock_vault, ctx);
    assert!(coin::value(&ut_coin) >= amount_ut as u64, 0);
    redeem_pool::donate(rp_config, ut_coin, rp_vault);
}

public fun harvest<U, T, S>(
    config: &AdapterConfig,
    ut: &UnderlyingToken<U, T ,S>,
    _: &KeeperCap,
    minter: &mut Minter<S>,
    vault: &mut Vault<T>,
    clock: &Clock,
    minimum_amount_out: u128,
    rp_config: &RedeemPoolConfig,
    rp_vault: &mut RedeemPoolVault<U, S>,
    mock_vault: &mut MockVault<U, T>,
    ctx: &mut TxContext
) {
    let price = get_price(mock_vault);
    let conversion_factor = 10u128.pow(ut.dt_decimals - ut.decimals);
    let (distribute_amount, fee, fee_receiver, unwrap_coin) = saver::harvest<T, S>(
        &config.adapter_cap,
        _,
        minter,
        clock,
        vault,
        price,
        minimum_amount_out,
        conversion_factor,
        ctx
    );

    let mut ut_coin = unwrap<U, T>(unwrap_coin, mock_vault, ctx);
    assert!(coin::value(&ut_coin) as u128 >= distribute_amount + fee, 0);
    let coin_to_fee_receiver = coin::split(&mut ut_coin, fee as u64, ctx);
    transfer::public_transfer(coin_to_fee_receiver, fee_receiver);
    
    redeem_pool::donate(rp_config, ut_coin, rp_vault);
}

public fun harvest_to_pool<U, T, S>(
    config: &AdapterConfig,
    ut: &mut UnderlyingToken<U, T ,S>,
    _: &KeeperCap,
    minter: &mut Minter<S>,
    vault: &mut Vault<T>,
    clock: &Clock,
    minimum_amount_out: u128,
    rp_config: &RedeemPoolConfig,
    rp_vault: &mut RedeemPoolVault<U, S>,
    insurance_pool: &mut InsurancePool<U>,
    mock_vault: &mut MockVault<U, T>,
    ctx: &mut TxContext
) {
    let price = mock::price(mock_vault);
    let conversion_factor = 10u128.pow(ut.dt_decimals - ut.decimals);
    let (distribute_amount, fee, _, unwrap_coin) = saver::harvest<T, S>(
        &config.adapter_cap,
        _,
        minter,
        clock,
        vault,
        price,
        minimum_amount_out,
        conversion_factor,
        ctx
    );

    let mut ut_coin = unwrap<U, T>(unwrap_coin, mock_vault, ctx);
    assert!(coin::value(&ut_coin) as u128 >= distribute_amount + fee, 0);
    
    let coin_to_fee = coin::split(&mut ut_coin, fee as u64, ctx);
    insurance_pool::deposit_fee(insurance_pool, coin_to_fee);
    
    redeem_pool::donate(rp_config, ut_coin, rp_vault);
}


// TODO: Implement get_price function to get price between yield token and underlying token
fun get_price<U, T>(vault: &MockVault<U, T>): u128 {
    mock::price(vault)
}

// TODO: implement this function to convert underlying token into yield token 
// this function must return a coin<YT> object
fun wrap<U, T>(
    token: Coin<U>,
    vault:&mut MockVault<U, T>,
    ctx: &mut TxContext
): Coin<T>{
    mock::deposit(vault, token, ctx)
}


fun unwrap<U, T>(
    token: Coin<T>,
    vault:&mut MockVault<U, T>,
    ctx: &mut TxContext
): Coin<U> {
    mock::withdraw(vault, token, ctx)
}


