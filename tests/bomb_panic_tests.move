#[test_only]
module games::bomb_panic_tests;

use games::bomb_panic;
use sui::clock;
use sui::coin;
use sui::random::{Self, Random};
use sui::sui::SUI;
use sui::test_scenario;

const SCALE: u64 = 10_000;

/// Helper: create ctx, random, hub, game, and clock set to 0ms with escrow=1.
fun setup(
    fee_bps: u64,
    scenario: &mut test_scenario::Scenario,
): (bomb_panic::GameHub, bomb_panic::GameState<SUI>, clock::Clock, Random) {
    // TX1: must be system sender to create Random
    test_scenario::next_tx(scenario, @0x0);
    {
        let ctx = test_scenario::ctx(scenario);
        random::create_for_testing(ctx);
    };

    // TX2: switch back to normal user
    test_scenario::next_tx(scenario, @0xA11CE);

    // take shared RNG BEFORE ctx
    let rng = test_scenario::take_shared<Random>(scenario);
    let ctx = test_scenario::ctx(scenario);

    let mut hub = bomb_panic::create_hub(@0xFA11, &rng, ctx);
    let mut game = bomb_panic::create_game_state<SUI>(&hub, ctx);

    let mut clk = clock::create_for_testing(ctx);
    clock::set_for_testing(&mut clk, 0);

    let escrow = coin::mint_for_testing<SUI>(1_000_000, ctx);
    bomb_panic::start_round(&mut hub, &rng, &mut game, &clk, escrow, fee_bps, ctx);

    (hub, game, clk, rng)
}

/// Advance clock by ms.
fun advance(clk: &mut clock::Clock, ms: u64) {
    clock::increment_for_testing(clk, ms);
}

//

// PASSED
// #[test]
// fun crash_point_within_bounds_and_reachable() {
//     let mut scenario = test_scenario::begin(@0xA11CE);
//     let (mut hub, mut game, mut clk, rng) = setup(500, &mut scenario);

//     advance(&mut clk, SCALE * 100);
//     bomb_panic::crash(&mut game, &clk);

//     {
//         let ctx = test_scenario::ctx(&mut scenario);
//         bomb_panic::settle_round(&mut hub, &mut game, ctx);
//     };

//     sui::transfer::public_transfer(hub, @0xA11CE);
//     sui::transfer::public_transfer(game, @0xA11CE);

//     test_scenario::return_shared(rng);

//     // consume the local clock properly
//     clock::destroy_for_testing(clk);

//     test_scenario::end(scenario);
// }

//this have threshold to player only have a max payout
// #[test]
// fun player_cashout_before_crash() {
//     use std::debug;

//     let mut scenario = test_scenario::begin(@0xBEEF);
//     let (mut hub, mut game, mut clk, rng) = setup(500, &mut scenario);

//     // start logs
//     debug::print(&bomb_panic::debug_crash_point(&game));
//     debug::print(&bomb_panic::debug_state(&game));

//     // move time forward enough so current_mult >= 2x
//     advance(&mut clk, SCALE); // big jump

//     let m = SCALE * 2; // 2.0x desired
//     debug::print(&clock::timestamp_ms(&clk));
//     debug::print(&m);
//     debug::print(&bomb_panic::debug_total_wager(&game));
//     debug::print(&bomb_panic::debug_reserved(&game));

//     {
//         let ctx = test_scenario::ctx(&mut scenario);
//         bomb_panic::cashout(&mut game, &clk, m, ctx);
//     };

//     debug::print(&bomb_panic::debug_reserved(&game));

//     // force crash
//     advance(&mut clk, SCALE * 200);
//     bomb_panic::crash(&mut game, &clk);

//     {
//         let ctx = test_scenario::ctx(&mut scenario);
//         bomb_panic::settle_round(&mut hub, &mut game, ctx);
//     };

//     sui::transfer::public_transfer(hub, @0xA11CE);
//     sui::transfer::public_transfer(game, @0xA11CE);

//     test_scenario::return_shared(rng);
//     clock::destroy_for_testing(clk);
//     test_scenario::end(scenario);
// }
// Too many player test
// #[test, expected_failure(abort_code = 2, location = games::bomb_panic)]
// fun non_player_cashout_when_full_fails() {
//     let mut scenario = test_scenario::begin(@0xA11CE);
//     let (hub, mut game, mut clk, rng) = setup(500, &mut scenario);

//     advance(&mut clk, 1);

//     let mut addrs = vector::empty<address>();
//     vector::push_back(&mut addrs, @0x1);
//     vector::push_back(&mut addrs, @0x2);
//     vector::push_back(&mut addrs, @0x3);
//     vector::push_back(&mut addrs, @0x4);
//     vector::push_back(&mut addrs, @0x5);
//     vector::push_back(&mut addrs, @0x6);
//     vector::push_back(&mut addrs, @0x7);
//     vector::push_back(&mut addrs, @0x8);
//     vector::push_back(&mut addrs, @0x9);
//     vector::push_back(&mut addrs, @0xA);

//     let mut i = 0;
//     while (i < vector::length(&addrs)) {
//         let addr = *vector::borrow(&addrs, i);
//         test_scenario::next_tx(&mut scenario, addr);
//         {
//             let ctx = test_scenario::ctx(&mut scenario);
//             bomb_panic::cashout(&mut game, &clk, SCALE, ctx);
//         };
//         i = i + 1;
//     };

//     test_scenario::next_tx(&mut scenario, @0xFFFF);
//     {
//         let ctx = test_scenario::ctx(&mut scenario);
//         sui::transfer::public_transfer(hub, @0x0);
//         // expected abort here
//         bomb_panic::cashout(&mut game, &clk, SCALE, ctx);
//     };

//     // unreachable
//     sui::transfer::public_transfer(game, @0xA11CE);
//     test_scenario::return_shared(rng);
//     clock::destroy_for_testing(clk);
//     test_scenario::end(scenario);
// }

// #[test, expected_failure(abort_code = 3, location = games::bomb_panic)]
// fun double_cashout_fails() {
//     let mut scenario = test_scenario::begin(@0xA11CE);
//     let (hub, mut game, mut clk, rng) = setup(500, &mut scenario);

//     advance(&mut clk, 1);

//     {
//         let ctx = test_scenario::ctx(&mut scenario);
//         bomb_panic::cashout(&mut game, &clk, SCALE, ctx);
//     };

//     // second attempt should abort with E_ALREADY_CASHED = 3
//     {
//         let ctx = test_scenario::ctx(&mut scenario);
//         sui::transfer::public_transfer(hub, @0x0);
//         bomb_panic::cashout(&mut game, &clk, SCALE, ctx);
//     };

//     // unreachable (abort happens above) - consume non-drop locals to satisfy compiler
//     sui::transfer::public_transfer(game, @0xA11CE);
//     test_scenario::return_shared(rng);
//     clock::destroy_for_testing(clk);
//     test_scenario::end(scenario);
// }

// #[test]
// fun payout_cap_clamps() {
//     use std::debug;

//     let mut scenario = test_scenario::begin(@0xA11CE);
//     let (mut hub, mut game, mut clk, rng) = setup(5_000, &mut scenario); // 50% fee

//     // start: crash point + state
//     debug::print(&bomb_panic::debug_crash_point(&game));
//     debug::print(&bomb_panic::debug_state(&game));
//     debug::print(&bomb_panic::debug_total_wager(&game));
//     debug::print(&bomb_panic::debug_reserved(&game));

//     // Make sure current_mult >= 10x
//     advance(&mut clk, SCALE * 20);
//     debug::print(&clock::timestamp_ms(&clk)); // time now
//     let m = SCALE * 10;
//     debug::print(&m); // desired multiplier (10x)

//     {
//         let ctx = test_scenario::ctx(&mut scenario);
//         bomb_panic::cashout(&mut game, &clk, m, ctx);
//     };

//     // After cashout: reserved should be clamped by cap
//     debug::print(&bomb_panic::debug_reserved(&game));

//     // Force crash to be allowed
//     advance(&mut clk, SCALE * 200);
//     bomb_panic::crash(&mut game, &clk);

//     // After crash
//     debug::print(&bomb_panic::debug_ended_mult(&game));
//     debug::print(&bomb_panic::debug_end_ts(&game));

//     {
//         let ctx = test_scenario::ctx(&mut scenario);
//         bomb_panic::settle_round(&mut hub, &mut game, ctx);
//     };

//     // After settle (your settle resets to Waiting + clears reserved)
//     debug::print(&bomb_panic::debug_state(&game));
//     debug::print(&bomb_panic::debug_reserved(&game));

//     sui::transfer::public_transfer(hub, @0xA11CE);
//     sui::transfer::public_transfer(game, @0xA11CE);

//     test_scenario::return_shared(rng);
//     clock::destroy_for_testing(clk);
//     test_scenario::end(scenario);
// }

// #[test, expected_failure(abort_code = 5, location = games::bomb_panic)]
// fun crash_too_early_fails() {
//     let mut scenario = test_scenario::begin(@0xA11CE);
//     let (_hub, mut game, clk, _rng) = setup(500, &mut scenario);

//     // should abort with 5
//     bomb_panic::crash(&mut game, &clk);

//     // if it *didn't* abort (bug), force an abort so the function never returns
//     abort 0
// }

// #[test]
// fun total_payout_never_exceeds_cap() {
//     use std::debug;

//     let mut scenario = test_scenario::begin(@0xA11CE);
//     let (mut hub, mut game, mut clk, rng) = setup(1_000, &mut scenario); // 10% fee

//     // make sure current_mult >= 5x
//     advance(&mut clk, SCALE * 10);

//     debug::print(&bomb_panic::debug_total_wager(&game));
//     debug::print(&bomb_panic::debug_reserved(&game));

//     // player A cashout
//     {
//         let ctx = test_scenario::ctx(&mut scenario);
//         bomb_panic::cashout(&mut game, &clk, SCALE * 5, ctx);
//     };
//     debug::print(&bomb_panic::debug_reserved(&game));

//     // player B cashout
//     test_scenario::next_tx(&mut scenario, @0xB);
//     {
//         let ctx = test_scenario::ctx(&mut scenario);
//         bomb_panic::cashout(&mut game, &clk, SCALE * 5, ctx);
//     };
//     debug::print(&bomb_panic::debug_reserved(&game));

//     // force crash
//     advance(&mut clk, SCALE * 200);
//     bomb_panic::crash(&mut game, &clk);

//     {
//         let ctx = test_scenario::ctx(&mut scenario);
//         bomb_panic::settle_round(&mut hub, &mut game, ctx);
//     };

//     sui::transfer::public_transfer(hub, @0xA11CE);
//     sui::transfer::public_transfer(game, @0xA11CE);

//     test_scenario::return_shared(rng);
//     clock::destroy_for_testing(clk);
//     test_scenario::end(scenario);
// }
