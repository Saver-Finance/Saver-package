module saver::limiter;


use saver::error::{invalidDuration, invalidMaximum, unAuthorize};
use std::u128::{min, max};
use one::tx_context::{Self, TxContext};
use one::transfer::{Self};
use one::clock::{Self, Clock};
use one::object::{Self, UID};

public struct LimiterConfig has key {
    id: UID,
    admin: address
}

public struct Limiter has key, store {
    id: UID,
    maximum: u128,
    rate: u128,
    last_value: u128,
    last_udpate_time: u64,
    min_limit: u128
}

public struct LimiterAccessCap has key, store {
    id: UID,
}

const COOLDOWN_TIME: u128 = 86400; //TODO: Set a suitable cooldown time
const FIXED_POINT_SCALAR: u128 = 1000000000000000000;

fun init(ctx: &mut TxContext) {
    let sender = ctx.sender();
    let config = LimiterConfig {
        id: object::new(ctx),
        admin: sender
    };
    transfer::transfer(config, sender);
}
#[test_only]
public fun test_init(ctx: &mut TxContext) {
    let sender = ctx.sender();
    let config = LimiterConfig {
        id: object::new(ctx),
        admin: sender
    };
    transfer::share_object(config);
}

public fun create_linear_grow_limiter(
    maximum: u128, 
    duration: u128,
    min_limit: u128,
    config: &LimiterConfig,
    clock: &Clock,
    ctx: &mut TxContext
): Limiter {
    assert!(config.admin == ctx.sender(), unAuthorize());
    assert!(duration <= COOLDOWN_TIME, invalidDuration());
    assert!(maximum >= min_limit, invalidMaximum());
    let new_limiter = Limiter {
        id: object::new(ctx),
        maximum,
        rate : maximum * FIXED_POINT_SCALAR / duration,
        last_value: maximum,
        last_udpate_time: clock::timestamp_ms(clock),
        min_limit
    };
    new_limiter
}

public fun configure(config: &LimiterConfig, limiter: &mut Limiter, maximum: u128, duration: u128, ctx: &TxContext) {
    assert!(config.admin == ctx.sender(), unAuthorize());
    assert!(duration <= COOLDOWN_TIME, invalidDuration());
    assert!(maximum >= limiter.min_limit, invalidMaximum());
    limiter.last_value = max(limiter.last_value, maximum);
    limiter.maximum = maximum;
    limiter.rate = maximum * FIXED_POINT_SCALAR / duration;
}

public fun update(
    _: &LimiterAccessCap,
    limiter: &mut Limiter,
    clock: &Clock
) {
    limiter.last_value = get(limiter, clock);
    limiter.last_udpate_time = clock::timestamp_ms(clock);
}

public fun decrease(
    _: &LimiterAccessCap,
    limiter: &mut Limiter,
    clock: &Clock,
    amount: u128,
) {
    let value = get(limiter, clock);
    limiter.last_value = value - (amount as u128);
    limiter.last_udpate_time = clock::timestamp_ms(clock);
}

public fun increase(
    _: &LimiterAccessCap,
    limiter: &mut Limiter,
    clock: &Clock,
    amount: u128,
) {
    let value = get(limiter, clock);
    //assert!(value + (amount as u128) <= limiter.maximum, 0);
    limiter.last_value = value + (amount as u128); 
    limiter.last_udpate_time = clock::timestamp_ms(clock);
}

public fun get(limiter: &Limiter, clock: &Clock): u128 {
    let elapsed = clock::timestamp_ms(clock) - limiter.last_udpate_time;
    if(elapsed == 0) {
        return limiter.last_value;
    };
    let delta_num: u256 = (elapsed as u256) * (limiter.rate as u256);
    let delta = (delta_num / (FIXED_POINT_SCALAR as u256)) as u128; // always <= u128 because delta always <= u(64 + 128);
    let value = limiter.last_value + delta;
    min(value, limiter.maximum)
}

public fun take_limiter_access_cap(config: &LimiterConfig, ctx: &mut TxContext): LimiterAccessCap {
    assert!(config.admin == ctx.sender(), unAuthorize());
    let new_cap = LimiterAccessCap {
        id: object::new(ctx)
    };
    new_cap
}