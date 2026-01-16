module games::game_hub_mock {
    use std::vector;
    use sui::event;
    use sui::object::{Self, UID};
    use sui::tx_context::TxContext;

    /// Simple room status codes for tests.
    /// 0 = Idle, 1 = Running, 2 = Ended, 3 = Settled.
    const STATUS_IDLE: u8 = 0;
    const STATUS_RUNNING: u8 = 1;
    const STATUS_ENDED: u8 = 2;
    const STATUS_SETTLED: u8 = 3;

    /// Room state tracked by the mock hub.
    struct RoomState has copy, drop, store {
        players: vector<address>,
        entry_fee: u64,
        fee_bps: u64,
        escrow_total: u64,
        status: u8,
    }

    /// In-memory record of per-player settlement results.
    struct Payout has copy, drop, store {
        round_id: u64,
        player: address,
        amount: u64,
    }

    /// Mock hub resource.
    struct GameHub has key, store {
        id: UID,
        room: RoomState,
        payouts: vector<Payout>,
    }

    /// Settlement event for test observation.
    struct SettlementEmitted has copy, drop, store {
        round_id: u64,
        player: address,
        amount: u64,
    }

    /// Create a new mock hub with initial room parameters.
    public entry fun create_mock_hub(
        entry_fee: u64,
        fee_bps: u64,
        escrow_total: u64,
        status: u8,
        ctx: &mut TxContext,
    ): GameHub {
        GameHub {
            id: object::new(ctx),
            room: RoomState {
                players: vector::empty(),
                entry_fee,
                fee_bps,
                escrow_total,
                status,
            },
            payouts: vector::empty(),
        }
    }

    /// Add a player address to the room list (no limit enforced in mock).
    public fun add_player(hub: &mut GameHub, player: address) {
        vector::push_back(&mut hub.room.players, player);
    }

    /// Update room status flag for test state transitions.
    public fun set_status(hub: &mut GameHub, status: u8) {
        hub.room.status = status;
    }

    /// Record a settlement outcome without transferring coins.
    /// Stores an in-memory record and emits a lightweight event.
    public fun record_settlement(hub: &mut GameHub, round_id: u64, player: address, amount: u64) {
        let payout = Payout { round_id, player, amount };
        vector::push_back(&mut hub.payouts, payout);
        event::emit(SettlementEmitted { round_id, player, amount });
        hub.room.status = STATUS_SETTLED;
    }

    /// Getter helpers for tests.
    public fun room_status(hub: &GameHub): u8 {
        hub.room.status
    }

    public fun room_players(hub: &GameHub): &vector<address> {
        &hub.room.players
    }

    public fun room_entry_fee(hub: &GameHub): u64 {
        hub.room.entry_fee
    }

    public fun room_fee_bps(hub: &GameHub): u64 {
        hub.room.fee_bps
    }

    public fun room_escrow_total(hub: &GameHub): u64 {
        hub.room.escrow_total
    }

    public fun payouts(hub: &GameHub): &vector<Payout> {
        &hub.payouts
    }
}
