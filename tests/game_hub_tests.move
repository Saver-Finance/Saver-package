#[test_only]
module gamehub::gamehub_tests {
    use gamehub::gamehub::{Self, GameRegistry, Config, Room, AdminCap};
    use one::test_scenario::{Self, next_tx, ctx};
    use one::coin::{Self, Coin};
    use one::oct::OCT;

    public struct ROCK_PAPER_SCISSORS {}

    const ADMIN: address = @0xA;
    const PLAYER_1: address = @0xB;
    const PLAYER_2: address = @0xC;
    const INSURANCE: address = @0xD;

    #[test]
    fun test_game_flow_with_ready_mechanism() {
        // 1. Initialize Scenario
        let mut scenario = test_scenario::begin(ADMIN);
        
        // --- Step 1: Initialize Module (Init) ---
        {
            gamehub::init_for_testing(ctx(&mut scenario));
        };

        // --- Step 2: Admin updates Config & Registers Game ---
        next_tx(&mut scenario, ADMIN);
        {
            let mut registry = test_scenario::take_shared<GameRegistry>(&scenario);
            let mut config = test_scenario::take_shared<Config>(&scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);

            // Set fee rate to 10% (100 / 1000), room creation fee to 0
            gamehub::update_config(&mut config, &admin_cap, 100, INSURANCE, 0);

            // Register game and get GameCap
            let game_cap = gamehub::register_game<ROCK_PAPER_SCISSORS>(&mut registry, &admin_cap, b"Rock Paper Scissors", ctx(&mut scenario));

            test_scenario::return_shared(registry);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&scenario, admin_cap);
            transfer::public_transfer(game_cap, ADMIN);
        };

        // --- Step 3: Create Room (with 0 creation fee) ---
        next_tx(&mut scenario, ADMIN);
        {
            let registry = test_scenario::take_shared<GameRegistry>(&scenario);
            let config = test_scenario::take_shared<Config>(&scenario);
            
            // Create zero-value coin for creation fee
            let creation_fee = coin::mint_for_testing<OCT>(0, ctx(&mut scenario));
            
            // Create room with entry fee of 10 OCT, max 2 players
            let entry_fee = 10_000_000_000; // 10 OCT
            gamehub::create_room<OCT, ROCK_PAPER_SCISSORS>(
                &registry, 
                &config,
                entry_fee, 
                2, 
                creation_fee,
                ctx(&mut scenario)
            );

            test_scenario::return_shared(registry);
            test_scenario::return_shared(config);
        };

        // --- Step 4: Player 1 joins (no fee yet) ---
        next_tx(&mut scenario, PLAYER_1);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            
            // Join without coin
            gamehub::join_room(&mut room, ctx(&mut scenario));
            
            test_scenario::return_shared(room);
        };

        // --- Step 5: Player 1 signals ready (pays entry fee) ---
        next_tx(&mut scenario, PLAYER_1);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            let entry_fee = 10_000_000_000;
            
            // Mint coin for entry fee (OCT requires 2x entry fee)
            let coin = coin::mint_for_testing<OCT>(entry_fee * 2, ctx(&mut scenario));
            
            gamehub::ready_to_play(&mut room, coin, ctx(&mut scenario));
            
            test_scenario::return_shared(room);
        };

        // --- Step 6: Player 2 joins and readies ---
        next_tx(&mut scenario, PLAYER_2);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            let entry_fee = 10_000_000_000;
            
            // Join
            gamehub::join_room(&mut room, ctx(&mut scenario));
            
            // Ready with entry fee (OCT requires 2x entry fee)
            let coin = coin::mint_for_testing<OCT>(entry_fee * 2, ctx(&mut scenario));
            gamehub::ready_to_play(&mut room, coin, ctx(&mut scenario));
            
            test_scenario::return_shared(room);
        };

        // --- Step 7: Player 1 starts game ---
        next_tx(&mut scenario, PLAYER_1);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            let config = test_scenario::take_shared<Config>(&scenario);

            gamehub::start_room(&mut room, &config, ctx(&mut scenario));

            test_scenario::return_shared(room);
            test_scenario::return_shared(config);
        };

        // --- Step 8: Admin settles (Player 1 wins remaining pool) ---
        // Pool was 20 OCT, 10% fee = 2 OCT to insurance, remaining = 18 OCT
        next_tx(&mut scenario, ADMIN);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            let game_cap = test_scenario::take_from_sender<gamehub::GameCap>(&scenario);

            let addresses = vector[PLAYER_1, PLAYER_2];
            let amounts = vector[18_000_000_000, 0]; // Player 1 wins all remaining

            gamehub::settle(&mut room, addresses, amounts, &game_cap, ctx(&mut scenario));

            test_scenario::return_shared(room);
            test_scenario::return_to_sender(&scenario, game_cap);
        };

        // --- Step 9: Verify Player 1 balance ---
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
            // Fee 10% of 20 OCT = 2 OCT
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
        
        // Init
        {
            gamehub::init_for_testing(ctx(&mut scenario));
        };

        // Register game
        next_tx(&mut scenario, ADMIN);
        {
            let mut registry = test_scenario::take_shared<GameRegistry>(&scenario);
            let mut config = test_scenario::take_shared<Config>(&scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);

            gamehub::update_config(&mut config, &admin_cap, 100, INSURANCE, 0);
            let game_cap = gamehub::register_game<ROCK_PAPER_SCISSORS>(&mut registry, &admin_cap, b"Test", ctx(&mut scenario));

            test_scenario::return_shared(registry);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&scenario, admin_cap);
            transfer::public_transfer(game_cap, ADMIN);
        };

        // Create room
        next_tx(&mut scenario, ADMIN);
        {
            let registry = test_scenario::take_shared<GameRegistry>(&scenario);
            let config = test_scenario::take_shared<Config>(&scenario);
            let creation_fee = coin::mint_for_testing<OCT>(0, ctx(&mut scenario));
            
            gamehub::create_room<OCT, ROCK_PAPER_SCISSORS>(
                &registry, &config, 10_000_000_000, 2, creation_fee, ctx(&mut scenario)
            );

            test_scenario::return_shared(registry);
            test_scenario::return_shared(config);
        };

        // Player 1 joins and readies
        next_tx(&mut scenario, PLAYER_1);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            
            gamehub::join_room(&mut room, ctx(&mut scenario));
            
            let coin = coin::mint_for_testing<OCT>(20_000_000_000, ctx(&mut scenario));
            gamehub::ready_to_play(&mut room, coin, ctx(&mut scenario));
            
            // Verify pool has entry fee (OCT rule: provide 2x, take 1x)
            assert!(gamehub::get_pool_value(&room) == 10_000_000_000, 0);
            
            test_scenario::return_shared(room);
        };

        // Player 1 cancels ready
        next_tx(&mut scenario, PLAYER_1);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            
            gamehub::cancel_ready(&mut room, ctx(&mut scenario));
            
            // Verify pool is empty
            assert!(gamehub::get_pool_value(&room) == 0, 1);
            
            test_scenario::return_shared(room);
        };

        // Verify Player 1 got one of the refunded coins (10 OCT)
        next_tx(&mut scenario, PLAYER_1);
        {
            let coin = test_scenario::take_from_sender<Coin<OCT>>(&scenario);
            assert!(coin::value(&coin) == 10_000_000_000, 2);
            test_scenario::return_to_sender(&scenario, coin);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 13)] // ENotAllPlayersReady
    fun test_start_fails_if_not_all_ready() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Init
        {
            gamehub::init_for_testing(ctx(&mut scenario));
        };

        // Register game
        next_tx(&mut scenario, ADMIN);
        {
            let mut registry = test_scenario::take_shared<GameRegistry>(&scenario);
            let mut config = test_scenario::take_shared<Config>(&scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);

            gamehub::update_config(&mut config, &admin_cap, 0, INSURANCE, 0);
            let game_cap = gamehub::register_game<ROCK_PAPER_SCISSORS>(&mut registry, &admin_cap, b"Test", ctx(&mut scenario));

            test_scenario::return_shared(registry);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&scenario, admin_cap);
            transfer::public_transfer(game_cap, ADMIN);
        };

        // Create room
        next_tx(&mut scenario, ADMIN);
        {
            let registry = test_scenario::take_shared<GameRegistry>(&scenario);
            let config = test_scenario::take_shared<Config>(&scenario);
            let creation_fee = coin::mint_for_testing<OCT>(0, ctx(&mut scenario));
            
            gamehub::create_room<OCT, ROCK_PAPER_SCISSORS>(
                &registry, &config, 10_000_000_000, 2, creation_fee, ctx(&mut scenario)
            );

            test_scenario::return_shared(registry);
            test_scenario::return_shared(config);
        };

        // Player 1 joins and readies
        next_tx(&mut scenario, PLAYER_1);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            gamehub::join_room(&mut room, ctx(&mut scenario));
            let coin = coin::mint_for_testing<OCT>(20_000_000_000, ctx(&mut scenario));
            gamehub::ready_to_play(&mut room, coin, ctx(&mut scenario));
            test_scenario::return_shared(room);
        };

        // Player 2 joins but does NOT ready
        next_tx(&mut scenario, PLAYER_2);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            gamehub::join_room(&mut room, ctx(&mut scenario));
            // NO ready_to_play call!
            test_scenario::return_shared(room);
        };

        // Try to start - should fail
        next_tx(&mut scenario, PLAYER_1);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            let config = test_scenario::take_shared<Config>(&scenario);

            gamehub::start_room(&mut room, &config, ctx(&mut scenario));

            test_scenario::return_shared(room);
            test_scenario::return_shared(config);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_re_ready_after_cancel() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Init
        {
            gamehub::init_for_testing(ctx(&mut scenario));
        };

        // Register game
        next_tx(&mut scenario, ADMIN);
        {
            let mut registry = test_scenario::take_shared<GameRegistry>(&scenario);
            let mut config = test_scenario::take_shared<Config>(&scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            gamehub::update_config(&mut config, &admin_cap, 0, INSURANCE, 0);
            let game_cap = gamehub::register_game<ROCK_PAPER_SCISSORS>(&mut registry, &admin_cap, b"Test", ctx(&mut scenario));
            test_scenario::return_shared(registry);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&scenario, admin_cap);
            transfer::public_transfer(game_cap, ADMIN);
        };

        // Create room
        next_tx(&mut scenario, ADMIN);
        {
            let registry = test_scenario::take_shared<GameRegistry>(&scenario);
            let config = test_scenario::take_shared<Config>(&scenario);
            let creation_fee = coin::mint_for_testing<OCT>(0, ctx(&mut scenario));
            gamehub::create_room<OCT, ROCK_PAPER_SCISSORS>(&registry, &config, 10_000_000_000, 2, creation_fee, ctx(&mut scenario));
            test_scenario::return_shared(registry);
            test_scenario::return_shared(config);
        };

        // Player 1: join -> ready -> cancel -> ready again
        next_tx(&mut scenario, PLAYER_1);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            gamehub::join_room(&mut room, ctx(&mut scenario));
            let coin1 = coin::mint_for_testing<OCT>(20_000_000_000, ctx(&mut scenario));
            gamehub::ready_to_play(&mut room, coin1, ctx(&mut scenario));
            test_scenario::return_shared(room);
        };

        next_tx(&mut scenario, PLAYER_1);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            gamehub::cancel_ready(&mut room, ctx(&mut scenario));
            test_scenario::return_shared(room);
        };

        next_tx(&mut scenario, PLAYER_1);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            // Mint a fresh coin for ready (OCT requires 2x entry fee)
            let coin = coin::mint_for_testing<OCT>(20_000_000_000, ctx(&mut scenario));
            gamehub::ready_to_play(&mut room, coin, ctx(&mut scenario));
            
            // Verify pool has entry fee again
            assert!(gamehub::get_pool_value(&room) == 10_000_000_000, 0);
            
            test_scenario::return_shared(room);
        };

        test_scenario::end(scenario);
    }
}