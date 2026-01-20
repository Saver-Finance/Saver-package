#[allow(lint(public_entry), lint(public_random))]
module games::bomb_panic;

use std::string::{Self, String};
use one::clock::{Self, Clock};
use one::event;
use one::random::{Self, Random};

/// Basis points denominator.
const BPS_DENOM: u64 = 10_000;
// Holder earns basis points per second from their entry fee.
/// 100 bps/sec = 1%/sec => 10 sec = 10% of entry fee (1.1x concept).
const REWARD_BPS_PER_SEC: u64 = 100;
/// Min delay before explosion (ms).
const MIN_EXPLODE_DELAY_MS: u64 = 5_000;
/// Max delay before explosion (ms).
const MAX_EXPLODE_DELAY_MS: u64 = 30_000;
/// Max time a single player can hold the bomb (anti-camping).
const MAX_HOLD_TIME_MS: u64 = 10_000;

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
const E_UNAUTHORIZED: u64 = 12;

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
    explode_at_ms: u64,
    holder_rewards: vector<HolderReward>,
    settlement_consumed: bool,
    hub_ref: GameHubRef,
    // Authority
    server_authority: address,
    round_start_ms: u64,
    // Config
    max_players: u64,
    reward_bps_per_sec: u64,
    min_explode_delay_ms: u64,
    max_explode_delay_ms: u64,
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
    explode_at_ms: u64,
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

public struct SettlementIntentReady has copy, drop, store {
    round_id: u64,
    remaining_pool_value: u64,
    survivors_count: u64,
}

public struct PlayerExited has copy, drop, store {
    round_id: u64,
    player: address,
    phase: GamePhase,
}

public struct GameReset has copy, drop, store {
    game_id: object::ID,
}

/// Create game state bound to hub.
public fun create_game_state<T>(
    hub_ref: GameHubRef,
    server_authority: address,
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
        explode_at_ms: 0,
        holder_rewards: vector::empty<HolderReward>(),
        settlement_consumed: false,
        hub_ref,
        server_authority,
        round_start_ms: 0,
        max_players,
        reward_bps_per_sec: REWARD_BPS_PER_SEC,
        min_explode_delay_ms: MIN_EXPLODE_DELAY_MS,
        max_explode_delay_ms: MAX_EXPLODE_DELAY_MS,
    }
}

/// Initialize and share a new game state (for testing/deployment).
public entry fun initialize_game<T>(
    hub_id: address,
    server_authority: address,
    name: vector<u8>,
    entry_fee: u64,
    max_players: u64,
    ctx: &mut one::tx_context::TxContext,
) {
    let hub_ref = GameHubRef { id: object::id_from_address(hub_id) };
    let name_str = string::utf8(name);
    let game = create_game_state<T>(hub_ref, server_authority, name_str, entry_fee, max_players, ctx);
    
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
public entry fun join<T>(
    game: &mut GameState<T>,
    ctx: &mut one::tx_context::TxContext,
) {
    assert!(is_waiting(&game.phase), E_WRONG_PHASE);
    assert!(vector::length(&game.players) < game.max_players, E_TOO_MANY_PLAYERS);
    
    let player_addr = one::tx_context::sender(ctx);
    let idx_opt = find_player_index(&game.players, player_addr);
    assert!(option::is_none(&idx_opt), E_ALREADY_JOINED);
    
    vector::push_back(&mut game.players, Player {
        addr: player_addr,
        alive: true,
    });
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
                // We force explosion at the current time.
                // We manually update explode_at_ms so try_explode works immediately.
                game.explode_at_ms = clock::timestamp_ms(clock);
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

/// Start round with pool value from room, random bomb holder + explode time.
public entry fun start_round<T>(
    rng: &Random,
    game: &mut GameState<T>,
    clock: &Clock,
    pool_value: u64,
    ctx: &mut one::tx_context::TxContext,
) {
    assert!(is_waiting(&game.phase), E_WRONG_PHASE);
    assert!(vector::length(&game.players) > 1, E_NOT_ENOUGH_PLAYERS);
    assert!(pool_value > 0, E_POOL_EMPTY);
    
    // Select random initial bomb holder.
    let initial_holder = select_random_player(rng, &game.players, ctx);
    
    // random explosion time.
    let now_ms = clock::timestamp_ms(clock);
    let delay_ms = sample_delay(rng, game.min_explode_delay_ms, game.max_explode_delay_ms, ctx);
    let explode_at_ms = now_ms + delay_ms;
    
    // Initialize round state.
    game.round_id = game.round_id + 1;
    game.pool_value = pool_value;
    
    // Calculate entry fee per player.
    let player_count = vector::length(&game.players);
    game.entry_fee_per_player = pool_value / player_count;
    
    game.bomb_holder = option::some(initial_holder);
    game.holder_start_ms = now_ms;
    game.explode_at_ms = explode_at_ms;
    game.round_start_ms = now_ms;
    game.holder_rewards = vector::empty<HolderReward>();
    game.settlement_consumed = false;
    game.phase = GamePhase::Playing;
    
    event::emit(RoundStarted {
        round_id: game.round_id,
        bomb_holder: initial_holder,
        explode_at_ms,
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
        // We set explode_at_ms to now so try_explode works.
        game.explode_at_ms = now_ms;
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
        game.entry_fee_per_player,
        game.reward_bps_per_sec,
        game.pool_value,
        duration_ms
    );
    
    // Deduct reward from pool.
    game.pool_value = if (game.pool_value > reward) {
        game.pool_value - reward
    } else {
        0
    };
    
    // Record reward.
    add_holder_reward(&mut game.holder_rewards, current_holder, reward);
    
    // Sticky Hands Mechanic: If < 3s remaining, 50% chance to fail pass
    let time_left = if (game.explode_at_ms > now_ms) {
        game.explode_at_ms - now_ms
    } else {
        0
    };

    if (time_left < 3000) {
        let mut generator = random::new_generator(rng, ctx);
        // 0 or 1. If 0 (50%), fail the pass.
        // Or generate_u8_in_range(0..99) < 50
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
fun perform_explosion<T>(
    game: &mut GameState<T>,
    clock: &Clock,
) {
    let now_ms = clock::timestamp_ms(clock);
    let current_holder = *option::borrow(&game.bomb_holder);
    
    // Calculate final reward for holder before explosion.
    let duration_ms = if (now_ms > game.holder_start_ms) {
        now_ms - game.holder_start_ms
    } else {
        0
    };
    let reward = calculate_holder_reward(
        game.entry_fee_per_player,
        game.reward_bps_per_sec,
        game.pool_value,
        duration_ms
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

/// Attempt to explode the bomb based on probabilistic server check.
public entry fun try_explode<T>(
    game: &mut GameState<T>,
    clock: &Clock,
    rng: &Random,
    ctx: &mut one::tx_context::TxContext,
) {
    // Only authorized server can call this
    assert!(one::tx_context::sender(ctx) == game.server_authority, E_UNAUTHORIZED);

    // Already ended, no-op.
    if (is_ended(&game.phase)) return;
    
    assert!(is_playing(&game.phase), E_WRONG_PHASE);
    
    let now_ms = clock::timestamp_ms(clock);
    
    // 1. Check if held too long (Anti-Camping) - Force explode if strict violation
    if (now_ms > game.holder_start_ms && (now_ms - game.holder_start_ms > MAX_HOLD_TIME_MS)) {
        perform_explosion(game, clock);
        return
    };

    // 2. Probabilistic Explosion
    let elapsed_ms = if (now_ms > game.round_start_ms) { now_ms - game.round_start_ms } else { 0 };
    let elapsed_sec = elapsed_ms / 1000;

    let probability_bps = if (elapsed_sec < 10) {
        0 // 0-10s: Grace period
    } else if (elapsed_sec < 30) {
        500 // 10-30s: 5% chance
    } else if (elapsed_sec < 60) {
        2000 // 30-60s: 20% chance
    } else {
        10000 // 60s+: 100% chance
    };

    let mut generator = random::new_generator(rng, ctx);
    let roll = random::generate_u64_in_range(&mut generator, 0, 10000); // 0-9999

    if (roll < probability_bps) {
        perform_explosion(game, clock);
    }
}

/// Consume settlement intent (once per round, after Ended).
public fun consume_settlement_intent<T>(
    game: &mut GameState<T>,
): SettlementIntent {
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

/// Prepare the game for the next round or allow dead players to rejoin.
/// - Removes dead players from the list (they must rejoin/pay again).
/// - Keeps survivors in the list (they stay for the next round).
/// - Resets phase to Waiting so more players can join or round can restart.
public entry fun reset_game<T>(
    game: &mut GameState<T>,
) {
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
    game.bomb_holder = option::none();
    game.holder_start_ms = 0;
    game.explode_at_ms = 0;
    game.holder_rewards = vector::empty();
    game.settlement_consumed = false;
    
    event::emit(GameReset {
        game_id: object::id(game),
    });
}

/// Calculate reward for holder based on time held and entry fee.
/// Formula: reward = entry_fee_per_player * elapsed_sec * reward_bps_per_sec / BPS_DENOM
/// This gives 1% per second (10% at 10 seconds = 1.1x concept).
fun calculate_holder_reward(
    entry_fee_per_player: u64,
    reward_bps_per_sec: u64,
    pool_remaining: u64,
    duration_ms: u64,
): u64 {
    // Convert ms to seconds.
    let elapsed_sec = duration_ms / 1000;
    
    // Calculate reward: entry_fee * elapsed_sec * rate_bps / BPS_DENOM
    // Using u128 to avoid overflow.
    let reward_raw = (entry_fee_per_player as u128) 
        * (elapsed_sec as u128) 
        * (reward_bps_per_sec as u128) 
        / (BPS_DENOM as u128);
    
    let reward = if (reward_raw > (std::u64::max_value!() as u128)) {
        std::u64::max_value!()
    } else {
        reward_raw as u64
    };
    
    // Cap at remaining pool to avoid underflow.
    if (reward > pool_remaining) {
        pool_remaining
    } else {
        reward
    }
}

/// Add or update holder reward.
fun add_holder_reward(
    rewards: &mut vector<HolderReward>,
    player: address,
    amount: u64,
) {
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
    let idx = random::generate_u64_in_range(&mut generator, 0, vector::length(&alive_candidates) - 1);
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

/// Sample random delay for explosion.
fun sample_delay(
    rng: &Random,
    min_ms: u64,
    max_ms: u64,
    ctx: &mut one::tx_context::TxContext,
): u64 {
    let mut generator = random::new_generator(rng, ctx);
    random::generate_u64_in_range(&mut generator, min_ms, max_ms)
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

/// Count number of alive players (survivors).
fun count_survivors(players: &vector<Player>): u64 {
    let len = vector::length(players);
    let mut count = 0;
    let mut i = 0;
    while (i < len) {
        let player = vector::borrow(players, i);
        if (player.alive) {
            count = count + 1;
        };
        i = i + 1;
    };
    count
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

#[test_only]
public fun debug_round_id<T>(g: &GameState<T>): u64 { g.round_id }

#[test_only]
public fun debug_pool_value<T>(g: &GameState<T>): u64 { g.pool_value }

#[test_only]
public fun debug_explode_at_ms<T>(g: &GameState<T>): u64 { g.explode_at_ms }

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
        explode_at_ms: _,
        holder_rewards: _,
        settlement_consumed: _,
        hub_ref: _,
        server_authority: _,
        round_start_ms: _,
        max_players: _,
        reward_bps_per_sec: _,
        min_explode_delay_ms: _,
        max_explode_delay_ms: _,
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
