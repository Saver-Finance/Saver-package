module saver::template_coin;

use one::coin::{Self};
use one::tx_context::{Self, TxContext};
use one::transfer;

public struct TEMPLATE_COIN has drop {}


fun init(witness: TEMPLATE_COIN, ctx: &mut TxContext) {
    let admin = ctx.sender();
    let (treasury_cap, metadata) = coin::create_currency(
        witness,
        9,
        b"tmp",
        b"Template",
        b"None",
        option::none(),
        ctx
    );
    transfer::public_transfer(treasury_cap, admin);
    transfer::public_transfer(metadata, admin);
}