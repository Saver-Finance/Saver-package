module gamehub::gamehub;

use one::object::{Self, UID};
use one::tx_context::{Self, TxContext};
use one::balance::{Self, Balance};
use one::transfer::{Self};
use one::coin::{Self, Coin};
use one::oct::OCT;
use std::string::{Self, String};
use one::table::{Self, Table};
use std::type_name::{Self, TypeName};

const FEE_RATE_DENOMINATOR: u64 = 1000; 
const MIN_ENTRY_FEE: u64 = 100; // Minimum entry fee to prevent 0-pool games

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
const EUnauthorizedGame: u64 = 10;
const EAlreadyReady: u64 = 11;
const ENotReady: u64 = 12;
const ENotAllPlayersReady: u64 = 13;
const EAlreadyJoined: u64 = 14;
const EInvalidCreationFee: u64 = 15;
const ECannotLeaveWhenReady: u64 = 16;
const EPoolNotEmpty: u64 = 17;
public enum Status has store, copy, drop {
    Waiting,
    Started,
    Cancelled,
    Settled
}

public struct AdminCap has key {
    id: UID,
}

public struct GameCap has key, store {
    id: UID,
    game_type: TypeName,
}

public struct GameRegistry has key {
    id: UID,
    registered_games: Table<TypeName, GameInfo>
}

public struct GameInfo has store, copy, drop {
    game_name: String,
}


public struct Config has key {
    id: UID,
    fee_rate: u64,
    insurance_pool: address,
    room_creation_fee: u64,
    whitelisted_tokens: Table<TypeName, bool>,
}

public struct Room<phantom T> has key {
    id: UID,
    game_type: TypeName,  
    creator: address,
    entry_fee: u64,
    max_players: u8,
    player_balances: Table<address, u64>,
    joined_players: vector<address>,
    pool: Balance<T>,
    status: Status,
    ready_players: Table<address, bool>,
}

fun init(
    ctx: &mut TxContext
) {
    let registry = GameRegistry { 
        id: object::new(ctx), 
        registered_games : table::new(ctx)
    };
    transfer::share_object(registry);

    let mut config = Config {
        id: object::new(ctx),
        fee_rate: 0,
        insurance_pool: ctx.sender(),
        room_creation_fee: 0,
        whitelisted_tokens: table::new(ctx),
    };

    // Add OCT as default whitelisted token
    table::add(&mut config.whitelisted_tokens, type_name::with_defining_ids<OCT>(), true);

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
    _: &AdminCap,
    game_name: vector<u8>,
    ctx: &mut TxContext,
): GameCap {
    let game_type = type_name::with_defining_ids<G>();

    assert!(!is_game_registered(registry, game_type), EGameAlreadyRegistered);

    let info = GameInfo {
        game_name: string::utf8(game_name),
    };

    table::add(&mut registry.registered_games, game_type, info);

    // Return GameCap for this game
    GameCap {
        id: object::new(ctx),
        game_type,
    }
}

public fun create_room_internal<T, G>(
    registry: &GameRegistry,
    config: &Config,
    entry_fee: u64,
    max_players: u8,
    mut creation_fee: Coin<T>,
    ctx: &mut TxContext
) {
    let game_type = type_name::with_defining_ids<G>();

    assert!(is_game_registered(registry, game_type), EGameNotRegistered);

    // Validate minimum entry fee to prevent 0-pool games
    assert!(entry_fee >= MIN_ENTRY_FEE, EInvalidEntryFee);

    // Validate and split creation fee - refund excess
    let fee_value = coin::value(&creation_fee);
    if (config.room_creation_fee > 0) {
        assert!(fee_value >= config.room_creation_fee, EInvalidCreationFee);

        // Split coin: keep room_creation_fee, refund excess
        if (fee_value > config.room_creation_fee) {
            let refund = coin::split(&mut creation_fee, fee_value - config.room_creation_fee, ctx);
            transfer::public_transfer(refund, tx_context::sender(ctx));
        };
    };

    // Transfer exact creation fee to insurance pool
    transfer::public_transfer(creation_fee, config.insurance_pool);

    let room = Room<T> {
        id: object::new(ctx),
        game_type,
        creator: tx_context::sender(ctx),
        entry_fee,
        max_players,
        player_balances: table::new(ctx),
        joined_players: vector::empty(),
        pool: balance::zero<T>(),
        status: Status::Waiting,
        ready_players: table::new(ctx),
    };
    transfer::share_object(room);
}


public fun leave_room_internal<T>(
    room: &mut Room<T>,
    ctx: &TxContext
) {
    let user = ctx.sender();

    assert!(room.status == Status::Waiting, ERoomNotWaiting);
    assert!(table::contains(&room.player_balances, user), EPlayerNotFound);
    let is_ready = *table::borrow(&room.ready_players, user);

assert!(!is_ready, EAlreadyReady); 

let _ = table::remove(&mut room.player_balances, user);
let _ = table::remove(&mut room.ready_players, user);

let mut i = 0;
let len = vector::length(&room.joined_players);
while (i < len) {
    if (*vector::borrow(&room.joined_players, i) == user) {
        vector::swap_remove(&mut room.joined_players, i);
        break;
    };
    i = i + 1;
}
}

public fun join_room_internal<T>(
    room: &mut Room<T>,
    ctx: &TxContext
) {
    assert!(room.status == Status::Waiting, ERoomNotWaiting);
    assert!(table::length(&room.player_balances) < (room.max_players as u64), EFullPlayerInRoom);

    let user = ctx.sender();

    // Check not already joined
    assert!(!table::contains(&room.player_balances, user), EAlreadyJoined);

    // Add player with 0 balance (not ready yet)
    table::add(&mut room.player_balances, user, 0);
    table::add(&mut room.ready_players, user, false);
    vector::push_back(&mut room.joined_players, user);
}

/// Signal ready and commit entry fee (escrow)
public fun ready_to_play_internal<T>(
    room: &mut Room<T>,
    mut coin: Coin<T>,
    ctx: &mut TxContext
) {
    let user = ctx.sender();
    
    assert!(room.status == Status::Waiting, ERoomNotWaiting);
    assert!(table::contains(&room.player_balances, user), EPlayerNotFound);

    // Check if it is OCT token for 50% rule
    if (type_name::with_defining_ids<T>() == type_name::with_defining_ids<OCT>()) {
        // For OCT, user must provide at least 2 * entry_fee to prove 50% balance
        assert!(coin::value(&coin) >= room.entry_fee * 2, EInsufficientPoolBalance);

        // Take entry fee
        let fee_coin = coin::split(&mut coin, room.entry_fee, ctx);
        room.pool.join(coin::into_balance(fee_coin));

        // Refund remaining
        transfer::public_transfer(coin, user);
    } else {
        // Normal token check
        assert!(coin::value(&coin) == room.entry_fee, EInvalidEntryFee);
        room.pool.join(coin::into_balance(coin));
    };

    assert!(!*table::borrow(&room.ready_players, user), EAlreadyReady);

    // Mark as ready
    *table::borrow_mut(&mut room.ready_players, user) = true;

    // Update balance to entry fee
    *table::borrow_mut(&mut room.player_balances, user) = room.entry_fee;
}

/// Cancel ready and get refund
public fun cancel_ready_internal<T>(
    room: &mut Room<T>,
    ctx: &mut TxContext
): Coin<T> {
    let user = ctx.sender();

    assert!(room.status == Status::Waiting, ERoomNotWaiting);
    assert!(table::contains(&room.ready_players, user), EPlayerNotFound);
    assert!(*table::borrow(&room.ready_players, user), ENotReady);

    // Unmark ready
    *table::borrow_mut(&mut room.ready_players, user) = false;

    // Get entry fee amount
    let amount = *table::borrow(&room.player_balances, user);
    assert!(amount > 0, ENothingToClaim);

    // Reset balance to 0
    *table::borrow_mut(&mut room.player_balances, user) = 0;

    // Refund from pool
    coin::from_balance(
        balance::split(&mut room.pool, amount),
        ctx
    )
}

/// Check if all players in room are ready
fun all_players_ready<T>(room: &Room<T>): bool {
    let player_count = table::length(&room.player_balances);

    // Check if pool equals expected total (entry_fee * player_count)
    let expected_pool = room.entry_fee * player_count;
    let actual_pool = balance::value(&room.pool);

    actual_pool == expected_pool
}

public fun start_room_internal<T> (
    room: &mut Room<T>,

    config: &Config,
    ctx: &mut TxContext,
) {
    assert!(room.status == Status::Waiting, ERoomCanNotStart);
    assert!(table::length(&room.player_balances) >= 2, ERoomCanNotStart);
    assert!(table::contains(&room.player_balances, ctx.sender()), EPlayerNotFound);

    // Check all players are ready
    assert!(all_players_ready(room), ENotAllPlayersReady);

    // Calculate and transfer insurance fee from pool
    let total_pool = balance::value(&room.pool);
    let insurance_fee = (total_pool * config.fee_rate) / FEE_RATE_DENOMINATOR;

    if (insurance_fee > 0) {
        let fee_coin = coin::from_balance(
            balance::split(&mut room.pool, insurance_fee),
            ctx
        );
        transfer::public_transfer(fee_coin, config.insurance_pool);
    };

    room.status = Status::Started;
}   

/// Settle game results - no fee calculation, just update balances
public fun settle_internal<T>(
    room: &mut Room<T>,
    addresses: vector<address>,
    amounts: vector<u64>,
    game_cap: &GameCap,
    ctx: &mut TxContext,
) {
    assert!(room.status == Status::Started, ERoomCanNotStart);
    assert!(room.game_type == game_cap.game_type, EUnauthorizedGame);

    let payouts_len = vector::length(&addresses);
    assert!(payouts_len == vector::length(&amounts), EInvalidEntryFee);


    let mut total_payout: u64 = 0;
    let mut i = 0;
    while (i < payouts_len) {
        total_payout = total_payout + *vector::borrow(&amounts, i);
        i = i + 1;
    };
    assert!(total_payout <= balance::value(&room.pool), EInsufficientPoolBalance);

    // update balances
    i = 0;
    while (i < payouts_len) {
        let addr = *vector::borrow(&addresses, i);
        let amount = *vector::borrow(&amounts, i);

        if (amount > 0) {
            let coin = coin::from_balance(
                balance::split(&mut room.pool, amount),
                ctx
            );
            transfer::public_transfer(coin, addr);
        };

        // Update balance to 0 as it is already paid
        if (!table::contains(&room.player_balances, addr)) {
            table::add(&mut room.player_balances, addr, 0);
        } else {
            let balance_ref = table::borrow_mut(&mut room.player_balances, addr);
            *balance_ref = 0;
        };

        i = i + 1;
    };

    room.status = Status::Settled;
}

/// Reset a settled room so everyone re-joins next round.
/// Must be called after settle_internal (pool must be 0).
entry fun reset_room<T>(
    room: &mut Room<T>,
    game_cap: &GameCap,
    _: &mut TxContext,
) {
    assert!(room.status == Status::Settled, ERoomNotSettled);
    assert!(room.game_type == game_cap.game_type, EUnauthorizedGame);
    assert!(balance::value(&room.pool) == 0, EPoolNotEmpty);

    let mut i = 0;
    let len = vector::length(&room.joined_players);
    while (i < len) {
        let addr = *vector::borrow(&room.joined_players, i);
        if (table::contains(&room.player_balances, addr)) {
            let _ = table::remove(&mut room.player_balances, addr);
        };
        if (table::contains(&room.ready_players, addr)) {
            let _ = table::remove(&mut room.ready_players, addr);
        };
        i = i + 1;
    };

    room.joined_players = vector::empty();
    room.status = Status::Waiting;
}

/// Get the current pool value for a room
public fun get_pool_value<T>(room: &Room<T>): u64 {
    balance::value(&room.pool)
}

/// Get room entry fee
public fun get_entry_fee<T>(room: &Room<T>): u64 {
    room.entry_fee
}

/// Get number of players in room
public fun get_player_count<T>(room: &Room<T>): u64 {
    table::length(&room.player_balances)
}

/// Get room max players
public fun get_max_players<T>(room: &Room<T>): u8 {
    room.max_players
}


entry fun update_config(
    config: &mut Config,
    _: &AdminCap,
    fee_rate: u64,
    insurance_pool: address,
    room_creation_fee: u64,
) {
    config.fee_rate = fee_rate;
    config.insurance_pool = insurance_pool;
    config.room_creation_fee = room_creation_fee;
}

entry fun add_whitelist<T>(
    config: &mut Config,
    _: &AdminCap,
    _ctx: &mut TxContext,
) {
    let type_name = type_name::with_defining_ids<T>();
    if (!table::contains(&config.whitelisted_tokens, type_name)) {
        table::add(&mut config.whitelisted_tokens, type_name, true);
    }
}

entry fun create_room<T, G>(
    registry: &GameRegistry,
    config: &Config,
    entry_fee: u64,
    max_players: u8,
    creation_fee: Coin<T>,
    ctx: &mut TxContext
) {
    create_room_internal<T, G>(registry, config, entry_fee, max_players, creation_fee, ctx);
}

entry fun join_room<T>(
    room: &mut Room<T>,
    ctx: &TxContext
) {
    join_room_internal(room, ctx);
}

entry fun leave_room<T>(
    room: &mut Room<T>,
    ctx: &TxContext
) {
    leave_room_internal(room, ctx);
}

entry fun ready_to_play<T>(
    room: &mut Room<T>,
    coin: Coin<T>,
    ctx: &mut TxContext
) {
    ready_to_play_internal(room, coin, ctx);
}

entry fun cancel_ready<T>(
    room: &mut Room<T>,
    ctx: &mut TxContext
) {
    let coin = cancel_ready_internal(room, ctx);
    transfer::public_transfer(coin, tx_context::sender(ctx));
}

entry fun start_room<T>(
    room: &mut Room<T>,

    config: &Config,
    ctx: &mut TxContext,
) {
    start_room_internal(room, config, ctx);
}

entry fun settle<T>(
    room: &mut Room<T>,
    addresses: vector<address>,
    amounts: vector<u64>,
    game_cap: &GameCap,
    ctx: &mut TxContext,
) {
    settle_internal(room, addresses, amounts, game_cap, ctx);
}

