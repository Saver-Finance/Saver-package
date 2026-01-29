module saver::ayoct;


use one::coin::{Self, TreasuryCap, Coin};
use one::tx_context::{Self, TxContext};
use one::transfer::{Self};
use one::oct::{OCT};
use one::balance::{Self, Balance};

public struct AYOCT has drop {}



fun init(witness: AYOCT, ctx: &mut TxContext) {
    let admin = ctx.sender();
    let (treasury_cap, metadata) = coin::create_currency(
        witness,
        9,
        b"AYOCT",
        b"AYOCT",
        b"None",
        option::none(),
        ctx
    );
    transfer::public_transfer(treasury_cap, admin);
    transfer::public_transfer(metadata, admin);
}

#[test_only]
public fun test_init(ctx: &mut TxContext) {
    let witness = AYOCT{};
    init(witness, ctx)
}