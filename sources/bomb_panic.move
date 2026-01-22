#[allow(lint(public_entry), lint(public_random))]
module games::bomb_panic;

use one::clock::{Self, Clock};
use one::event;
use one::random::{Self, Random};
use std::string::{Self, String};

/// Basis points denominator.
const BPS_DENOM: u64 = 10_000;
/// Default flat explosion probability per second (300 bps = 3%)
const DEFAULT_EXPLOSION_RATE_BPS: u64 = 300;
/// Max time a single player can hold the bomb (anti-camping).
const MAX_HOLD_TIME_MS: u64 = 10_000;
/// Sticky hands threshold - after this many ms, passing becomes risky
const STICKY_HANDS_THRESHOLD_MS: u64 = 30_000;

/// Error codes.
const E_WRONG_PHASE: u64 = 1;
const E_TOO_MANY_PLAYERS: u64 = 2;
const E_NOT_HOLDER: u64 = 3;
const E_NO_ALIVE_PLAYERS: u64 = 4;
const E_ALREADY_JOINED: u64 = 5;
const E_SETTLEMENT_CONSUMED: u64 = 7;
const E_POOL_EMPTY: u64 = 8;
const E_NOT_JOINED: u64 = 9;
const E_SETTLEMENT_NOT_CONSUMED: u64 = 10;
const E_NOT_ENOUGH_PLAYERS: u64 = 11;

/// Phase enum for round lifecycle.
public enum GamePhase has copy, drop, store {
    Waiting,
    Playing,
    Ended,
}

/// Minimal hub reference binding.
public struct GameHubRef has copy, drop, store {
    id: object::ID,
}

/// Player in a round.
public struct Player has copy, drop, store {
    addr: address,
    alive: bool,
}

/// Holder reward record.
public struct HolderReward has copy, drop, store {
    player: address,
    amount: u64,
}

/// Settlement intent produced after round ends.
public struct SettlementIntent has drop, store {
    round_id: u64,
    dead_player: address,
    survivors: vector<address>,
    survivor_payout_each: u64,
    holder_rewards: vector<HolderReward>,
    remaining_pool_value: u64,
}
/// Round settled event.
public struct RoundSettled has copy, drop, store {
    round_id: u64,
    dead_player: address,
    survivors: vector<address>,
    survivor_payout_each: u64,
    holder_rewards: vector<HolderReward>,
    remaining_pool_value: u64,
}

/// Core game state (one per coin type).
public struct GameState<phantom T> has key, store {
    id: object::UID,
    name: String,
    phase: GamePhase,
    round_id: u64,
    players: vector<Player>,
    pool_value: u64,
    entry_fee: u64, // Configured entry fee per player
    entry_fee_per_player: u64, // Actual fee calculated at start_round (usually equals entry_fee)
    bomb_holder: option::Option<address>,
    holder_start_ms: u64,
    holder_rewards: vector<HolderReward>,
    settlement_consumed: bool,
    hub_ref: GameHubRef,
    current_room_id: option::Option<object::ID>,
    round_start_ms: u64,
    // Config
    max_players: u64,
    reward_per_sec: u64, // Fixed reward amount per second (pool/60)
    explosion_rate_bps: u64, // Flat explosion probability in basis points (default 300 = 3%)
}

/// Events.
public struct GameCreated has copy, drop, store {
    game_id: object::ID,
    creator: address,
    name: String,
    entry_fee: u64,
    max_players: u64,
}

public struct RoundStarted has copy, drop, store {
    round_id: u64,
    bomb_holder: address,
    pool_value: u64,
}

public struct BombPassed has copy, drop, store {
    round_id: u64,
    from: address,
    to: address,
    reward_paid_to_from: u64,
    now_ms: u64,
    pool_value_after: u64,
}

public struct BombPassFailed has copy, drop, store {
    round_id: u64,
    holder: address,
    reason: String,
    now_ms: u64,
}

public struct Exploded has copy, drop, store {
    round_id: u64,
    dead_player: address,
    now_ms: u64,
    pool_value_after: u64,
}

public struct PlayerExited has copy, drop, store {
    round_id: u64,
    player: address,
    phase: GamePhase,
}

public struct Victory has copy, drop, store {
    round_id: u64,
    winner: address,
    now_ms: u64,
    pool_value: u64,
}

public struct GameReset has copy, drop, store {
    game_id: object::ID,
}

/// Create game state bound to hub.
public fun create_game_state<T>(
    hub_ref: GameHubRef,
    name: String,
    entry_fee: u64,
    max_players: u64,
    ctx: &mut one::tx_context::TxContext,
): GameState<T> {
    GameState {
        id: object::new(ctx),
        name,
        phase: GamePhase::Waiting,
        round_id: 0,
        players: vector::empty<Player>(),
        pool_value: 0,
        entry_fee,
        entry_fee_per_player: 0,
        bomb_holder: option::none(),
        holder_start_ms: 0,
        holder_rewards: vector::empty<HolderReward>(),
        settlement_consumed: false,
        hub_ref,
        current_room_id: option::none(),
        round_start_ms: 0,
        max_players,
        reward_per_sec: 0, // Will be calculated at start_round
        explosion_rate_bps: DEFAULT_EXPLOSION_RATE_BPS,
    }
}

/// Initialize and share a new game state (for testing/deployment).
public entry fun initialize_game<T>(
    hub_id: address,
    name: vector<u8>,
    entry_fee: u64,
    max_players: u64,
    ctx: &mut one::tx_context::TxContext,
) {
    let hub_ref = GameHubRef { id: object::id_from_address(hub_id) };
    let name_str = string::utf8(name);
    let game = create_game_state<T>(hub_ref, name_str, entry_fee, max_players, ctx);

    event::emit(GameCreated {
        game_id: object::id(&game),
        creator: one::tx_context::sender(ctx),
        name: name_str,
        entry_fee,
        max_players,
    });

    transfer::share_object(game);
}

/// Join a round (Waiting phase only).
public entry fun join<T>(game: &mut GameState<T>, ctx: &mut one::tx_context::TxContext) {
    assert!(is_waiting(&game.phase), E_WRONG_PHASE);
    assert!(vector::length(&game.players) < game.max_players, E_TOO_MANY_PLAYERS);

    let player_addr = one::tx_context::sender(ctx);
    let idx_opt = find_player_index(&game.players, player_addr);
    assert!(option::is_none(&idx_opt), E_ALREADY_JOINED);

    vector::push_back(
        &mut game.players,
        Player {
            addr: player_addr,
            alive: true,
        },
    );
}

/// Leave the game.
/// - In Waiting: Removes player from list.
/// - In Playing: Marks player as dead (forfeit). If they held the bomb, it triggers an explosion.
public entry fun leave<T>(
    game: &mut GameState<T>,
    clock: &Clock,
    ctx: &mut one::tx_context::TxContext,
) {
    let sender = one::tx_context::sender(ctx);
    let idx_opt = find_player_index(&game.players, sender);
    assert!(option::is_some(&idx_opt), E_NOT_JOINED);
    let idx = *option::borrow(&idx_opt);

    if (is_waiting(&game.phase)) {
        vector::remove(&mut game.players, idx);
    } else if (is_playing(&game.phase)) {
        let player = vector::borrow_mut(&mut game.players, idx);
        if (player.alive) {
            player.alive = false;

            // If the exiting player is the bomb holder, explode immediately.
            let current_holder = *option::borrow(&game.bomb_holder);
            if (sender == current_holder) {
                perform_explosion(game, clock);
            };
        };
    };

    event::emit(PlayerExited {
        round_id: game.round_id,
        player: sender,
        phase: game.phase,
    });
}

/// Start round with pool value from room, random bomb holder.
public entry fun start_round<T>(
    rng: &Random,
    game: &mut GameState<T>,
    room_id: address,
    clock: &Clock,
    pool_value: u64,
    ctx: &mut one::tx_context::TxContext,
) {
    assert!(is_waiting(&game.phase), E_WRONG_PHASE);
    assert!(vector::length(&game.players) > 1, E_NOT_ENOUGH_PLAYERS);
    assert!(pool_value > 0, E_POOL_EMPTY);

    // Validate that pool matches the fixed entry fee per player
    let player_count = vector::length(&game.players);
    let expected_pool = game.entry_fee * player_count;
    assert!(pool_value == expected_pool, E_POOL_EMPTY); // Reusing error code for invalid pool

    // Store current room ID
    game.current_room_id = option::some(object::id_from_address(room_id));

    // Select random initial bomb holder.
    let initial_holder = select_random_player(rng, &game.players, ctx);

    let now_ms = clock::timestamp_ms(clock);

    // Initialize round state.
    game.round_id = game.round_id + 1;
    game.pool_value = pool_value;

    // Use the fixed entry fee (not calculated from pool)
    game.entry_fee_per_player = game.entry_fee;

    // Calculate fixed reward per second (pool / 60)
    game.reward_per_sec = pool_value / 60;

    game.bomb_holder = option::some(initial_holder);
    game.holder_start_ms = now_ms;
    game.round_start_ms = now_ms;
    game.holder_rewards = vector::empty<HolderReward>();
    game.settlement_consumed = false;
    game.phase = GamePhase::Playing;

    event::emit(RoundStarted {
        round_id: game.round_id,
        bomb_holder: initial_holder,
        pool_value,
    });
}

/// Pass bomb to random next holder (only current holder can call).
public entry fun pass_bomb<T>(
    rng: &Random,
    game: &mut GameState<T>,
    clock: &Clock,
    ctx: &mut one::tx_context::TxContext,
) {
    assert!(is_playing(&game.phase), E_WRONG_PHASE);

    let sender = one::tx_context::sender(ctx);
    let current_holder = *option::borrow(&game.bomb_holder);
    assert!(sender == current_holder, E_NOT_HOLDER);

    let now_ms = clock::timestamp_ms(clock);

    // Check for Max Hold Time Violation
    if (now_ms > game.holder_start_ms && (now_ms - game.holder_start_ms > MAX_HOLD_TIME_MS)) {
        // Player held too long! Force explosion immediately.
        perform_explosion(game, clock);
        return
    };

    // Calculate reward for current holder.
    let duration_ms = if (now_ms > game.holder_start_ms) {
        now_ms - game.holder_start_ms
    } else {
        0
    };
    let reward = calculate_holder_reward(
        game.reward_per_sec,
        game.pool_value,
        duration_ms,
    );

    // Deduct reward from pool.
    game.pool_value = if (game.pool_value > reward) {
        game.pool_value - reward
    } else {
        0
    };

    // Record reward.
    add_holder_reward(&mut game.holder_rewards, current_holder, reward);

    // Sticky Hands Mechanic: After 30s elapsed, 50% chance to fail pass (Danger Zone)
    let elapsed_ms = if (now_ms > game.round_start_ms) {
        now_ms - game.round_start_ms
    } else {
        0
    };

    if (elapsed_ms > STICKY_HANDS_THRESHOLD_MS) {
        let mut generator = random::new_generator(rng, ctx);
        // 50% chance to fail the pass
        if (random::generate_bool(&mut generator)) {
            event::emit(BombPassFailed {
                round_id: game.round_id,
                holder: current_holder,
                reason: string::utf8(b"Sticky Hands"),
                now_ms,
            });
            // Update reward time only, but keep bomb
            game.holder_start_ms = now_ms;
            return
        };
    };

    // Check for Victory (Pool Drained)
    if (game.pool_value == 0) {
        perform_victory(game, clock);
        return
    };

    // Select random next holder (excluding current holder).
    let next_holder = select_random_alive_player(rng, &game.players, current_holder, ctx);

    // Update bomb holder.
    game.bomb_holder = option::some(next_holder);
    game.holder_start_ms = now_ms;

    event::emit(BombPassed {
        round_id: game.round_id,
        from: current_holder,
        to: next_holder,
        reward_paid_to_from: reward,
        now_ms,
        pool_value_after: game.pool_value,
    });
}

/// Helper to execute the actual explosion logic (payouts, phase change)
fun perform_explosion<T>(game: &mut GameState<T>, clock: &Clock) {
    let now_ms = clock::timestamp_ms(clock);
    let current_holder = *option::borrow(&game.bomb_holder);

    // Calculate final reward for holder before explosion.
    let duration_ms = if (now_ms > game.holder_start_ms) {
        now_ms - game.holder_start_ms
    } else {
        0
    };
    let reward = calculate_holder_reward(
        game.reward_per_sec,
        game.pool_value,
        duration_ms,
    );

    // Deduct reward from pool.
    game.pool_value = if (game.pool_value > reward) {
        game.pool_value - reward
    } else {
        0
    };

    // Record reward.
    add_holder_reward(&mut game.holder_rewards, current_holder, reward);

    // Mark holder as dead.
    let holder_idx_opt = find_player_index(&game.players, current_holder);
    if (option::is_some(&holder_idx_opt)) {
        let holder_idx = *option::borrow(&holder_idx_opt);
        let player_ref = vector::borrow_mut(&mut game.players, holder_idx);
        player_ref.alive = false;
    };

    // End round.
    game.phase = GamePhase::Ended;
    game.bomb_holder = option::none();

    event::emit(Exploded {
        round_id: game.round_id,
        dead_player: current_holder,
        now_ms,
        pool_value_after: game.pool_value,
    });
}

/// Helper to execute victory logic (Pool drained, no explosion - everyone survives)
fun perform_victory<T>(game: &mut GameState<T>, clock: &Clock) {
    let now_ms = clock::timestamp_ms(clock);

    // Just end the game peacefully
    // Everyone keeps their holder rewards (which total 100% of pool)
    // Everyone is alive (no one died since there was no explosion)
    // Pool is already 0

    game.phase = GamePhase::Ended;
    game.bomb_holder = option::none();

    event::emit(Victory {
        round_id: game.round_id,
        winner: @0x0, // No single winner - everyone survived
        now_ms,
        pool_value: 0, // Pool is empty
    });
}

/// Attempt to explode the bomb based on flat probabilistic check.
/// Backend should call this approximately once per second.
public entry fun try_explode<T>(
    game: &mut GameState<T>,
    clock: &Clock,
    rng: &Random,
    ctx: &mut one::tx_context::TxContext,
) {
    // Already ended, no-op.
    if (is_ended(&game.phase)) return;

    assert!(is_playing(&game.phase), E_WRONG_PHASE);

    let now_ms = clock::timestamp_ms(clock);

    // Check if held too long- Force explode
    if (now_ms > game.holder_start_ms && (now_ms - game.holder_start_ms > MAX_HOLD_TIME_MS)) {
        perform_explosion(game, clock);
        return
    };

    // Flat explosion probability per check (default 3%)
    let mut generator = random::new_generator(rng, ctx);
    let roll = random::generate_u64_in_range(&mut generator, 0, 10000); // 0-9999

    if (roll < game.explosion_rate_bps) {
        perform_explosion(game, clock);
    } else if (game.pool_value == 0) {
        // No explosion but pool is empty? Victory!
        perform_victory(game, clock);
    }
}

/// Consume settlement intent (once per round, after Ended).
public fun consume_settlement_intent<T>(game: &mut GameState<T>): SettlementIntent {
    assert!(is_ended(&game.phase), E_WRONG_PHASE);
    assert!(!game.settlement_consumed, E_SETTLEMENT_CONSUMED);

    game.settlement_consumed = true;

    // Find dead player and survivors.
    let mut dead_player = @0x0;
    let mut survivors = vector::empty<address>();
    let len = vector::length(&game.players);
    let mut i = 0;
    while (i < len) {
        let player = vector::borrow(&game.players, i);
        if (player.alive) {
            vector::push_back(&mut survivors, player.addr);
        } else {
            dead_player = player.addr;
        };
        i = i + 1;
    };

    // Calculate equal payout per survivor from remaining pool.
    let survivor_count = vector::length(&survivors);
    let survivor_payout_each = if (survivor_count > 0) {
        game.pool_value / survivor_count
    } else {
        0
    };

    SettlementIntent {
        round_id: game.round_id,
        dead_player,
        survivors,
        survivor_payout_each,
        holder_rewards: game.holder_rewards,
        remaining_pool_value: game.pool_value,
    }
}

/// Get settlement data for backend to call gamehub settle
/// Returns (addresses, amounts, pool_value) for settlement
public fun get_settlement_data<T>(game: &GameState<T>): (vector<address>, vector<u64>, u64) {
    assert!(is_ended(&game.phase), E_WRONG_PHASE);
    assert!(!game.settlement_consumed, E_SETTLEMENT_CONSUMED);

    let mut survivors = vector::empty<address>();
    let len = vector::length(&game.players);
    let mut i = 0;
    while (i < len) {
        let player = vector::borrow(&game.players, i);
        if (player.alive) {
            vector::push_back(&mut survivors, player.addr);
        };
        i = i + 1;
    };

    // Calculate survivor payout
    let survivor_count = vector::length(&survivors);
    let survivor_payout_each = if (survivor_count > 0) {
        game.pool_value / survivor_count
    } else {
        0
    };

    // Build payout vectors (combine survivors + holder rewards)
    let mut addrs = vector::empty<address>();
    let mut amts = vector::empty<u64>();

    // Add survivor payouts
    i = 0;
    while (i < survivor_count) {
        let addr = *vector::borrow(&survivors, i);
        vector::push_back(&mut addrs, addr);
        vector::push_back(&mut amts, survivor_payout_each);
        i = i + 1;
    };

    // Add holder rewards (merge if player already in list)
    let rewards = &game.holder_rewards;
    i = 0;
    while (i < vector::length(rewards)) {
        let reward = vector::borrow(rewards, i);
        let player = reward.player;
        let amount = reward.amount;

        // Find if player already in addrs
        let mut found_idx: option::Option<u64> = option::none();
        let mut j = 0;
        while (j < vector::length(&addrs)) {
            if (*vector::borrow(&addrs, j) == player) {
                found_idx = option::some(j);
                break
            };
            j = j + 1;
        };

        if (option::is_some(&found_idx)) {
            // Add to existing amount
            let idx = *option::borrow(&found_idx);
            let amt_ref = vector::borrow_mut(&mut amts, idx);
            *amt_ref = *amt_ref + amount;
        } else {
            // New entry
            vector::push_back(&mut addrs, player);
            vector::push_back(&mut amts, amount);
        };

        i = i + 1;
    };

    (addrs, amts, game.pool_value)
}

/// Prepare the game for the next round or allow dead players to rejoin.
/// - Removes dead players from the list (they must rejoin/pay again).
/// - Keeps survivors in the list (they stay for the next round).
/// - Resets phase to Waiting so more players can join or round can restart.
public entry fun reset_game<T>(game: &mut GameState<T>) {
    assert!(is_ended(&game.phase), E_WRONG_PHASE);
    assert!(game.settlement_consumed, E_SETTLEMENT_NOT_CONSUMED);

    // Keep only alive players for the next round.
    let mut survivors = vector::empty<Player>();
    let len = vector::length(&game.players);
    let mut i = 0;
    while (i < len) {
        let player = vector::borrow(&game.players, i);
        if (player.alive) {
            vector::push_back(&mut survivors, *player);
        };
        i = i + 1;
    };
    game.players = survivors;

    game.phase = GamePhase::Waiting;
    game.pool_value = 0;
    game.current_room_id = option::none();
    game.bomb_holder = option::none();
    game.holder_start_ms = 0;
    game.round_start_ms = 0;
    game.holder_rewards = vector::empty();
    game.settlement_consumed = false;

    event::emit(GameReset {
        game_id: object::id(game),
    });
}

/// Calculate reward for holder based on time held.
/// Formula: reward = reward_per_sec * elapsed_sec
/// reward_per_sec is fixed at (initial_pool / 60)
fun calculate_holder_reward(reward_per_sec: u64, pool_remaining: u64, duration_ms: u64): u64 {
    // Convert ms to seconds.
    let elapsed_sec = duration_ms / 1000;

    // Calculate reward: fixed amount per second
    let reward = reward_per_sec * elapsed_sec;

    // Cap at remaining pool to avoid underflow.
    if (reward > pool_remaining) {
        pool_remaining
    } else {
        reward
    }
}

/// Add or update holder reward.
fun add_holder_reward(rewards: &mut vector<HolderReward>, player: address, amount: u64) {
    let len = vector::length(rewards);
    let mut i = 0;
    let mut found = false;
    while (i < len) {
        let reward_ref = vector::borrow_mut(rewards, i);
        if (reward_ref.player == player) {
            reward_ref.amount = reward_ref.amount + amount;
            found = true;
            break
        };
        i = i + 1;
    };

    if (!found) {
        vector::push_back(rewards, HolderReward { player, amount });
    };
}

/// Select random alive player excluding specified address.
fun select_random_alive_player(
    rng: &Random,
    players: &vector<Player>,
    exclude: address,
    ctx: &mut one::tx_context::TxContext,
): address {
    let mut alive_candidates = vector::empty<address>();
    let len = vector::length(players);
    let mut i = 0;
    while (i < len) {
        let player = vector::borrow(players, i);
        if (player.alive && player.addr != exclude) {
            vector::push_back(&mut alive_candidates, player.addr);
        };
        i = i + 1;
    };

    assert!(vector::length(&alive_candidates) > 0, E_NO_ALIVE_PLAYERS);

    let mut generator = random::new_generator(rng, ctx);
    let idx = random::generate_u64_in_range(
        &mut generator,
        0,
        vector::length(&alive_candidates) - 1,
    );
    *vector::borrow(&alive_candidates, idx)
}

/// Select random player (for initial holder).
fun select_random_player(
    rng: &Random,
    players: &vector<Player>,
    ctx: &mut one::tx_context::TxContext,
): address {
    assert!(vector::length(players) > 0, E_NO_ALIVE_PLAYERS);

    let mut generator = random::new_generator(rng, ctx);
    let idx = random::generate_u64_in_range(&mut generator, 0, vector::length(players) - 1);
    let player = vector::borrow(players, idx);
    player.addr
}

/// Find player index by address.
fun find_player_index(players: &vector<Player>, addr: address): option::Option<u64> {
    let len = vector::length(players);
    let mut i = 0;
    while (i < len) {
        let player = vector::borrow(players, i);
        if (player.addr == addr) {
            return option::some(i)
        };
        i = i + 1;
    };
    option::none()
}

fun is_waiting(phase: &GamePhase): bool {
    match (*phase) {
        GamePhase::Waiting => true,
        _ => false,
    }
}

fun is_playing(phase: &GamePhase): bool {
    match (*phase) {
        GamePhase::Playing => true,
        _ => false,
    }
}

fun is_ended(phase: &GamePhase): bool {
    match (*phase) {
        GamePhase::Ended => true,
        _ => false,
    }
}

// ========== GAMEHUB INTEGRATION FUNCTIONS ==========

/// Start a bomb panic round (coordinates GameHub + Bomb Panic)
/// This function bridges the two systems by:
/// 1. Starting the room in GameHub (marks as Started, collects insurance fee)
/// 2. Getting the pool value from the room (after fee deduction)
/// 3. Starting the game logic in Bomb Panic with pool value
public entry fun start_round_with_hub<T>(
    rng: &Random,
    game: &mut GameState<T>,
    room: &mut gamehub::gamehub::Room<T>,
    clock: &Clock,
    admin_cap: &gamehub::gamehub::AdminCap,
    config: &gamehub::gamehub::Config,
    ctx: &mut one::tx_context::TxContext,
) {
    // 1. Start room in GameHub (collects insurance fee from pool)
    gamehub::gamehub::start_room_internal(room, admin_cap, config, ctx);

    // 2. Get pool value from room (after insurance fee deduction)
    let pool_value = gamehub::gamehub::get_pool_value(room);

    // 3. Get room address
    let room_id = object::id_address(room);

    // 4. Start round in Bomb Panic
    start_round(rng, game, room_id, clock, pool_value, ctx);
}

/// Settle a bomb panic round and distribute via GameHub
/// 1. Gets settlement data from Bomb Panic (survivor + holder payouts)
/// 2. Consumes settlement intent (set status consumed)
/// 3. Calls GameHub settle with GameCap authorization (no fee cal)
public entry fun settle_round_with_hub<T>(
    game: &mut GameState<T>,
    room: &mut gamehub::gamehub::Room<T>,
    game_cap: &gamehub::gamehub::GameCap,
    ctx: &mut one::tx_context::TxContext,
) {
    // 1. Get settlement data from Bomb Panic (doesn't consume yet)
    let (addresses, amounts, _pool) = get_settlement_data(game);

    // 2. Consume settlement intent (marks as consumed)
    let intent = consume_settlement_intent(game);

    event::emit(RoundSettled {
        round_id: intent.round_id,
        dead_player: intent.dead_player,
        survivors: intent.survivors,
        survivor_payout_each: intent.survivor_payout_each,
        holder_rewards: intent.holder_rewards,
        remaining_pool_value: intent.remaining_pool_value,
    });
    // 3. Settle in GameHub (just updates balances, no fee calculation)
    gamehub::gamehub::settle_internal(room, addresses, amounts, game_cap, ctx);
}

/// Prepare for next round: reset game (keeps survivors) + create new room
/// 1. Resets Bomb Panic game (survivors stay, dead players removed)
/// 2. Creates a new room for the next round
public entry fun prepare_next_round<T, G>(
    registry: &gamehub::gamehub::GameRegistry,
    config: &gamehub::gamehub::Config,
    game: &mut GameState<T>,
    entry_fee: u64,
    max_players: u8,
    creation_fee: one::coin::Coin<T>,
    ctx: &mut one::tx_context::TxContext,
) {
    // 1. Reset Bomb Panic game (keeps survivors)
    reset_game(game);

    // 2. Create new room for next round
    gamehub::gamehub::create_room_internal<T, G>(
        registry,
        config,
        entry_fee,
        max_players,
        creation_fee,
        ctx,
    );
}

#[test_only]
public fun debug_round_id<T>(g: &GameState<T>): u64 { g.round_id }

#[test_only]
public fun debug_pool_value<T>(g: &GameState<T>): u64 { g.pool_value }

#[test_only]
public fun debug_phase<T>(g: &GameState<T>): u8 {
    match (g.phase) {
        GamePhase::Waiting => 0,
        GamePhase::Playing => 1,
        GamePhase::Ended => 2,
    }
}

#[test_only]
public fun debug_bomb_holder<T>(g: &GameState<T>): address {
    *option::borrow(&g.bomb_holder)
}

#[test_only]
public fun new_hub_ref_for_testing(id: object::ID): GameHubRef {
    GameHubRef { id }
}

#[test_only]
public fun destroy_for_testing<T>(game: GameState<T>) {
    let GameState {
        id,
        name: _,
        phase: _,
        round_id: _,
        players: _,
        pool_value: _,
        entry_fee: _,
        entry_fee_per_player: _,
        bomb_holder: _,
        holder_start_ms: _,
        holder_rewards: _,
        settlement_consumed: _,
        hub_ref: _,
        current_room_id: _,
        round_start_ms: _,
        max_players: _,
        reward_per_sec: _,
        explosion_rate_bps: _,
    } = game;
    object::delete(id);
}

#[test_only]
public fun destroy_settlement_intent_for_testing(intent: SettlementIntent) {
    let SettlementIntent {
        round_id: _,
        dead_player: _,
        survivors: _,
        survivor_payout_each: _,
        holder_rewards: _,
        remaining_pool_value: _,
    } = intent;
}

#[test_only]
public fun settlement_round_id(intent: &SettlementIntent): u64 {
    intent.round_id
}

#[test_only]
public fun settlement_dead_player(intent: &SettlementIntent): address {
    intent.dead_player
}

#[test_only]
public fun settlement_survivors(intent: &SettlementIntent): vector<address> {
    intent.survivors
}

#[test_only]
public fun settlement_survivor_payout_each(intent: &SettlementIntent): u64 {
    intent.survivor_payout_each
}

#[test_only]
public fun settlement_remaining_pool(intent: &SettlementIntent): u64 {
    intent.remaining_pool_value
}

#[test_only]
public fun settlement_holder_rewards(intent: &SettlementIntent): vector<HolderReward> {
    intent.holder_rewards
}

#[test_only]
public fun holder_reward_amount(reward: &HolderReward): u64 {
    reward.amount
}
