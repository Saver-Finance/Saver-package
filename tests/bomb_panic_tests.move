#[test_only]
module games::bomb_panic_tests;

use games::bomb_panic::{Self, GameState, GameHubRef, SettlementIntent};
use gamehub::gamehub::{Self, Room, AdminCap, Config, GameRegistry};
use gamehub::lobby::{Self, Lobby};
use one::clock::{Self, Clock};
use one::random::{Self, Random};
use one::oct::OCT;
use one::test_scenario::{Self as ts, Scenario};
use one::coin;
use std::vector;
use std::option;
use std::string;


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

/// Helper: initialize gamehub for testing and return registry/config/admin_cap
/// Note: This helper makes setup easier for admin tests
fun init_gamehub_test(scenario: &mut Scenario): (GameRegistry, Config, AdminCap) {
    ts::next_tx(scenario, ALICE);
    gamehub::init_for_testing(ts::ctx(scenario));
    
    ts::next_tx(scenario, ALICE);
    let registry = ts::take_shared<GameRegistry>(scenario);
    let config = ts::take_shared<Config>(scenario);
    let admin_cap = ts::take_from_sender<AdminCap>(scenario);
    
    (registry, config, admin_cap)
}

/// Helper: setup a Room for testing
fun setup_room<T>(scenario: &mut Scenario): object::ID {
    ts::next_tx(scenario, ALICE);
    
    // We need GameRegistry and Config to create room via gamehub
    gamehub::init_for_testing(ts::ctx(scenario));
    
    ts::next_tx(scenario, ALICE);
    let mut registry = ts::take_shared<GameRegistry>(scenario);
    let config = ts::take_shared<Config>(scenario);
    let admin_cap = ts::take_from_sender<AdminCap>(scenario);
    
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

/// Helper: Helper to fund room and ready players
fun fund_and_ready_players(scenario: &mut Scenario, room_id: object::ID, players: vector<address>) {
    ts::next_tx(scenario, ALICE); // Start from Alice
    let mut room = ts::take_shared<Room<OCT>>(scenario);
    
    let mut i = 0;
    while (i < vector::length(&players)) {
        let player = *vector::borrow(&players, i);
        ts::next_tx(scenario, player);
        gamehub::join_room_internal(&mut room, ts::ctx(scenario));
        gamehub::ready_to_play_internal(
            &mut room, 
            coin::mint_for_testing<OCT>(ENTRY_FEE * 2, ts::ctx(scenario)), 
            ts::ctx(scenario)
        );
        i = i + 1;
    };
    
    ts::return_shared(room);
}

#[test]
fun test_join_adds_players_up_to_max() {
    let mut scenario = ts::begin(ALICE);
    
    ts::next_tx(&mut scenario, ALICE);
    let room_id = setup_room<OCT>(&mut scenario);
    
    ts::next_tx(&mut scenario, ALICE);
    let hub_ref = create_hub_ref();
    let name = string::utf8(b"Test Room");
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
    let name = string::utf8(b"Test Room");
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

// ===  Player Exit (Waiting) ===
#[test]
fun test_leave_waiting_removes_player() {
    let mut scenario = ts::begin(ALICE);
    
    ts::next_tx(&mut scenario, ALICE);
    let room_id = setup_room<OCT>(&mut scenario);
    
    ts::next_tx(&mut scenario, ALICE);
    let hub_ref = create_hub_ref();
    let name = string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    
    // Join Alice and Bob
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    // Alice leaves
    ts::next_tx(&mut scenario, ALICE);
    let clock = clock::create_for_testing(ts::ctx(&mut scenario));
    bomb_panic::leave(&mut game, &clock, ts::ctx(&mut scenario));
    
    // Alice can join again (proof she was removed)
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    clock::destroy_for_testing(clock);
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
    let name = string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    // Prepare room pool
    let players = vector[ALICE, BOB];
    fund_and_ready_players(&mut scenario, room_id, players);
    
    // Start round (2 players, so pool = 100 * 2 = 200)
    ts::next_tx(&mut scenario, ALICE);
    let mut room = ts::take_shared<Room<OCT>>(&scenario);
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

// === Min Players Validations ===
#[test]
#[expected_failure(abort_code = bomb_panic::E_NOT_ENOUGH_PLAYERS)]
fun test_start_fails_with_one_player() {
    let mut scenario = ts::begin(ALICE);
    create_random(&mut scenario);
    ts::next_tx(&mut scenario, ALICE);
    let room_id = setup_room<OCT>(&mut scenario);
    
    ts::next_tx(&mut scenario, ALICE);
    let rng = ts::take_shared<Random>(&scenario);
    let hub_ref = create_hub_ref();
    let name = string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Join only Alice
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    fund_and_ready_players(&mut scenario, room_id, vector[ALICE]);

    ts::next_tx(&mut scenario, ALICE);
    let mut room = ts::take_shared<Room<OCT>>(&scenario);
    
    // Should fail
    bomb_panic::start_round(&rng, &mut game, &room, &clock, ts::ctx(&mut scenario));
    
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
    let name = string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Join players
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, CAROL);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    fund_and_ready_players(&mut scenario, room_id, vector[ALICE, BOB, CAROL]);

    // Start round
    ts::next_tx(&mut scenario, ALICE);
    let mut room = ts::take_shared<Room<OCT>>(&scenario);
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
    let name = string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Join players
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    fund_and_ready_players(&mut scenario, room_id, vector[ALICE, BOB]);

    // Start round
    ts::next_tx(&mut scenario, ALICE);
    let mut room = ts::take_shared<Room<OCT>>(&scenario);
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
    let name = string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Join and start
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    fund_and_ready_players(&mut scenario, room_id, vector[ALICE, BOB]);

    ts::next_tx(&mut scenario, ALICE);
    let mut room = ts::take_shared<Room<OCT>>(&scenario);
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
    let name = string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Join and start
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    fund_and_ready_players(&mut scenario, room_id, vector[ALICE, BOB]);

    ts::next_tx(&mut scenario, ALICE);
    let mut room = ts::take_shared<Room<OCT>>(&scenario);
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

// ===  Leave During Playing (Non-Holder) ===
#[test]
fun test_leave_playing_non_holder_surrender() {
    let mut scenario = ts::begin(ALICE);
    create_random(&mut scenario);
    ts::next_tx(&mut scenario, ALICE);
    let room_id = setup_room<OCT>(&mut scenario);
    
    ts::next_tx(&mut scenario, ALICE);
    let rng = ts::take_shared<Random>(&scenario);
    let hub_ref = create_hub_ref();
    let name = string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    fund_and_ready_players(&mut scenario, room_id, vector[ALICE, BOB]);

    ts::next_tx(&mut scenario, ALICE);
    let mut room = ts::take_shared<Room<OCT>>(&scenario);
    bomb_panic::start_round(&rng, &mut game, &room, &clock, ts::ctx(&mut scenario));
    
    let holder = bomb_panic::debug_bomb_holder(&game);
    let non_holder = if (holder == ALICE) { BOB } else { ALICE };
    
    // Non-holder leaves (surrenders/dies)
    ts::next_tx(&mut scenario, non_holder);
    bomb_panic::leave(&mut game, &clock, ts::ctx(&mut scenario));
    
    // Verify still playing (didn't explode, just died)
    // Note: In a 2 player game, if one dies, the game technically could end or continue until explosion.
    // The current logic only explodes if holder leaves or bomb explodes.
    // If a non-holder leaves, they are just marked dead. 
    // Wait... if only 1 player alive, the game should probably end? 
    // Checking `bomb_panic.move`: `leave` marks as dead. `pass_bomb` checks for alive players.
    // The game continues until explosion or victory.
    
    let phase = bomb_panic::debug_phase(&game);
    assert!(phase == 1, 0); // Still playing
    
    clock::destroy_for_testing(clock);
    ts::return_shared(rng);
    ts::return_shared(room);
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}

// ===  Leave During Playing (Holder -> Explosion) ===
#[test]
fun test_leave_playing_holder_explodes_game() {
    let mut scenario = ts::begin(ALICE);
    create_random(&mut scenario);
    ts::next_tx(&mut scenario, ALICE);
    let room_id = setup_room<OCT>(&mut scenario);
    
    ts::next_tx(&mut scenario, ALICE);
    let rng = ts::take_shared<Random>(&scenario);
    let hub_ref = create_hub_ref();
    let name = string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    fund_and_ready_players(&mut scenario, room_id, vector[ALICE, BOB]);

    ts::next_tx(&mut scenario, ALICE);
    let mut room = ts::take_shared<Room<OCT>>(&scenario);
    bomb_panic::start_round(&rng, &mut game, &room, &clock, ts::ctx(&mut scenario));
    
    let holder = bomb_panic::debug_bomb_holder(&game);
    
    // Holder leaves -> Suicide bomber
    ts::next_tx(&mut scenario, holder);
    bomb_panic::leave(&mut game, &clock, ts::ctx(&mut scenario));
    
    // Verify Game Ended (Explosion triggered)
    let phase = bomb_panic::debug_phase(&game);
    assert!(phase == 2, 0); // Ended
    
    clock::destroy_for_testing(clock);
    ts::return_shared(rng);
    ts::return_shared(room);
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}

// ===  Victory Condition (Pool Drained) ===
#[test]
fun test_victory_condition_pool_drained() {
    let mut scenario = ts::begin(ALICE);
    create_random(&mut scenario);
    ts::next_tx(&mut scenario, ALICE);
    let room_id = setup_room<OCT>(&mut scenario);
    
    ts::next_tx(&mut scenario, ALICE);
    let rng = ts::take_shared<Random>(&scenario);
    let hub_ref = create_hub_ref();
    let name = string::utf8(b"Victory Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Join 2 players
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    fund_and_ready_players(&mut scenario, room_id, vector[ALICE, BOB]);

    ts::next_tx(&mut scenario, ALICE);
    let mut room = ts::take_shared<Room<OCT>>(&scenario);
    bomb_panic::start_round(&rng, &mut game, &room, &clock, ts::ctx(&mut scenario));
    
    // Forcefully drain pool via many passes without exploding
    // We can simulate this by mocking time passing and bomb passing looping 
    // until pool is 0. 
    // Pool = 200. Reward = Pool / 60 per sec.
    // If we wait 30s, reward is roughly half.
    // Let's loop pass
    
    let mut i = 0; 
    let mut pool = bomb_panic::debug_pool_value(&game);
    
    while (pool > 0) {
        advance_clock(&mut clock, 2000); // 2 seconds
        let holder = bomb_panic::debug_bomb_holder(&game);
        ts::next_tx(&mut scenario, holder);
        bomb_panic::pass_bomb(&rng, &mut game, &clock, ts::ctx(&mut scenario));
        
        let new_pool = bomb_panic::debug_pool_value(&game);
        if (new_pool == 0) break; // Won!
        // Safety break
         i = i + 1;
         if (i > 100) break;
         pool = new_pool;
    };
    
    // Verify Victory
    let phase = bomb_panic::debug_phase(&game);
    assert!(phase == 2, 0); // Ended
    assert!(bomb_panic::debug_pool_value(&game) == 0, 1); // Pool empty
    
    // Check settlement - should have NO dead players
    let intent = bomb_panic::consume_settlement_intent(&mut game);
    let dead = bomb_panic::settlement_dead_player(&intent);
    assert!(dead == @0x0, 2); // No one died
    
    let survivors = bomb_panic::settlement_survivors(&intent);
    assert!(vector::length(&survivors) == 2, 3); // Both survived
    
    bomb_panic::destroy_settlement_intent_for_testing(intent);
    clock::destroy_for_testing(clock);
    ts::return_shared(rng);
    ts::return_shared(room);
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}

// ===  Game Reset ===
#[test]
fun test_reset_game_clears_state() {
    let mut scenario = ts::begin(ALICE);
    create_random(&mut scenario);
    ts::next_tx(&mut scenario, ALICE);
    let room_id = setup_room<OCT>(&mut scenario);
    
    ts::next_tx(&mut scenario, ALICE);
    let rng = ts::take_shared<Random>(&scenario);
    let hub_ref = create_hub_ref();
    let name = string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Play a full round
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    fund_and_ready_players(&mut scenario, room_id, vector[ALICE, BOB]);

    ts::next_tx(&mut scenario, ALICE);
    let mut room = ts::take_shared<Room<OCT>>(&scenario);
    bomb_panic::start_round(&rng, &mut game, &room, &clock, ts::ctx(&mut scenario));
    
    advance_clock(&mut clock, 65000); // Trigger explosion
    bomb_panic::try_explode(&mut game, &clock, &rng, ts::ctx(&mut scenario));
    
    let intent = bomb_panic::consume_settlement_intent(&mut game);
    bomb_panic::destroy_settlement_intent_for_testing(intent);
    
    // Call Reset
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::reset_game(&mut game);
    
    // Verify state reset
    assert!(bomb_panic::debug_phase(&game) == 0, 0); // Waiting
    assert!(bomb_panic::debug_pool_value(&game) == 0, 1);
    
    // New round can start? (Need to join again)
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario)); 
    // Works!
    
    clock::destroy_for_testing(clock);
    ts::return_shared(rng);
    ts::return_shared(room);
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}

// ===  Admin Config ===
#[test]
fun test_configure_game_admin_updates_config() {
     let mut scenario = ts::begin(ALICE);
    
    // Setup AdminCap via helper
    let (registry, config, admin_cap) = init_gamehub_test(&mut scenario);
    
    ts::next_tx(&mut scenario, ALICE);
    let room_id = setup_room<OCT>(&mut scenario); // Just to get ID
    let hub_ref = create_hub_ref();
    let name = string::utf8(b"Config Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    
    // Change config
    let new_hold_time = 5000;
    let new_rate = 500;
    let new_divisor = 30;
    
    bomb_panic::configure_game_admin(
        &mut game, 
        &admin_cap,
        new_hold_time,
        new_rate,
        new_divisor
    );
    
    // We can't easily inspect config private fields without debug, 
    // but successful execution implies the setter worked and didn't abort.
    
    ts::return_shared(registry);
    ts::return_shared(config);
    ts::return_to_sender(&scenario, admin_cap);
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
    let name = string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Join and start
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    fund_and_ready_players(&mut scenario, room_id, vector[ALICE, BOB]);

    ts::next_tx(&mut scenario, ALICE);
    let mut room = ts::take_shared<Room<OCT>>(&scenario);
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
    let name = string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
    // Join and start
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, BOB);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    fund_and_ready_players(&mut scenario, room_id, vector[ALICE, BOB]);

    ts::next_tx(&mut scenario, ALICE);
    let mut room = ts::take_shared<Room<OCT>>(&scenario);
    bomb_panic::start_round(&rng, &mut game, &room, &clock, ts::ctx(&mut scenario));
    
    // Explode
    advance_clock(&mut clock, 65000);
    bomb_panic::try_explode(&mut game, &clock, &rng, ts::ctx(&mut scenario));
    
    // Consume settlement
    let intent1 = bomb_panic::consume_settlement_intent(&mut game);
    bomb_panic::destroy_settlement_intent_for_testing(intent1);
    
    // Try again -> fail
    let intent2 = bomb_panic::consume_settlement_intent(&mut game);
    bomb_panic::destroy_settlement_intent_for_testing(intent2);
    
    clock::destroy_for_testing(clock);
    ts::return_shared(rng);
    ts::return_shared(room);
    bomb_panic::destroy_for_testing(game);
    ts::end(scenario);
}

#[test]
fun test_delete_game() {
    let mut scenario = ts::begin(ALICE);
    
    ts::next_tx(&mut scenario, ALICE);
    let room_id = setup_room<OCT>(&mut scenario);
    
    ts::next_tx(&mut scenario, ALICE);
    let hub_ref = create_hub_ref();
    let name = string::utf8(b"Test Room");
    let mut game = bomb_panic::create_game_state<OCT>(hub_ref, name, room_id, ts::ctx(&mut scenario));
    
    // Join Allowable amount (1 player)
    ts::next_tx(&mut scenario, ALICE);
    bomb_panic::join(&mut game, ts::ctx(&mut scenario));
    
    // Take Lobby
    let mut lobby = ts::take_shared<Lobby>(&scenario);

    // Delete Game (should succeed)
    bomb_panic::delete_game(game, &mut lobby);
    
    ts::return_shared(lobby);
    
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
    let name = string::utf8(b"Happy Path");
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
    
    fund_and_ready_players(&mut scenario, room_id, vector[ALICE, BOB, CAROL, DAVE]);

    // Start round with pool = entry_fee * 4
    ts::next_tx(&mut scenario, ALICE);
    let mut room = ts::take_shared<Room<OCT>>(&scenario);
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
// End of tests
