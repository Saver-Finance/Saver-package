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
        next_tx(scenario, PLAYER_1);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(scenario);
            let config = test_scenario::take_shared<Config>(scenario);
            gamehub::start_room(&mut room, &config, ctx(scenario));
            test_scenario::return_shared(room);
            test_scenario::return_shared(config);
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

    #[test]
    fun test_delete_room() {
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

        // Delete Room (should work with 1 player)
        next_tx(&mut scenario, ADMIN);
        {
            let room = test_scenario::take_shared<Room<OCT>>(&scenario);
            gamehub::delete_room(room, ctx(&mut scenario));
            // room is consumed, so we don't return it
        };
        
        test_scenario::end(scenario);
    }
}