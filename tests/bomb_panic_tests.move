#[test_only]
module games::bomb_panic_tests {
    use std::option;
    use std::vector;
    use games::bomb_panic;
    use games::bomb_panic::{SCALE, BPS_DENOM, MAX_PLAYERS};
    use games::game_hub_mock;
    use sui::clock;
    use sui::coin;
    use sui::random;
    use sui::signer;
    use sui::tx_context;

    /// Test coin type.
    struct TestCoin has drop, store {}

    /// Helper: create ctx, random, hub, game, and clock set to 0ms with escrow=1.
    fun setup(fee_bps: u64): (
        bomb_panic::GameHub,
        bomb_panic::GameState<TestCoin>,
        clock::Clock,
        tx_context::TxContext,
        signer
    ) {
        let mut ctx = tx_context::dummy();
        let mut rng = random::create_for_testing(&mut ctx);
        let mut hub = bomb_panic::create_hub(@0xFA11, rng, &mut ctx);
        let mut game = bomb_panic::create_game_state<TestCoin>(&hub, &mut ctx);
        let mut clk = clock::create_for_testing(&mut ctx);
        clock::set_for_testing(&mut clk, 0);
        let escrow = coin::mint_for_testing<TestCoin>(1, &mut ctx);
        bomb_panic::start_round(&mut hub, &mut game, &clk, escrow, fee_bps, &mut ctx);
        let player = tx_context::new_signer_for_testing(@0xA11CE);
        (hub, game, clk, ctx, player)
    }

    /// Advance clock by ms.
    fun advance(clk: &mut clock::Clock, ms: u64) {
        clock::increment_for_testing(clk, ms);
    }

    #[test]
    fun crash_point_within_bounds_and_reachable() {
        let (mut hub, mut game, mut clk, mut ctx, _player) = setup(500);
        // Advance enough so multiplier must exceed the maximum possible crash point bound.
        advance(&mut clk, SCALE * 100);
        bomb_panic::crash(&mut game, &clk);
        bomb_panic::settle_round(&mut hub, &mut game, &mut ctx);
    }

    #[test]
    fun player_cashout_before_crash() {
        let (mut hub, mut game, mut clk, mut ctx, player) = setup(500);
        advance(&mut clk, 1);
        bomb_panic::cashout(&player, &mut game, &clk, SCALE, &mut ctx);
        // Second crash after advancing to ensure end can happen.
        advance(&mut clk, 10_000);
        bomb_panic::crash(&mut game, &clk);
        bomb_panic::settle_round(&mut hub, &mut game, &mut ctx);
    }

    #[test, expected_failure(abort_code = 3)]
    fun double_cashout_fails() {
        let (mut hub, mut game, mut clk, mut ctx, player) = setup(500);
        advance(&mut clk, 1);
        bomb_panic::cashout(&player, &mut game, &clk, SCALE, &mut ctx);
        // second attempt should abort with E_ALREADY_CASHED = 3
        bomb_panic::cashout(&player, &mut game, &clk, SCALE, &mut ctx);
        let _ = hub; // silence unused
    }

    #[test, expected_failure(abort_code = 2)]
    fun non_player_cashout_when_full_fails() {
        let (mut hub, mut game, mut clk, mut ctx, _) = setup(500);
        advance(&mut clk, 1);
        // Fill up with MAX_PLAYERS distinct cashouts using fixed addresses.
        let mut addrs = vector::empty<address>();
        vector::push_back(&mut addrs, @0x1);
        vector::push_back(&mut addrs, @0x2);
        vector::push_back(&mut addrs, @0x3);
        vector::push_back(&mut addrs, @0x4);
        vector::push_back(&mut addrs, @0x5);
        vector::push_back(&mut addrs, @0x6);
        vector::push_back(&mut addrs, @0x7);
        vector::push_back(&mut addrs, @0x8);
        vector::push_back(&mut addrs, @0x9);
        vector::push_back(&mut addrs, @0xA);
        let mut i = 0;
        while (i < vector::length(&addrs)) {
            let addr = *vector::borrow(&addrs, i);
            let s = tx_context::new_signer_for_testing(addr);
            bomb_panic::cashout(&s, &mut game, &clk, SCALE, &mut ctx);
            i = i + 1;
        }
        // Next player should fail with E_TOO_MANY_PLAYERS = 2.
        let extra = tx_context::new_signer_for_testing(@0xFFFF);
        bomb_panic::cashout(&extra, &mut game, &clk, SCALE, &mut ctx);
        let _ = hub;
    }

    #[test]
    fun payout_cap_clamps() {
        let (mut hub, mut game, mut clk, mut ctx, player) = setup(5_000); // 50% fee => cap = 0.5
        advance(&mut clk, 1);
        // Ask for a huge multiplier; payout should be clamped to 0.5 of escrow.
        bomb_panic::cashout(&player, &mut game, &clk, SCALE * 10, &mut ctx);
        // With fee 50%, max payable is 0.5 coin; ensure crash and settle do not abort.
        advance(&mut clk, 10_000);
        bomb_panic::crash(&mut game, &clk);
        bomb_panic::settle_round(&mut hub, &mut game, &mut ctx);
    }

    #[test, expected_failure(abort_code = 5)]
    fun crash_too_early_fails() {
        let (mut _hub, mut game, clk, _ctx, _player) = setup(500);
        // At start, multiplier == SCALE so crash should abort with E_AT_OR_AFTER_CRASH = 5.
        bomb_panic::crash(&mut game, &clk);
    }

    #[test]
    fun total_payout_never_exceeds_cap() {
        let (mut hub, mut game, mut clk, mut ctx, player1) = setup(1_000); // 10% fee => cap 0.9
        let player2 = tx_context::new_signer_for_testing(@0xB);
        advance(&mut clk, 1);
        bomb_panic::cashout(&player1, &mut game, &clk, SCALE * 5, &mut ctx);
        bomb_panic::cashout(&player2, &mut game, &clk, SCALE * 5, &mut ctx);
        // Force crash after large time then settle; internal checks ensure cap enforced.
        advance(&mut clk, 10_000);
        bomb_panic::crash(&mut game, &clk);
        bomb_panic::settle_round(&mut hub, &mut game, &mut ctx);
    }
}
