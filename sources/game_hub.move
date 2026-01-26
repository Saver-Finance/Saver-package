
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

const EFullPlayerInRoom: u64 = 0;
const EInvalidEntryFee: u64 = 1;
const ERoomNotWaiting: u64 = 2;
const EGameNotRegistered: u64 = 3;
const EGameAlreadyRegistered: u64 = 4;
const ERoomCanNotStart: u64 = 5;
const EPlayerNotFound: u64 = 6;
// const ERoomNotSettled: u64 = 7;
const ENothingToClaim: u64 = 7;
const EUnauthorizedGame: u64 = 8;
const EAlreadyReady: u64 = 9;
const ENotReady: u64 = 10;
const ENotAllPlayersReady: u64 = 11;
const EAlreadyJoined: u64 = 12;
const EInvalidCreationFee: u64 = 13;
const EInsufficientPoolBalance: u64 = 14;

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
    creation_fee: Coin<T>,
    ctx: &mut TxContext
) {
    let game_type = type_name::with_defining_ids<G>();
    
    assert!(is_game_registered(registry, game_type), EGameNotRegistered);
    
    // Validate and transfer creation fee to insurance pool
    if (config.room_creation_fee > 0) {
        assert!(coin::value(&creation_fee) >= config.room_creation_fee, EInvalidCreationFee);
    };
    
    // Validate token is whitelisted
    assert!(table::contains(&config.whitelisted_tokens, type_name::with_defining_ids<T>()), EUnauthorizedGame);

    // Transfer creation fee to insurance pool (even if 0)
    transfer::public_transfer(creation_fee, config.insurance_pool);
    
    let room = Room<T> {
        id: object::new(ctx),
        game_type,
        creator: tx_context::sender(ctx),
        entry_fee,
        max_players,
        player_balances: table::new(ctx),
        pool: balance::zero<T>(),
        status: Status::Waiting,
        ready_players: table::new(ctx),
    };
    transfer::share_object(room);
}

/// Join room without paying entry fee (just add to player list)
public fun join_room_internal<T>(
    room: &mut Room<T>,
    ctx: &TxContext
) {
    assert!(room.status == Status::Waiting, ERoomNotWaiting);
    assert!(room.player_balances.length() as u8 < room.max_players, EFullPlayerInRoom);

    let user = ctx.sender();
    
    // Check not already joined
    assert!(!table::contains(&room.player_balances, user), EAlreadyJoined);
    
    // Add player with 0 balance (not ready yet)
    table::add(&mut room.player_balances, user, 0);
    table::add(&mut room.ready_players, user, false);
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
    // This works because pool = sum of all ready player entry fees
    let expected_pool = room.entry_fee * player_count;
    let actual_pool = balance::value(&room.pool);
    
    actual_pool == expected_pool
}

public fun start_room_internal<T> (
    room: &mut Room<T>,
    _: &AdminCap,
    config: &Config,
    ctx: &mut TxContext,
) {
    assert!(room.status == Status::Waiting || room.status == Status::Settled, ERoomCanNotStart);
    assert!(room.player_balances.length() >= 2, ERoomCanNotStart);
    
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
    
    // Direct transfer to users
    let mut i = 0;
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

// public fun claim_internal<T>(
//     room: &mut Room<T>,
//     ctx: &mut TxContext,
// ): Coin<T> {
//     let player = tx_context::sender(ctx);
    
//     assert!(room.status == Status::Settled, ERoomNotSettled);
    
//     assert!(
//         table::contains(&room.player_balances, player),
//         EPlayerNotFound
//     );
    
//     let amount = table::borrow_mut(&mut room.player_balances, player);
//     let pool_balance = balance::value(&room.pool);

//     assert!(*amount > 0, ENothingToClaim);
//     assert!(*amount <= pool_balance, EInsufficientPoolBalance);
    
//     let claim_amount = *amount;
//     *amount = 0u64;
    
//     // Return full balance (fees already deducted at start)
//     coin::from_balance(
//         balance::split(&mut room.pool, claim_amount),
//         ctx
//     )
// }

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
    admin_cap: &AdminCap,
    config: &Config,
    ctx: &mut TxContext,
) {
    start_room_internal(room, admin_cap, config, ctx);
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


// entry fun claim<T>(
//     room: &mut Room<T>,
//     ctx: &mut TxContext,
// ) {
//     let coin = claim_internal(room, ctx);
//     transfer::public_transfer(coin, tx_context::sender(ctx));
// }

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun get_room_creation_fee(config: &Config): u64 {
    config.room_creation_fee
}
