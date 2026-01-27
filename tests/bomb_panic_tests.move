#[test_only]
module games::bomb_panic_tests;

use games::bomb_panic::{Self, GameState, GameHubRef, SettlementIntent};
use gamehub::gamehub::{Self, Room};
use one::clock::{Self, Clock};
use one::random::{Self, Random};
use one::oct::OCT;
use one::test_scenario::{Self as ts, Scenario};
use one::coin;

const ENTRY_FEE: u64 = 100;

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

/// Helper: setup a Room for testing
fun setup_room<T>(scenario: &mut Scenario): object::ID {
    ts::next_tx(scenario, ALICE);
    let ctx = ts::ctx(scenario);
    
    // We need GameRegistry and Config to create room via gamehub
    gamehub::init_for_testing(ctx);
    
    ts::next_tx(scenario, ALICE);
    let mut registry = ts::take_shared<gamehub::GameRegistry>(scenario);
    let config = ts::take_shared<gamehub::Config>(scenario);
    let admin_cap = ts::take_from_sender<gamehub::AdminCap>(scenario);
    
    // Register game
    let game_cap = gamehub::register_game<T>(&mut registry, &admin_cap, b"Test Game", ts::ctx(scenario));
    
    // Create room
    let creation_fee = coin::mint_for_testing<OCT>(0, ts::ctx(scenario));
    gamehub::create_room<OCT, T>(
        &registry,
        &config,
        ENTRY_FEE,
        10,
        creation_fee,
        ts::ctx(scenario)
    );
    
    ts::return_shared(registry);
    ts::return_shared(config);
    ts::return_to_sender(scenario, admin_cap);
    transfer::public_transfer(game_cap, ALICE);

    ts::next_tx(scenario, ALICE);
    let room = ts::take_shared<Room<OCT>>(scenario);
    let room_id = object::id(&room);
    ts::return_shared(room);
    
    room_id
}

#[test]
fun test_join_adds_players_up_to_max() {
    let mut scenario = ts::begin(ALICE);
    
    ts::next_tx(&mut scenario, ALICE);
    let room_id = setup_room<OCT>(&mut scenario);
    
    ts::next_tx(&mut scenario, ALICE);
    let hub_ref = create_hub_ref();
    let name = std::string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    
    // Join 4 players
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    ts::next_tx(&mut scenario, CAROL);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    ts::next_tx(&mut scenario, DAVE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bomb_panic::E_ALREADY_JOINED)]
fun test_join_cannot_join_twice() {
    let mut scenario = ts::begin(ALICE);
    
    ts::next_tx(&mut scenario, ALICE);
    let room_id = setup_room<OCT>(&mut scenario);
    
    ts::next_tx(&mut scenario, ALICE);
    let hub_ref = create_hub_ref();
    let name = std::string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    
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
    let room_id = setup_room<OCT>(&mut scenario);
    
    ts::next_tx(&mut scenario, ALICE);
    let rng = ts::take_shared<Random>(&scenario);
    let hub_ref = create_hub_ref();
    let name = std::string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    // Prepare room pool
    ts::next_tx(&mut scenario, ALICE);
    let mut room = ts::take_shared<Room<OCT>>(&scenario);
    let coin1 = coin::mint_for_testing<OCT>(ENTRY_FEE * 2, ts::ctx(&mut scenario));
    gamehub::join_room_internal(&mut room, ts::ctx(&mut scenario));
    gamehub::ready_to_play_internal(&mut room, coin1, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, BOB);
    let coin2 = coin::mint_for_testing<OCT>(ENTRY_FEE * 2, ts::ctx(&mut scenario));
    gamehub::join_room_internal(&mut room, ts::ctx(&mut scenario));
    gamehub::ready_to_play_internal(&mut room, coin2, ts::ctx(&mut scenario));
    
    // Start round (2 players, so pool = 100 * 2 = 200)
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::start_round(&rng, &mut game, &room, &clock, ts::ctx(&mut scenario));
    
    // Verify state 
    let phase = bomb_panic::debug_phase(&game);
    assert!(phase == 1, 0); // 1 = Playing
    
    let pool = bomb_panic::debug_pool_value(&game);
    assert!(pool == ENTRY_FEE * 2, 1);
    
    // Cleanup
    clock::destroy_for_testing(clock);
    ts::return_shared(rng);
    ts::return_shared(room);
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}

#[test]
fun test_pass_bomb_changes_holder_and_reduces_pool() {
    let mut scenario = ts::begin(ALICE);
    
    // Setup
    create_random(&mut scenario);
    ts::next_tx(&mut scenario, ALICE);
    let room_id = setup_room<OCT>(&mut scenario);
    
    ts::next_tx(&mut scenario, ALICE);
    let rng = ts::take_shared<Random>(&scenario);
    let hub_ref = create_hub_ref();
    let name = std::string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Join players
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, CAROL);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    // Prepare room pool
    ts::next_tx(&mut scenario, ALICE);
    let mut room = ts::take_shared<Room<OCT>>(&scenario);
    gamehub::join_room_internal(&mut room, ts::ctx(&mut scenario));
    gamehub::ready_to_play_internal(&mut room, coin::mint_for_testing<OCT>(ENTRY_FEE * 2, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    gamehub::join_room_internal(&mut room, ts::ctx(&mut scenario));
    gamehub::ready_to_play_internal(&mut room, coin::mint_for_testing<OCT>(ENTRY_FEE * 2, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, CAROL);
    gamehub::join_room_internal(&mut room, ts::ctx(&mut scenario));
    gamehub::ready_to_play_internal(&mut room, coin::mint_for_testing<OCT>(ENTRY_FEE * 2, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));

    // Start round (3 players, so pool = 100 * 3 = 300)
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::start_round(&rng, &mut game, &room, &clock, ts::ctx(&mut scenario));
    
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
    ts::return_shared(room);
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
    let room_id = setup_room<OCT>(&mut scenario);
    
    ts::next_tx(&mut scenario, ALICE);
    let rng = ts::take_shared<Random>(&scenario);
    let hub_ref = create_hub_ref();
    let name = std::string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Join players
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    // Prepare room pool
    ts::next_tx(&mut scenario, ALICE);
    let mut room = ts::take_shared<Room<OCT>>(&scenario);
    gamehub::join_room_internal(&mut room, ts::ctx(&mut scenario));
    gamehub::ready_to_play_internal(&mut room, coin::mint_for_testing<OCT>(ENTRY_FEE * 2, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    gamehub::join_room_internal(&mut room, ts::ctx(&mut scenario));
    gamehub::ready_to_play_internal(&mut room, coin::mint_for_testing<OCT>(ENTRY_FEE * 2, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));

    // Start round (2 players, so pool = 100 * 2 = 200)
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::start_round(&rng, &mut game, &room, &clock, ts::ctx(&mut scenario));
    
    // Get current holder
    let holder = bomb_panic::debug_bomb_holder(&game);
    
    // Non-holder tries to pass - should abort
    let non_holder = if (holder == ALICE) { BOB } else { ALICE };
    ts::next_tx(&mut scenario, non_holder);
    bomb_panic::pass_bomb(&rng, &mut game, &clock, ts::ctx(&mut scenario));
    
    // Cleanup
    clock::destroy_for_testing(clock);
    ts::return_shared(rng);
    ts::return_shared(room);
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}

#[test]
fun test_try_explode_during_grace_period_does_nothing() {
    let mut scenario = ts::begin(ALICE);
    
    // Setup
    create_random(&mut scenario);
    ts::next_tx(&mut scenario, ALICE);
    let room_id = setup_room<OCT>(&mut scenario);
    
    ts::next_tx(&mut scenario, ALICE);
    let rng = ts::take_shared<Random>(&scenario);
    let hub_ref = create_hub_ref();
    let name = std::string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Join and start
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    // Prepare room pool
    ts::next_tx(&mut scenario, ALICE);
    let mut room = ts::take_shared<Room<OCT>>(&scenario);
    gamehub::join_room_internal(&mut room, ts::ctx(&mut scenario));
    gamehub::ready_to_play_internal(&mut room, coin::mint_for_testing<OCT>(ENTRY_FEE * 2, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    gamehub::join_room_internal(&mut room, ts::ctx(&mut scenario));
    gamehub::ready_to_play_internal(&mut room, coin::mint_for_testing<OCT>(ENTRY_FEE * 2, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::start_round(&rng, &mut game, &room, &clock, ts::ctx(&mut scenario));
    
    // Advance time but stay in grace period (0-10s)
    advance_clock(&mut clock, 5000); // 5 seconds - still in grace period
    
    // Try to explode - should do nothing (0% probability in grace period)
    bomb_panic::try_explode(&mut game, &clock, &rng, ts::ctx(&mut scenario));
    
    // Verify still Playing
    let phase = bomb_panic::debug_phase(&game);
    assert!(phase == 1, 1); // 1 = Playing
    
    // Cleanup
    clock::destroy_for_testing(clock);
    ts::return_shared(rng);
    ts::return_shared(room);
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}

#[test]
fun test_try_explode_after_60s_always_explodes() {
    let mut scenario = ts::begin(ALICE);
    
    // Setup
    create_random(&mut scenario);
    ts::next_tx(&mut scenario, ALICE);
    let room_id = setup_room<OCT>(&mut scenario);
    
    ts::next_tx(&mut scenario, ALICE);
    let rng = ts::take_shared<Random>(&scenario);
    let hub_ref = create_hub_ref();
    let name = std::string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Join and start
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    // Prepare room pool
    ts::next_tx(&mut scenario, ALICE);
    let mut room = ts::take_shared<Room<OCT>>(&scenario);
    gamehub::join_room_internal(&mut room, ts::ctx(&mut scenario));
    gamehub::ready_to_play_internal(&mut room, coin::mint_for_testing<OCT>(ENTRY_FEE * 2, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    gamehub::join_room_internal(&mut room, ts::ctx(&mut scenario));
    gamehub::ready_to_play_internal(&mut room, coin::mint_for_testing<OCT>(ENTRY_FEE * 2, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::start_round(&rng, &mut game, &room, &clock, ts::ctx(&mut scenario));
    
    // Advance time to 65 seconds (100% probability zone)
    advance_clock(&mut clock, 65000);
    
    // Explode - guaranteed at 60s+
    bomb_panic::try_explode(&mut game, &clock, &rng, ts::ctx(&mut scenario));
    
    // Verify Ended
    let phase = bomb_panic::debug_phase(&game);
    assert!(phase == 2, 1); // 2 = Ended
    
    // Cleanup
    clock::destroy_for_testing(clock);
    ts::return_shared(rng);
    ts::return_shared(room);
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}

#[test]
fun test_consume_settlement_intent_works_once() {
    let mut scenario = ts::begin(ALICE);
    
    // Setup
    create_random(&mut scenario);
    ts::next_tx(&mut scenario, ALICE);
    let room_id = setup_room<OCT>(&mut scenario);
    
    ts::next_tx(&mut scenario, ALICE);
    let rng = ts::take_shared<Random>(&scenario);
    let hub_ref = create_hub_ref();
    let name = std::string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Join and start
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    // Prepare room pool
    ts::next_tx(&mut scenario, ALICE);
    let mut room = ts::take_shared<Room<OCT>>(&scenario);
    gamehub::join_room_internal(&mut room, ts::ctx(&mut scenario));
    gamehub::ready_to_play_internal(&mut room, coin::mint_for_testing<OCT>(ENTRY_FEE * 2, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    gamehub::join_room_internal(&mut room, ts::ctx(&mut scenario));
    gamehub::ready_to_play_internal(&mut room, coin::mint_for_testing<OCT>(ENTRY_FEE * 2, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::start_round(&rng, &mut game, &room, &clock, ts::ctx(&mut scenario));
    
    // Explode - advance to 65s (100% zone)
    advance_clock(&mut clock, 65000);
    bomb_panic::try_explode(&mut game, &clock, &rng, ts::ctx(&mut scenario));
    
    // Consume settlement - should work
    let intent = bomb_panic::consume_settlement_intent(&mut game);
    bomb_panic::destroy_settlement_intent_for_testing(intent);
    
    // Cleanup
    clock::destroy_for_testing(clock);
    ts::return_shared(rng);
    ts::return_shared(room);
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
    let room_id = setup_room<OCT>(&mut scenario);
    
    ts::next_tx(&mut scenario, ALICE);
    let rng = ts::take_shared<Random>(&scenario);
    let hub_ref = create_hub_ref();
    let name = std::string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Join and start
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    // Prepare room pool
    ts::next_tx(&mut scenario, ALICE);
    let mut room = ts::take_shared<Room<OCT>>(&scenario);
    gamehub::join_room_internal(&mut room, ts::ctx(&mut scenario));
    gamehub::ready_to_play_internal(&mut room, coin::mint_for_testing<OCT>(ENTRY_FEE * 2, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    gamehub::join_room_internal(&mut room, ts::ctx(&mut scenario));
    gamehub::ready_to_play_internal(&mut room, coin::mint_for_testing<OCT>(ENTRY_FEE * 2, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::start_round(&rng, &mut game, &room, &clock, ts::ctx(&mut scenario));
    
    // Explode - advance to 65s (100% zone)
    advance_clock(&mut clock, 65000);
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
    ts::return_shared(room);
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}

#[test]
fun test_full_workflow_happy_path() {
    let mut scenario = ts::begin(ALICE);
    
    create_random(&mut scenario);
    ts::next_tx(&mut scenario, ALICE);
    let room_id = setup_room<OCT>(&mut scenario);
    
    ts::next_tx(&mut scenario, ALICE);
    let rng = ts::take_shared<Random>(&scenario);
    let hub_ref = create_hub_ref();
    let name = std::string::utf8(b"Happy Path");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Join 4 players
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, CAROL);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, DAVE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    // Prepare room pool
    ts::next_tx(&mut scenario, ALICE);
    let mut room = ts::take_shared<Room<OCT>>(&scenario);
    gamehub::join_room_internal(&mut room, ts::ctx(&mut scenario));
    gamehub::ready_to_play_internal(&mut room, coin::mint_for_testing<OCT>(ENTRY_FEE * 2, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    gamehub::join_room_internal(&mut room, ts::ctx(&mut scenario));
    gamehub::ready_to_play_internal(&mut room, coin::mint_for_testing<OCT>(ENTRY_FEE * 2, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, CAROL);
    gamehub::join_room_internal(&mut room, ts::ctx(&mut scenario));
    gamehub::ready_to_play_internal(&mut room, coin::mint_for_testing<OCT>(ENTRY_FEE * 2, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, DAVE);
    gamehub::join_room_internal(&mut room, ts::ctx(&mut scenario));
    gamehub::ready_to_play_internal(&mut room, coin::mint_for_testing<OCT>(ENTRY_FEE * 2, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));

    // Start round with pool = entry_fee * 4
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::start_round(&rng, &mut game, &room, &clock, ts::ctx(&mut scenario));
    
    let round_id = bomb_panic::debug_round_id(&game);
    let initial_pool = ENTRY_FEE * 4;
    
    // Identify current holder
    let holder = bomb_panic::debug_bomb_holder(&game);
    
    // As holder, pass bomb at least once
    advance_clock(&mut clock, 3000); // 3 seconds
    ts::next_tx(&mut scenario, holder);
    bomb_panic::pass_bomb(&rng, &mut game, &clock, ts::ctx(&mut scenario));
    
    let pool_after_pass = bomb_panic::debug_pool_value(&game);
    assert!(pool_after_pass < initial_pool, 0); // Pool decreased
    
    // Try explode during grace period (should no-op)
    advance_clock(&mut clock, 1000); // 1 more second (total 4s)
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
    
    // Cleanup
    bomb_panic::destroy_settlement_intent_for_testing(intent);
    clock::destroy_for_testing(clock);
    ts::return_shared(rng);
    ts::return_shared(room);
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}
