
module gamehub::gamehub;

use one::balance::Balance;
use one::balance;
use one::coin::{Self, Coin};
use std::string::{Self, String};
use one::table::{Self, Table};
use std::type_name::{Self, TypeName};

const FEE_RATE_DENOMINATOR: u64 = 1000; 

const EFullPlayerInRoom: u64 = 0;
const EInvalidEntryFee: u64 = 1;
const ERoomNotWaiting: u64 = 2;
const EGameNotRegistered: u64 = 3;
const EGameAlreadyRegistered: u64 = 4;
const ERoomCanNotStart: u64 = 5;
const EPlayerNotFound: u64 = 6;
const ERoomNotSettled: u64 = 7;
const ENothingToClaim: u64 = 8;
const EInsufficientPoolBalance: u64 = 9;

public enum Status has store, copy, drop {
    Waiting,
    Started,
    Cancelled,
    Settled
}

public struct AdminCap has key {
    id: UID
}

public struct GameRegistry has key {
    id: UID,
    registered_games: Table<TypeName, GameInfo>
}

public struct GameInfo has store, copy, drop {
    game_name: String,
}

public struct Payout has copy, drop {
    address: address,
    amount: u64,
}

public struct Config has key {
    id: UID,
    fee_rate: u64,
    insurance_pool: address,
}

public struct Room<phantom T> has key {
    id: UID,
    game_type: TypeName,  
    creator: address,
    entry_fee: u64,
    max_players: u8,

    player_balances: Table<address, u64>,
    pool: Balance<T>,

    status: Status
}

fun init(
    ctx: &mut TxContext
) {
    let registry = GameRegistry { 
        id: object::new(ctx), 
        registered_games : table::new(ctx)
    };
    transfer::share_object(registry);

    let config = Config {
        id: object::new(ctx),
        fee_rate: 0,
        insurance_pool: ctx.sender(),
    };
    transfer::share_object(config);

    transfer::transfer(
        AdminCap { id: object::new(ctx) },
        ctx.sender()
    );
}

public fun is_game_registered(registry: &GameRegistry, game_type: TypeName): bool {
    table::contains(&registry.registered_games, game_type)
}

public fun register_game<G>(
    registry: &mut GameRegistry,
    game_name: vector<u8>,
) {
    let game_type = type_name::with_defining_ids<G>();
    
    assert!(!is_game_registered(registry, game_type), EGameAlreadyRegistered);

    let info = GameInfo {
        game_name: string::utf8(game_name),
    };
    
    table::add(&mut registry.registered_games, game_type, info);
}

public fun create_room_internal<T, G>(
    registry: &GameRegistry,
    entry_fee: u64,
    max_players: u8,
    ctx: &mut TxContext
) {
    let game_type = type_name::with_defining_ids<G>();
    
    assert!(is_game_registered(registry, game_type), EGameNotRegistered);
    
    let room = Room<T> {
        id: object::new(ctx),
        game_type,
        creator: tx_context::sender(ctx),
        entry_fee,
        max_players,
        player_balances: table::new(ctx),
        pool: balance::zero<T>(),
        status: Status::Waiting
    };
    transfer::share_object(room);
}

public fun join_room_internal<T>(
    room: &mut Room<T>,
    coin: Coin<T>,
    ctx: &TxContext
) {
    assert!(room.status == Status::Waiting, ERoomNotWaiting);
    assert!(room.player_balances.length() as u8 < room.max_players, EFullPlayerInRoom);
    assert!(coin::value(&coin) == room.entry_fee, EInvalidEntryFee);

    let user = ctx.sender();
    room.player_balances.add(user, coin.value());

    room.pool.join(coin::into_balance(coin));
}

public fun start_room_internal<T> (
    room: &mut Room<T>,
    _: &AdminCap,
) {
    assert!(room.status == Status::Waiting || room.status == Status::Settled, ERoomCanNotStart);
    room.status = Status::Started;
}   

public fun settle_internal<T>(
    room: &mut Room<T>,
    payouts: vector<Payout>,
    _: &AdminCap,
) {
    assert!(room.status == Status::Started, ERoomCanNotStart);

    let mut i = 0;
    while (i < vector::length(&payouts)) {
        let payout = vector::borrow(&payouts, i);

        assert!(
            table::contains(&room.player_balances, payout.address),
            EPlayerNotFound
        );

        let balance_ref =
            table::borrow_mut(&mut room.player_balances, payout.address);

        *balance_ref = payout.amount;

        i = i + 1;
    };

    room.status = Status::Settled;
}

public fun claim_internal<T>(
    config: &Config,
    room: &mut Room<T>,
    ctx: &mut TxContext,
): Coin<T> {
    let player = tx_context::sender(ctx);
    
    assert!(room.status == Status::Settled, ERoomNotSettled);
    
    assert!(
        table::contains(&room.player_balances, player),
        EPlayerNotFound
    );
    
    let amount = table::borrow_mut(&mut room.player_balances, player);
    let pool_balance = balance::value(&room.pool);

    assert!(*amount > 0, ENothingToClaim);

    assert!(*amount <= pool_balance, EInsufficientPoolBalance);

    let fee_amount = (*amount * config.fee_rate) / FEE_RATE_DENOMINATOR;
    let claim_amount = *amount - fee_amount;
    *amount = 0u64;
    
    let fee_coin = coin::from_balance(
        balance::split(&mut room.pool, fee_amount),
        ctx
    );
    transfer::public_transfer(fee_coin, config.insurance_pool);
    
    coin::from_balance(
        balance::split(&mut room.pool, claim_amount),
        ctx
    )
}

entry fun update_config(
    config: &mut Config,
    _: &AdminCap,
    fee_rate: u64,
    insurance_pool: address,
) {
    config.fee_rate = fee_rate;
    config.insurance_pool = insurance_pool;
}

entry fun create_room<T, G>(
    registry: &GameRegistry,
    entry_fee: u64,
    max_players: u8,
    ctx: &mut TxContext
) {
    create_room_internal<T, G>(registry, entry_fee, max_players, ctx);
}

entry fun join_room<T>(
    room: &mut Room<T>,
    coin: Coin<T>,
    ctx: &TxContext
) {
    join_room_internal(room, coin, ctx);
}

entry fun start_room<T>(
    room: &mut Room<T>,
    admin_cap: &AdminCap,
) {
    start_room_internal(room, admin_cap);
}

entry fun settle<T>(
    room: &mut Room<T>,
    addresses: vector<address>,
    amounts: vector<u64>,
    _: &AdminCap,
) {
    let payouts_len = vector::length(&addresses);
    assert!(payouts_len == vector::length(&amounts), EInvalidEntryFee);
    
    let mut payouts = vector::empty<Payout>();
    let mut i = 0;
    while (i < payouts_len) {
        vector::push_back(&mut payouts, Payout {
            address: *vector::borrow(&addresses, i),
            amount: *vector::borrow(&amounts, i),
        });
        i = i + 1;
    };
    
    settle_internal(room, payouts, _);
}


entry fun claim<T>(
    config: &Config,
    room: &mut Room<T>,
    ctx: &mut TxContext,
) {
    let coin = claim_internal(config, room, ctx);
    transfer::public_transfer(coin, tx_context::sender(ctx));
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}
