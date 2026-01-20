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
    fun test_game_flow() {
        // 1. Khởi tạo Scenario
        let mut scenario = test_scenario::begin(ADMIN);
        
        // --- Bước 1: Khởi tạo Module (Init) ---
        {
            gamehub::init_for_testing(ctx(&mut scenario));
        };

        // --- Bước 2: Admin cập nhật Config & Đăng ký Game ---
        next_tx(&mut scenario, ADMIN);
        {
            let mut registry = test_scenario::take_shared<GameRegistry>(&scenario);
            let mut config = test_scenario::take_shared<Config>(&scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);

            // Set fee rate là 10% (100 / 1000)
            gamehub::update_config(&mut config, &admin_cap, 100, INSURANCE);

            // Đăng ký game
            gamehub::register_game<ROCK_PAPER_SCISSORS>(&mut registry, b"Rock Paper Scissors");

            test_scenario::return_shared(registry);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&scenario, admin_cap);
        };

        // --- Bước 3: Tạo phòng (Create Room) ---
        next_tx(&mut scenario, ADMIN);
        {
            let registry = test_scenario::take_shared<GameRegistry>(&scenario);
            
            // Tạo phòng với phí vào cửa là 10 OCT, tối đa 2 người
            let entry_fee = 10_000_000_000; // 10 OCT
            gamehub::create_room<OCT, ROCK_PAPER_SCISSORS>(
                &registry, 
                entry_fee, 
                2, 
                ctx(&mut scenario)
            );

            test_scenario::return_shared(registry);
        };

        // --- Bước 4: Player 1 tham gia ---
        next_tx(&mut scenario, PLAYER_1);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            let entry_fee = 10_000_000_000;
            
            // Mint coin cho Player 1
            let coin = coin::mint_for_testing<OCT>(entry_fee, ctx(&mut scenario));
            
            gamehub::join_room(&mut room, coin, ctx(&mut scenario));
            
            test_scenario::return_shared(room);
        };

        // --- Bước 5: Player 2 tham gia ---
        next_tx(&mut scenario, PLAYER_2);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            let entry_fee = 10_000_000_000;
            
            let coin = coin::mint_for_testing<OCT>(entry_fee, ctx(&mut scenario));
            
            gamehub::join_room(&mut room, coin, ctx(&mut scenario));
            
            test_scenario::return_shared(room);
        };

        // --- Bước 6: Admin bắt đầu game (Start Room) ---
        next_tx(&mut scenario, ADMIN);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);

            gamehub::start_room(&mut room, &admin_cap);

            test_scenario::return_shared(room);
            test_scenario::return_to_sender(&scenario, admin_cap);
        };

        // --- Bước 7: Admin chốt kết quả (Settle) ---
        // Giả sử Player 1 thắng hết quỹ (20 OCT)
        next_tx(&mut scenario, ADMIN);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);

            let addresses = vector[PLAYER_1, PLAYER_2];
            let amounts = vector[20_000_000_000, 0]; // Player 1 thắng 20 OCT

            gamehub::settle(&mut room, addresses, amounts, &admin_cap);

            test_scenario::return_shared(room);
            test_scenario::return_to_sender(&scenario, admin_cap);
        };

        // --- Bước 8: Player 1 rút tiền (Claim) ---
        next_tx(&mut scenario, PLAYER_1);
        {
            let mut room = test_scenario::take_shared<Room<OCT>>(&scenario);
            let config = test_scenario::take_shared<Config>(&scenario);
            
            // Player 1 claim
            gamehub::claim(&config, &mut room, ctx(&mut scenario));

            test_scenario::return_shared(room);
            test_scenario::return_shared(config);
        };

        // --- Bước 9: Kiểm tra số dư cuối cùng ---
        next_tx(&mut scenario, PLAYER_1);
        {
            let expected_balance = 18_000_000_000;
            
            let coin = test_scenario::take_from_sender<Coin<OCT>>(&scenario);
            assert!(coin::value(&coin) == expected_balance, 0);
            
            test_scenario::return_to_sender(&scenario, coin);
        };

        // Kiểm tra ví bảo hiểm nhận được phí
        next_tx(&mut scenario, INSURANCE);
        {
             // Phí 10% của 20 OCT = 2 OCT
            let expected_fee = 2_000_000_000;
            
            let coin = test_scenario::take_from_sender<Coin<OCT>>(&scenario);
            assert!(coin::value(&coin) == expected_fee, 1);
            
            test_scenario::return_to_sender(&scenario, coin);
        };

        test_scenario::end(scenario);
    }
}