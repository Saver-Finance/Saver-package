#[allow(lint(coin_field), lint(public_entry), lint(public_random))]
module games::bomb_panic;

use std::u64;
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::event;
use sui::random::{Self, Random};

// Add these in games::bomb_panic (same module as GameState):
// public fun debug_round_id<T>(g: &bomb_panic::GameState<T>): u64 { g.round_id }
// public fun debug_crash_point<T>(g: &bomb_panic::GameState<T>): u64 { g.crash_point }
// public fun debug_start_ts<T>(g: &bomb_panic::GameState<T>): u64 { g.round_start_ts_ms }
// public fun debug_end_ts<T>(g: &bomb_panic::GameState<T>): u64 { g.round_end_ts_ms }
// public fun debug_total_wager<T>(g: &bomb_panic::GameState<T>): u64 { g.total_wager }
// public fun debug_reserved<T>(g: &bomb_panic::GameState<T>): u64 { g.total_payout_reserved }
// public fun debug_ended_mult<T>(g: &bomb_panic::GameState<T>): u64 { g.ended_multiplier }
// public fun debug_state<T>(g: &bomb_panic::GameState<T>): u8 { g.state as u8 }

/// Fixed-point scale for multipliers (1.0x = 10_000).
const SCALE: u64 = 10_000;
/// Basis point denominator.
const BPS_DENOM: u64 = 10_000;
/// Max players per round.
const MAX_PLAYERS: u64 = 10;
/// Linear growth per millisecond (1 unit = 0.0001x).
const RATE_PER_MS: u64 = 1;
/// Upper bound factor for crash sampling (inclusive range: [SCALE, SCALE * CRASH_RANGE_MULT]).
const CRASH_RANGE_MULT: u64 = 100;

/// Error codes.
const E_WRONG_PHASE: u64 = 1;
const E_TOO_MANY_PLAYERS: u64 = 2;
const E_ALREADY_CASHED: u64 = 3;
const E_BELOW_DESIRED: u64 = 4;
const E_AT_OR_AFTER_CRASH: u64 = 5;
const E_FEE_RANGE: u64 = 6;
const E_HUB_MISMATCH: u64 = 7;
const E_ESCROW_VALUE: u64 = 8;

/// Phase enum for round lifecycle.
public enum GamePhase has copy, drop, store {
    Waiting,
    Running,
    Ended,
}

/// Config immutable per game instance.
public struct GameConfig has copy, drop, store {
    max_players: u64,
    scale: u64,
    min_fee_bps: u64,
    max_fee_bps: u64,
}

/// Hub object controlling settlement and randomness source.
public struct GameHub has key, store {
    id: object::UID,
    treasury: address,
    rng_id: object::ID,
}

/// Reference tying state to hub for replay protection.
public struct GameHubRef has copy, drop, store {
    id: object::ID,
}

/// Per-player accounting.
public struct PlayerEntry has copy, drop, store {
    player: address,
    wager: u64,
    cashout_multiplier: option::Option<u64>,
    payout: u64,
    cashed_out: bool,
}

/// Core game state (one per coin type).
public struct GameState<phantom T> has key, store {
    id: object::UID,
    state: GamePhase,
    round_id: u64,
    escrow_coin: Coin<T>,
    player_entries: vector<PlayerEntry>,
    total_wager: u64,
    total_payout_reserved: u64,
    fee_bps: u64,
    crash_point: u64,
    round_start_ts_ms: u64,
    round_end_ts_ms: u64,
    running_start_multiplier: u64,
    ended_multiplier: u64,
    game_config: GameConfig,
    hub: GameHubRef,
    version: u64,
}

/// Events.
public struct RoundStarted has copy, drop, store {
    round_id: u64,
    crash_point: u64,
    fee_bps: u64,
    start_ts_ms: u64,
}

public struct Cashout has copy, drop, store {
    round_id: u64,
    player: address,
    cashout_multiplier: u64,
    payout: u64,
}

public struct RoundEnded has copy, drop, store {
    round_id: u64,
    ended_multiplier: u64,
    end_ts_ms: u64,
}

public struct RoundSettled has copy, drop, store {
    round_id: u64,
    total_payout_reserved: u64,
    fee_collected: u64,
    remainder_to_house: u64,
}

public struct RoundCancelled has copy, drop, store {
    round_id: u64,
}

/// Create a hub with a randomness object and treasury receiver.
public fun create_hub(
    treasury: address,
    rng: &Random,
    ctx: &mut sui::tx_context::TxContext,
): GameHub {
    GameHub { id: object::new(ctx), treasury, rng_id: object::id(rng) }
}

/// Initialize a game state bound to a hub for a specific coin type.
public fun create_game_state<T>(hub: &GameHub, ctx: &mut sui::tx_context::TxContext): GameState<T> {
    GameState {
        id: object::new(ctx),
        state: GamePhase::Waiting,
        round_id: 0,
        escrow_coin: coin::zero<T>(ctx),
        player_entries: vector::empty<PlayerEntry>(),
        total_wager: 0,
        total_payout_reserved: 0,
        fee_bps: 0,
        crash_point: SCALE,
        round_start_ts_ms: 0,
        round_end_ts_ms: 0,
        running_start_multiplier: SCALE,
        ended_multiplier: SCALE,
        game_config: GameConfig {
            max_players: MAX_PLAYERS,
            scale: SCALE,
            min_fee_bps: 0,
            max_fee_bps: BPS_DENOM,
        },
        hub: GameHubRef { id: object::uid_to_inner(&hub.id) },
        version: 0,
    }
}

/// Start a new round: lock escrow, sample crash point, set running.
public entry fun start_round<T>(
    hub: &mut GameHub,
    rng: &Random,
    game: &mut GameState<T>,
    clock: &Clock,
    escrow: Coin<T>,
    fee_bps: u64,
    ctx: &mut sui::tx_context::TxContext,
) {
    assert!(is_waiting(&game.state), E_WRONG_PHASE);
    assert!(fee_bps <= BPS_DENOM, E_FEE_RANGE);
    assert!(
        fee_bps >= game.game_config.min_fee_bps && fee_bps <= game.game_config.max_fee_bps,
        E_FEE_RANGE,
    );
    assert!(object::uid_to_inner(&hub.id) == game.hub.id, E_HUB_MISMATCH);
    assert!(object::id(rng) == hub.rng_id, E_HUB_MISMATCH);
    // Enforce single-token escrow.
    assert!(coin::value(&escrow) >= 1, E_ESCROW_VALUE);

    // Sample crash multiplier once from sui::random; range [SCALE, SCALE*CRASH_RANGE_MULT].
    let crash_point = sample_crash_point(rng, ctx);

    // Reset round accounting.
    coin::join(&mut game.escrow_coin, escrow);
    game.player_entries = vector::empty<PlayerEntry>();
    game.total_wager = coin::value(&game.escrow_coin);
    game.total_payout_reserved = 0;
    game.fee_bps = fee_bps;
    game.crash_point = crash_point;
    game.round_start_ts_ms = clock::timestamp_ms(clock);
    game.round_end_ts_ms = 0;
    game.running_start_multiplier = SCALE;
    game.ended_multiplier = SCALE;
    game.round_id = game.round_id + 1;
    game.version = game.version + 1;
    game.state = GamePhase::Running;

    event::emit(RoundStarted {
        round_id: game.round_id,
        crash_point,
        fee_bps,
        start_ts_ms: game.round_start_ts_ms,
    });
}

/// Player cashout at or below current multiplier but strictly before crash.
public entry fun cashout<T>(
    game: &mut GameState<T>,
    clock: &Clock,
    desired_multiplier: u64,
    ctx: &mut sui::tx_context::TxContext,
) {
    assert!(is_running(&game.state), E_WRONG_PHASE);
    assert!(desired_multiplier >= SCALE, E_BELOW_DESIRED);

    // Current deterministic multiplier.
    let current_mult = current_multiplier(game, clock);
    assert!(current_mult >= desired_multiplier, E_BELOW_DESIRED);
    assert!(current_mult < game.crash_point, E_AT_OR_AFTER_CRASH);

    // Locate or add player entry.
    let player_addr = sui::tx_context::sender(ctx);
    let (idx_opt, len) = find_player(&game.player_entries, player_addr);
    let idx = if (option::is_some(&idx_opt)) {
        *option::borrow(&idx_opt)
    } else {
        assert!(len < game.game_config.max_players, E_TOO_MANY_PLAYERS);
        let wager = per_player_wager(game.total_wager);
        let entry = PlayerEntry {
            player: player_addr,
            wager,
            cashout_multiplier: option::none(),
            payout: 0,
            cashed_out: false,
        };
        vector::push_back(&mut game.player_entries, entry);
        len
    };

    let entry_ref = vector::borrow_mut(&mut game.player_entries, idx);
    assert!(!entry_ref.cashed_out, E_ALREADY_CASHED);

    // Gross payout = wager * desired_multiplier / SCALE.
    let gross = multiply_scaled(entry_ref.wager, desired_multiplier);
    // Apply fee.
    let payout = apply_fee(gross, game.fee_bps);
    // Enforce payout cap by clamping to remaining available.
    let cap = payout_cap(game.total_wager, game.fee_bps);
    let available = if (cap > game.total_payout_reserved) { cap - game.total_payout_reserved }
    else { 0 };
    let final_payout = if (payout > available) { available } else { payout };

    // Mark player state prior to transfer.
    entry_ref.cashout_multiplier = option::some(desired_multiplier);
    entry_ref.payout = final_payout;
    entry_ref.cashed_out = true;
    game.total_payout_reserved = game.total_payout_reserved + final_payout;

    // Pay immediately from escrow if anything remains under cap.
    if (final_payout > 0) {
        let out = coin::split(&mut game.escrow_coin, final_payout, ctx);
        sui::transfer::public_transfer(out, player_addr);
    };

    event::emit(Cashout {
        round_id: game.round_id,
        player: player_addr,
        cashout_multiplier: desired_multiplier,
        payout: final_payout,
    });
}

/// Permissionless crash once multiplier reaches or exceeds crash point.
public entry fun crash<T>(game: &mut GameState<T>, clock: &Clock) {
    if (is_ended(&game.state)) return;
    assert!(is_running(&game.state), E_WRONG_PHASE);
    let current_mult = current_multiplier(game, clock);
    assert!(current_mult >= game.crash_point, E_AT_OR_AFTER_CRASH);

    game.state = GamePhase::Ended;
    game.ended_multiplier = current_mult;
    game.round_end_ts_ms = clock::timestamp_ms(clock);

    event::emit(RoundEnded {
        round_id: game.round_id,
        ended_multiplier: current_mult,
        end_ts_ms: game.round_end_ts_ms,
    });
}

/// Settle an ended round: pay fee and remainder to treasury; reset to Waiting.
public entry fun settle_round<T>(
    hub: &mut GameHub,
    game: &mut GameState<T>,
    ctx: &mut sui::tx_context::TxContext,
) {
    assert!(is_ended(&game.state), E_WRONG_PHASE);
    assert!(object::uid_to_inner(&hub.id) == game.hub.id, E_HUB_MISMATCH);

    let escrow_value = coin::value(&game.escrow_coin);
    let reserved = game.total_payout_reserved;
    let fee = fee_amount(game.total_wager, game.fee_bps);
    let available_for_fee = if (escrow_value > fee) { fee } else { escrow_value };

    // Collect fee to treasury.
    if (available_for_fee > 0) {
        let fee_coin = coin::split(&mut game.escrow_coin, available_for_fee, ctx);
        sui::transfer::public_transfer(fee_coin, hub.treasury);
    };

    // Remaining escrow goes to treasury as house remainder.
    let remainder_value = coin::value(&game.escrow_coin);
    if (remainder_value > 0) {
        let remainder_coin = coin::split(&mut game.escrow_coin, remainder_value, ctx);
        sui::transfer::public_transfer(remainder_coin, hub.treasury);
    };

    event::emit(RoundSettled {
        round_id: game.round_id,
        total_payout_reserved: reserved,
        fee_collected: available_for_fee,
        remainder_to_house: remainder_value,
    });

    // Reset state to Waiting with zeroed escrow.
    game.player_entries = vector::empty<PlayerEntry>();
    game.total_wager = 0;
    game.total_payout_reserved = 0;
    game.fee_bps = 0;
    game.crash_point = SCALE;
    game.round_start_ts_ms = 0;
    game.round_end_ts_ms = 0;
    game.running_start_multiplier = SCALE;
    game.ended_multiplier = SCALE;
    game.state = GamePhase::Waiting;
}

/// Optional cancel only if still waiting (no randomness consumed).
public entry fun force_cancel_round<T>(
    hub: &mut GameHub,
    game: &mut GameState<T>,
    ctx: &mut sui::tx_context::TxContext,
) {
    assert!(is_waiting(&game.state), E_WRONG_PHASE);
    assert!(object::uid_to_inner(&hub.id) == game.hub.id, E_HUB_MISMATCH);

    // Return escrow (if any) to treasury to avoid trapping value.
    let value = coin::value(&game.escrow_coin);
    if (value > 0) {
        let refund = coin::split(&mut game.escrow_coin, value, ctx);
        sui::transfer::public_transfer(refund, hub.treasury);
    };

    event::emit(RoundCancelled { round_id: game.round_id });

    game.player_entries = vector::empty<PlayerEntry>();
    game.total_wager = 0;
    game.total_payout_reserved = 0;
    game.fee_bps = 0;
    game.crash_point = SCALE;
    game.round_start_ts_ms = 0;
    game.round_end_ts_ms = 0;
    game.running_start_multiplier = SCALE;
    game.ended_multiplier = SCALE;
}

/// Fixed-point multiplier at current clock time.
fun current_multiplier<T>(game: &GameState<T>, clock: &Clock): u64 {
    let now_ms = clock::timestamp_ms(clock);
    let elapsed = if (now_ms > game.round_start_ts_ms) { now_ms - game.round_start_ts_ms } else {
        0
    };
    let inc: u128 = (elapsed as u128) * (RATE_PER_MS as u128);
    let base: u128 = game.running_start_multiplier as u128;
    let res = base + inc;
    if (res > (u64::max_value!() as u128)) { u64::max_value!() } else { res as u64 }
}

/// Payout including multiplier (before fees).
fun multiply_scaled(wager: u64, mult: u64): u64 {
    let num: u128 = (wager as u128) * (mult as u128);
    (num / (SCALE as u128)) as u64
}

/// Apply fee in basis points.
fun apply_fee(amount: u64, fee_bps: u64): u64 {
    let num: u128 = (amount as u128) * ((BPS_DENOM - fee_bps) as u128);
    (num / (BPS_DENOM as u128)) as u64
}

/// Maximum total payouts after fees.
fun payout_cap(total_wager: u64, fee_bps: u64): u64 {
    apply_fee(total_wager, fee_bps)
}

/// Fee computed from gross value.
fun fee_amount(gross: u64, fee_bps: u64): u64 {
    let num: u128 = (gross as u128) * (fee_bps as u128);
    (num / (BPS_DENOM as u128)) as u64
}

/// Sample crash multiplier using sui::random.
fun sample_crash_point(rng: &Random, ctx: &mut sui::tx_context::TxContext): u64 {
    let mut generator = random::new_generator(rng, ctx);
    let draw = random::generate_u64(&mut generator);
    let min = SCALE as u128;
    let range = (SCALE * CRASH_RANGE_MULT) as u128 - min;
    let picked = min + (draw as u128 % range);
    picked as u64
}

/// Locate player index or None.
fun find_player(entries: &vector<PlayerEntry>, addr: address): (option::Option<u64>, u64) {
    let len = vector::length(entries);
    let mut i = 0;
    while (i < len) {
        let e = vector::borrow(entries, i);
        if (e.player == addr) return (option::some(i), len);
        i = i + 1;
    };
    (option::none(), len)
}

/// Deterministic per-player wager share so total_wager remains 1 token.
fun per_player_wager(total_wager: u64): u64 {
    let share = total_wager / MAX_PLAYERS;
    if (share == 0) { 1 } else { share }
}

fun is_waiting(phase: &GamePhase): bool {
    match (*phase) {
        GamePhase::Waiting => true,
        _ => false,
    }
}

fun is_running(phase: &GamePhase): bool {
    match (*phase) {
        GamePhase::Running => true,
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
public fun debug_crash_point<T>(g: &GameState<T>): u64 { g.crash_point }

#[test_only]
public fun debug_start_ts<T>(g: &GameState<T>): u64 { g.round_start_ts_ms }

#[test_only]
public fun debug_end_ts<T>(g: &GameState<T>): u64 { g.round_end_ts_ms }

#[test_only]
public fun debug_total_wager<T>(g: &GameState<T>): u64 { g.total_wager }

#[test_only]
public fun debug_reserved<T>(g: &GameState<T>): u64 { g.total_payout_reserved }

#[test_only]
public fun debug_ended_mult<T>(g: &GameState<T>): u64 { g.ended_multiplier }

#[test_only]
public fun debug_state<T>(g: &GameState<T>): u8 {
    match (g.state) {
        GamePhase::Waiting => 0,
        GamePhase::Running => 1,
        GamePhase::Ended => 2,
    }
}
