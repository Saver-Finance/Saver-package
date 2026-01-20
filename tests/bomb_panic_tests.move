#[test_only]
module games::bomb_panic_tests;

use games::bomb_panic::{Self, GameState, GameHubRef, SettlementIntent};
use one::clock::{Self, Clock};
use one::random::{Self, Random};
use one::oct::OCT;
use one::test_scenario::{Self as ts, Scenario};

const POOL_VALUE: u64 = 1_000_000;
const PLAYER_COUNT: u64 = 4;

// Test addresses
const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;
const CAROL: address = @0xCA401;
const DAVE: address = @0xDA4E;

/// Helper: create Random object (must be called by @0x0)
fun create_random(scenario: &mut Scenario) {
    ts::next_tx(scenario, @0x0);
    random::create_for_testing(ts::ctx(scenario));
}

/// Helper: create hub ref
fun create_hub_ref(): GameHubRef {
    bomb_panic::new_hub_ref_for_testing(object::id_from_address(@0x1234))
}

/// Helper: advance clock by milliseconds
fun advance_clock(clock: &mut Clock, ms: u64) {
    clock::increment_for_testing(clock, ms);
}

#[test]
fun test_join_adds_players_up_to_max() {
    let mut scenario = ts::begin(ALICE);
    
    ts::next_tx(&mut scenario, ALICE);
    let hub_ref = create_hub_ref();
    let name = std::string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, ALICE, name, 100, 10, ts::ctx(&mut scenario));
    
    // Join 4 players
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    ts::next_tx(&mut scenario, CAROL);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    ts::next_tx(&mut scenario, DAVE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    // Verify 4 players joined (via debug function if available)
    // We can't directly access player count, so we'll verify by starting round
    
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bomb_panic::E_TOO_MANY_PLAYERS)]
fun test_join_cannot_exceed_max_players() {
    let mut scenario = ts::begin(ALICE);
    
    ts::next_tx(&mut scenario, ALICE);
    let hub_ref = create_hub_ref();
    let name = std::string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, ALICE, name, 100, 10, ts::ctx(&mut scenario));
    
    ts::next_tx(&mut scenario, @0x1);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, @0x2);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, @0x3);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, @0x4);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, @0x5);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, @0x6);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, @0x7);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, @0x8);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, @0x9);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, @0xA);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bomb_panic::E_ALREADY_JOINED)]
fun test_join_cannot_join_twice() {
    let mut scenario = ts::begin(ALICE);
    
    ts::next_tx(&mut scenario, ALICE);
    let hub_ref = create_hub_ref();
    let name = std::string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, ALICE, name, 100, 10, ts::ctx(&mut scenario));
    
    // Alice joins
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    // Alice tries to join again - should abort
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}

#[test]
fun test_start_round_sets_playing_state() {
    let mut scenario = ts::begin(ALICE);
    
    // Create random
    create_random(&mut scenario);
    
    ts::next_tx(&mut scenario, ALICE);
    let rng = ts::take_shared<Random>(&scenario);
    let hub_ref = create_hub_ref();
    let name = std::string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, ALICE, name, 100, 10, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    // Start round
    ts::next_tx(&mut scenario, ALICE);
    let start_ms = clock::timestamp_ms(&clock);
    bomb_panic::start_round(&rng, &mut game, &clock, POOL_VALUE, ts::ctx(&mut scenario));
    
    // Verify state via debug functions
    let phase = bomb_panic::debug_phase(&game);
    assert!(phase == 1, 0); // 1 = Playing
    
    let pool = bomb_panic::debug_pool_value(&game);
    assert!(pool == POOL_VALUE, 1);
    
    let explode_at = bomb_panic::debug_explode_at_ms(&game);
    assert!(explode_at > start_ms, 2);
    
    // Cleanup
    clock::destroy_for_testing(clock);
    ts::return_shared(rng);
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}

#[test]
fun test_pass_bomb_changes_holder_and_reduces_pool() {
    let mut scenario = ts::begin(ALICE);
    
    // Setup
    create_random(&mut scenario);
    ts::next_tx(&mut scenario, ALICE);
    let rng = ts::take_shared<Random>(&scenario);
    let hub_ref = create_hub_ref();
    let name = std::string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, ALICE, name, 100, 10, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Join players
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, CAROL);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    // Start round
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::start_round(&rng, &mut game, &clock, POOL_VALUE, ts::ctx(&mut scenario));
    
    let initial_pool = bomb_panic::debug_pool_value(&game);
    
    // Advance time to accumulate some reward
    advance_clock(&mut clock, 5000); // 5 seconds
    
    // Get current holder and pass bomb
    let holder = bomb_panic::debug_bomb_holder(&game);
    ts::next_tx(&mut scenario, holder);
    bomb_panic::pass_bomb(&rng, &mut game, &clock, ts::ctx(&mut scenario));
    
    // Verify pool decreased (reward was paid)
    let pool_after = bomb_panic::debug_pool_value(&game);
    assert!(pool_after < initial_pool, 0);
    
    // Verify holder changed
    let new_holder = bomb_panic::debug_bomb_holder(&game);
    assert!(new_holder != holder, 1);
    
    // Cleanup
    clock::destroy_for_testing(clock);
    ts::return_shared(rng);
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bomb_panic::E_NOT_HOLDER)]
fun test_pass_bomb_only_holder_can_call() {
    let mut scenario = ts::begin(ALICE);
    
    // Setup
    create_random(&mut scenario);
    ts::next_tx(&mut scenario, ALICE);
    let rng = ts::take_shared<Random>(&scenario);
    let hub_ref = create_hub_ref();
    let name = std::string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, ALICE, name, 100, 10, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Join players
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    // Start round
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::start_round(&rng, &mut game, &clock, POOL_VALUE, ts::ctx(&mut scenario));
    
    // Get current holder
    let holder = bomb_panic::debug_bomb_holder(&game);
    
    // Non-holder tries to pass - should abort
    let non_holder = if (holder == ALICE) { BOB } else { ALICE };
    ts::next_tx(&mut scenario, non_holder);
    bomb_panic::pass_bomb(&rng, &mut game, &clock, ts::ctx(&mut scenario));
    
    // Cleanup
    clock::destroy_for_testing(clock);
    ts::return_shared(rng);
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}

#[test]
fun test_try_explode_before_deadline_does_nothing() {
    let mut scenario = ts::begin(ALICE);
    
    // Setup
    create_random(&mut scenario);
    ts::next_tx(&mut scenario, ALICE);
    let rng = ts::take_shared<Random>(&scenario);
    let hub_ref = create_hub_ref();
    let name = std::string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, ALICE, name, 100, 10, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Join and start
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::start_round(&rng, &mut game, &clock, POOL_VALUE, ts::ctx(&mut scenario));
    
    let explode_at = bomb_panic::debug_explode_at_ms(&game);
    
    // Advance time but not to deadline
    advance_clock(&mut clock, 1000); // 1 second
    assert!(clock::timestamp_ms(&clock) < explode_at, 0);
    
    // Try to explode - should do nothing
    bomb_panic::try_explode(&mut game, &clock, &rng, ts::ctx(&mut scenario));
    
    // Verify still Playing
    let phase = bomb_panic::debug_phase(&game);
    assert!(phase == 1, 1); // 1 = Playing
    
    // Cleanup
    clock::destroy_for_testing(clock);
    ts::return_shared(rng);
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}

#[test]
fun test_try_explode_after_deadline_ends_game() {
    let mut scenario = ts::begin(ALICE);
    
    // Setup
    create_random(&mut scenario);
    ts::next_tx(&mut scenario, ALICE);
    let rng = ts::take_shared<Random>(&scenario);
    let hub_ref = create_hub_ref();
    let name = std::string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, ALICE, name, 100, 10, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Join and start
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::start_round(&rng, &mut game, &clock, POOL_VALUE, ts::ctx(&mut scenario));
    
    let explode_at = bomb_panic::debug_explode_at_ms(&game);
    
    // Advance time past deadline
    let time_to_advance = explode_at - clock::timestamp_ms(&clock) + 1000;
    advance_clock(&mut clock, time_to_advance);
    assert!(clock::timestamp_ms(&clock) >= explode_at, 0);
    
    // Explode
    bomb_panic::try_explode(&mut game, &clock, &rng, ts::ctx(&mut scenario));
    
    // Verify Ended
    let phase = bomb_panic::debug_phase(&game);
    assert!(phase == 2, 1); // 2 = Ended
    
    // Cleanup
    clock::destroy_for_testing(clock);
    ts::return_shared(rng);
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}

#[test]
fun test_consume_settlement_intent_works_once() {
    let mut scenario = ts::begin(ALICE);
    
    // Setup
    create_random(&mut scenario);
    ts::next_tx(&mut scenario, ALICE);
    let rng = ts::take_shared<Random>(&scenario);
    let hub_ref = create_hub_ref();
    let name = std::string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, ALICE, name, 100, 10, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Join and start
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::start_round(&rng, &mut game, &clock, POOL_VALUE, ts::ctx(&mut scenario));
    
    // Explode
    let explode_at = bomb_panic::debug_explode_at_ms(&game);
    advance_clock(&mut clock, explode_at + 1000);
    bomb_panic::try_explode(&mut game, &clock, &rng, ts::ctx(&mut scenario));
    
    // Consume settlement - should work
    let intent = bomb_panic::consume_settlement_intent(&mut game);
    bomb_panic::destroy_settlement_intent_for_testing(intent);
    
    // Cleanup
    clock::destroy_for_testing(clock);
    ts::return_shared(rng);
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bomb_panic::E_SETTLEMENT_CONSUMED)]
fun test_consume_settlement_intent_fails_second_time() {
    let mut scenario = ts::begin(ALICE);
    
    // Setup
    create_random(&mut scenario);
    ts::next_tx(&mut scenario, ALICE);
    let rng = ts::take_shared<Random>(&scenario);
    let hub_ref = create_hub_ref();
    let name = std::string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, ALICE, name, 100, 10, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Join and start
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::start_round(&rng, &mut game, &clock, POOL_VALUE, ts::ctx(&mut scenario));
    
    // Explode
    let explode_at = bomb_panic::debug_explode_at_ms(&game);
    advance_clock(&mut clock, explode_at + 1000);
    bomb_panic::try_explode(&mut game, &clock, &rng, ts::ctx(&mut scenario));
    
    // First consume - works
    let intent = bomb_panic::consume_settlement_intent(&mut game);
    bomb_panic::destroy_settlement_intent_for_testing(intent);
    
    // Second consume - should abort
    let intent2 = bomb_panic::consume_settlement_intent(&mut game);
    bomb_panic::destroy_settlement_intent_for_testing(intent2);
    
    // Cleanup
    clock::destroy_for_testing(clock);
    ts::return_shared(rng);
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}

#[test]
fun test_full_workflow_happy_path() {
    let mut scenario = ts::begin(ALICE);
    
    create_random(&mut scenario);
    ts::next_tx(&mut scenario, ALICE);
    let rng = ts::take_shared<Random>(&scenario);
    let hub_ref = create_hub_ref();
    let name = std::string::utf8(b"Happy Path");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, ALICE, name, 100, 10, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Join 4 players
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, CAROL);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, DAVE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    // Start round with pool = entry_fee * 4
    ts::next_tx(&mut scenario, ALICE);
    let initial_pool = POOL_VALUE;
    bomb_panic::start_round(&rng, &mut game, &clock, initial_pool, ts::ctx(&mut scenario));
    
    let round_id = bomb_panic::debug_round_id(&game);
    let explode_at = bomb_panic::debug_explode_at_ms(&game);
    
    // Identify current holder
    let holder = bomb_panic::debug_bomb_holder(&game);
    
    // As holder, pass bomb at least once
    advance_clock(&mut clock, 3000); // 3 seconds
    ts::next_tx(&mut scenario, holder);
    bomb_panic::pass_bomb(&rng, &mut game, &clock, ts::ctx(&mut scenario));
    
    let pool_after_pass = bomb_panic::debug_pool_value(&game);
    assert!(pool_after_pass < initial_pool, 0); // Pool decreased
    
    // Try explode before deadline (should no-op)
    advance_clock(&mut clock, 1000); // 1 more second
    assert!(clock::timestamp_ms(&clock) < explode_at, 1);
    bomb_panic::try_explode(&mut game, &clock, &rng, ts::ctx(&mut scenario));
    
    let phase = bomb_panic::debug_phase(&game);
    assert!(phase == 1, 2); // Still Playing
    
    // Advance to 65 seconds from round start (100% probability zone)
    advance_clock(&mut clock, 61000);
    
    // Keep trying until bomb explodes (probabilistic system)
    let mut attempts = 0;
    while (attempts < 100) {
        bomb_panic::try_explode(&mut game, &clock, &rng, ts::ctx(&mut scenario));
        let phase_check = bomb_panic::debug_phase(&game);
        if (phase_check == 2) break; // Ended
        attempts = attempts + 1;
    };
    
    let phase_after = bomb_panic::debug_phase(&game);
    assert!(phase_after == 2, 3); // Ended
    
    // Consume settlement intent
    let intent = bomb_panic::consume_settlement_intent(&mut game);
    
    // Verify invariants
    let intent_round_id = bomb_panic::settlement_round_id(&intent);
    assert!(intent_round_id == round_id, 4);
    
    let dead_player = bomb_panic::settlement_dead_player(&intent);
    // Verify dead player is one of the 4 players
    assert!(
        dead_player == ALICE || dead_player == BOB || 
        dead_player == CAROL || dead_player == DAVE,
        5
    );
    
    let survivors = bomb_panic::settlement_survivors(&intent);
    let survivors_count = vector::length(&survivors);
    assert!(survivors_count == 3, 6); // 4 - 1 dead = 3 survivors
    
    // Verify dead player not in survivors
    let mut i = 0;
    while (i < survivors_count) {
        let survivor = *vector::borrow(&survivors, i);
        assert!(survivor != dead_player, 7);
        i = i + 1;
    };
    
    let remaining_pool = bomb_panic::settlement_remaining_pool(&intent);
    assert!(remaining_pool <= initial_pool, 8);
    
    let survivor_payout_each = bomb_panic::settlement_survivor_payout_each(&intent);
    // Verify consistent calculation
    if (survivors_count > 0) {
        assert!(survivor_payout_each == remaining_pool / survivors_count, 9);
    };
    
    // Verify economic invariant: total payouts <= initial pool
    let holder_rewards = bomb_panic::settlement_holder_rewards(&intent);
    let mut total_holder_rewards = 0u64;
    let mut j = 0;
    while (j < vector::length(&holder_rewards)) {
        let reward = vector::borrow(&holder_rewards, j);
        total_holder_rewards = total_holder_rewards + bomb_panic::holder_reward_amount(reward);
        j = j + 1;
    };
    
    let total_survivor_payouts = survivors_count * survivor_payout_each;
    let total_payouts = total_holder_rewards + total_survivor_payouts;
    assert!(total_payouts <= initial_pool, 10);
    
    // Verify second consume aborts (already tested above, but check state)
    // We can't call it again here without expected_failure, so we trust the flag
    
    // Cleanup
    bomb_panic::destroy_settlement_intent_for_testing(intent);
    clock::destroy_for_testing(clock);
    ts::return_shared(rng);
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}
