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

#[test_only]
module gamehub::gamehub_tests {
    use gamehub::gamehub::{Self, GameRegistry, Config, Room, AdminCap, GameCap};
    use one::test_scenario::{Self, next_tx, ctx, Scenario};
    use one::coin::{Self, Coin};
    use one::oct::OCT;

    public struct ROCK_PAPER_SCISSORS {}

    const ADMIN: address = @0xA;
    const PLAYER_1: address = @0xB;
    const PLAYER_2: address = @0xC;
    const INSURANCE: address = @0xD;
    const ENTRY_FEE: u64 = 10_000_000_000;

    // --- Helpers ---

    fun init_test_state(scenario: &mut Scenario) {
        // 1. Init
        gamehub::init_for_testing(ctx(scenario));

        // 2. Register Game & Update Config
        next_tx(scenario, ADMIN);
        {
            let mut registry = test_scenario::take_shared<GameRegistry>(scenario);
            let mut config = test_scenario::take_shared<Config>(scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);

            gamehub::update_config(&mut config, &admin_cap, 100, INSURANCE, 0);
            let game_cap = gamehub::register_game<ROCK_PAPER_SCISSORS>(
                &mut registry, 
                &admin_cap, 
                b"Rock Paper Scissors", 
                ctx(scenario)
            );

            test_scenario::return_shared(registry);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(scenario, admin_cap);
            transfer::public_transfer(game_cap, ADMIN);
        };

        // 3. Create Room
        next_tx(scenario, ADMIN);
        {
            let registry = test_scenario::take_shared<GameRegistry>(scenario);
            let config = test_scenario::take_shared<Config>(scenario);
            let creation_fee = coin::mint_for_testing<OCT>(0, ctx(scenario));
            
            gamehub::create_room<OCT, ROCK_PAPER_SCISSORS>(
                &registry, 
                &config, 
                ENTRY_FEE, 
                2, 
                creation_fee, 
                ctx(scenario)
            );

            test_scenario::return_shared(registry);
            test_scenario::return_shared(config);
        };
    }

    fun join_room_helper(scenario: &mut Scenario, player: address) {
        next_tx(scenario, player);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(scenario);
            gamehub::join_room(&mut room, ctx(scenario));
            test_scenario::return_shared(room);
        };
    }

    fun ready_helper(scenario: &mut Scenario, player: address, amount: u64) {
        next_tx(scenario, player);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(scenario);
            let coin = coin::mint_for_testing<OCT>(amount, ctx(scenario));
            gamehub::ready_to_play(&mut room, coin, ctx(scenario));
            test_scenario::return_shared(room);
        };
    }

    fun start_room_helper(scenario: &mut Scenario) {
        next_tx(scenario, ADMIN);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);
            let config = test_scenario::take_shared<Config>(scenario);
            gamehub::start_room(&mut room, &admin_cap, &config, ctx(scenario));
            test_scenario::return_shared(room);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(scenario, admin_cap);
        };
    }

    fun settle_helper(scenario: &mut Scenario, players: vector<address>, amounts: vector<u64>) {
        next_tx(scenario, ADMIN);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(scenario);
            let game_cap = test_scenario::take_from_sender<GameCap>(scenario);
            gamehub::settle(&mut room, players, amounts, &game_cap, ctx(scenario));
            test_scenario::return_shared(room);
            test_scenario::return_to_sender(scenario, game_cap);
        };
    }

    // --- Tests ---

    #[test]
    fun test_game_flow_with_ready_mechanism() {
        let mut scenario = test_scenario::begin(ADMIN);
        init_test_state(&mut scenario);

        // Player 1 joins (no fee yet)
        join_room_helper(&mut scenario, PLAYER_1);

        // Player 1 signals ready (pays 2x entry fee for OCT)
        ready_helper(&mut scenario, PLAYER_1, ENTRY_FEE * 2);

        // Player 2 joins and readies
        join_room_helper(&mut scenario, PLAYER_2);
        ready_helper(&mut scenario, PLAYER_2, ENTRY_FEE * 2);

        // Admin starts game
        start_room_helper(&mut scenario);

        // Admin settles (Player 1 wins remaining pool)
        // Pool was 20 OCT, 10% fee = 2 OCT to insurance, remaining = 18 OCT
        settle_helper(&mut scenario, vector[PLAYER_1, PLAYER_2], vector[18_000_000_000, 0]);

        // Verify Player 1 balance
        next_tx(&mut scenario, PLAYER_1);
        {
            let expected_balance = 18_000_000_000;
            let coin = test_scenario::take_from_sender<Coin<OCT>>(&scenario);
            assert!(coin::value(&coin) == expected_balance, 0);
            test_scenario::return_to_sender(&scenario, coin);
        };

        // Verify insurance pool received fee
        next_tx(&mut scenario, INSURANCE);
        {
            let expected_fee = 2_000_000_000;
            let coin = test_scenario::take_from_sender<Coin<OCT>>(&scenario);
            assert!(coin::value(&coin) == expected_fee, 1);
            test_scenario::return_to_sender(&scenario, coin);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_cancel_ready_refunds() {
        let mut scenario = test_scenario::begin(ADMIN);
        init_test_state(&mut scenario);

        join_room_helper(&mut scenario, PLAYER_1);
        ready_helper(&mut scenario, PLAYER_1, ENTRY_FEE * 2);

        // Verify pool has entry fee
        next_tx(&mut scenario, PLAYER_1);
        {
            let room = test_scenario::take_shared<Room<OCT>>(&scenario);
            assert!(gamehub::get_pool_value(&room) == ENTRY_FEE, 0);
            test_scenario::return_shared(room);
        };

        // Cancel ready
        next_tx(&mut scenario, PLAYER_1);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            gamehub::cancel_ready(&mut room, ctx(&mut scenario));
            assert!(gamehub::get_pool_value(&room) == 0, 1);
            test_scenario::return_shared(room);
        };

        // Verify Refund
        next_tx(&mut scenario, PLAYER_1);
        {
            let coin = test_scenario::take_from_sender<Coin<OCT>>(&scenario);
            assert!(coin::value(&coin) == ENTRY_FEE, 2);
            test_scenario::return_to_sender(&scenario, coin);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 13)] // ENotAllPlayersReady
    fun test_start_fails_if_not_all_ready() {
        let mut scenario = test_scenario::begin(ADMIN);
        init_test_state(&mut scenario);

        join_room_helper(&mut scenario, PLAYER_1);
        ready_helper(&mut scenario, PLAYER_1, ENTRY_FEE * 2);

        join_room_helper(&mut scenario, PLAYER_2);
        // Player 2 does NOT ready

        start_room_helper(&mut scenario); // Should fail
        test_scenario::end(scenario);
    }

    #[test]
    fun test_re_ready_after_cancel() {
        let mut scenario = test_scenario::begin(ADMIN);
        init_test_state(&mut scenario);

        join_room_helper(&mut scenario, PLAYER_1);
        ready_helper(&mut scenario, PLAYER_1, ENTRY_FEE * 2);

        // Cancel
        next_tx(&mut scenario, PLAYER_1);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            gamehub::cancel_ready(&mut room, ctx(&mut scenario));
            test_scenario::return_shared(room);
        };

        // Re-ready
        ready_helper(&mut scenario, PLAYER_1, ENTRY_FEE * 2);

        // Verify pool
        next_tx(&mut scenario, PLAYER_1);
        {
            let room = test_scenario::take_shared<Room<OCT>>(&scenario);
            assert!(gamehub::get_pool_value(&room) == ENTRY_FEE, 0);
            test_scenario::return_shared(room);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 0)] // EFullPlayerInRoom
    fun test_join_fails_when_full() {
        let mut scenario = test_scenario::begin(ADMIN);
        init_test_state(&mut scenario);

        join_room_helper(&mut scenario, PLAYER_1);
        join_room_helper(&mut scenario, PLAYER_2);
        
        // Player 3 joins -> Fail (Max 2)
        join_room_helper(&mut scenario, @0xE);
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 11)] // EAlreadyReady
    fun test_ready_fails_if_already_ready() {
        let mut scenario = test_scenario::begin(ADMIN);
        init_test_state(&mut scenario);

        join_room_helper(&mut scenario, PLAYER_1);
        ready_helper(&mut scenario, PLAYER_1, ENTRY_FEE * 2);
        
        // Ready again -> Fail
        ready_helper(&mut scenario, PLAYER_1, ENTRY_FEE * 2);

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 12)] // ENotReady
    fun test_cancel_fails_if_not_ready() {
        let mut scenario = test_scenario::begin(ADMIN);
        init_test_state(&mut scenario);

        join_room_helper(&mut scenario, PLAYER_1);
        // Do NOT ready

        // Cancel -> Fail
        next_tx(&mut scenario, PLAYER_1);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            gamehub::cancel_ready(&mut room, ctx(&mut scenario));
            test_scenario::return_shared(room);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_leave_room() {
        let mut scenario = test_scenario::begin(ADMIN);
        init_test_state(&mut scenario);

        join_room_helper(&mut scenario, PLAYER_1);

        // Verify joined
        next_tx(&mut scenario, PLAYER_1);
        {
            let room = test_scenario::take_shared<Room<OCT>>(&scenario);
            assert!(gamehub::get_player_count(&room) == 1, 0);
            test_scenario::return_shared(room);
        };

        // Leave
        next_tx(&mut scenario, PLAYER_1);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            gamehub::leave_room(&mut room, ctx(&mut scenario));
            assert!(gamehub::get_player_count(&room) == 0, 1);
            test_scenario::return_shared(room);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 16)] // ECannotLeaveWhenReady
    fun test_leave_room_fails_if_ready() {
        let mut scenario = test_scenario::begin(ADMIN);
        init_test_state(&mut scenario);

        join_room_helper(&mut scenario, PLAYER_1);
        ready_helper(&mut scenario, PLAYER_1, ENTRY_FEE * 2);

        // Leave -> Fail
        next_tx(&mut scenario, PLAYER_1);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            gamehub::leave_room(&mut room, ctx(&mut scenario));
            test_scenario::return_shared(room);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_reset_room() {
        let mut scenario = test_scenario::begin(ADMIN);
        init_test_state(&mut scenario);

        join_room_helper(&mut scenario, PLAYER_1);
        ready_helper(&mut scenario, PLAYER_1, 20_000); // Small amount for manual check in test logic? No, must match ENTRY_FEE if not mocked properly, but helper handles it. Wait, helper uses ENTRY_FEE const unless passed.
        // In helper I used `amount` param.
        // The original test used 20_000, but ENTRY_FEE is 10_000_000_000.
        // Wait, original test step 5 used `10_000_000_000`.
        // But `test_reset_room` in original file used `20_000`? 
        // Let's check original file.
        // Lines 661-662: `let coin = coin::mint_for_testing<OCT>(20_000, ...)`
        // And creation fee was 10_000 in `create_room` call in that test?
        // Line 650: `gamehub::create_room<OCT, ...>(..., 10_000, ...)`
        // Ah, `test_reset_room` used different entry fee (10_000) than other tests (10_000_000_000).
        // My helper `init_test_state` uses `ENTRY_FEE` (10_000_000_000).
        // I should stick to `ENTRY_FEE` to be consistent with the helper.
        // So I should pass `ENTRY_FEE * 2` to ready helper.
        
        // Re-doing logic for this test to match helper's config
        // ENTRY_FEE is 10_000_000_000
        
        // 1. Join & Ready P1
        // (already joined above) - wait, I need to call ready.
        // I used `join_room_helper` above for P1.
        // Now ready P1.
        // NOTE: In `test_reset_room` I was starting fresh.
        // `init_test_state` does the setup.
        // So I just need to call join/ready for P1 and P2 using consistent constants.
        
        // Resetting scenario for clarity in this thought trace (I am writing the file content).
        // Back to writing code.
        
        // P1 Ready
        // NOTE: previous call to `join_room_helper` was P1.
        // I need to ready P1.
        ready_helper(&mut scenario, PLAYER_1, ENTRY_FEE * 2);
        
        // P2 Join & Ready
        join_room_helper(&mut scenario, PLAYER_2);
        ready_helper(&mut scenario, PLAYER_2, ENTRY_FEE * 2);

        // Start
        start_room_helper(&mut scenario);

        // Settle
        // Pool = 2 * ENTRY_FEE = 20_000_000_000
        // Settle expects amounts matching pool?
        // Wait, settle checks balance.
        // If settlement doesn't deduct fee, it just distributes.
        // `start_room` deducts insurance fee (10%).
        // Pool = 20e9. Fee = 2e9. Remaining = 18e9.
        // So amounts should sum to 18e9.
        settle_helper(&mut scenario, vector[PLAYER_1, PLAYER_2], vector[18_000_000_000, 0]);

        // Reset
        next_tx(&mut scenario, ADMIN);
        {
             let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
             let game_cap = test_scenario::take_from_sender<GameCap>(&scenario);
             gamehub::reset_room(&mut room, &game_cap, ctx(&mut scenario));
             
             assert!(gamehub::get_player_count(&room) == 0, 0);
             
             test_scenario::return_shared(room);
             test_scenario::return_to_sender(&scenario, game_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_update_config() {
        let mut scenario = test_scenario::begin(ADMIN);
        gamehub::init_for_testing(ctx(&mut scenario));
        
        next_tx(&mut scenario, ADMIN);
        {
            let mut config = test_scenario::take_shared<Config>(&scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            gamehub::update_config(&mut config, &admin_cap, 100, INSURANCE, 500);
            assert!(gamehub::get_room_creation_fee(&config) == 500, 0);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&scenario, admin_cap);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 9)] // EInsufficientPoolBalance
    fun test_settle_fails_incorrect_amounts() {
        let mut scenario = test_scenario::begin(ADMIN);
        init_test_state(&mut scenario);

        join_room_helper(&mut scenario, PLAYER_1);
        ready_helper(&mut scenario, PLAYER_1, ENTRY_FEE * 2);
        
        join_room_helper(&mut scenario, PLAYER_2);
        ready_helper(&mut scenario, PLAYER_2, ENTRY_FEE * 2);

        start_room_helper(&mut scenario);

        // Fail Settle: Try to payout more than remaining pool (18e9)
        settle_helper(&mut scenario, vector[PLAYER_1, PLAYER_2], vector[18_000_000_001, 0]);

        test_scenario::end(scenario);
    }
}

