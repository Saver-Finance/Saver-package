module gamehub::lobby;

use one::table::{Self, Table};

/// Error codes
const E_ROOM_ALREADY_REGISTERED: u64 = 0;
const E_ROOM_NOT_FOUND: u64 = 1;

/// Global registry mapping Room IDs to GameState IDs
public struct Lobby has key {
    id: object::UID,
    /// Maps: Room Object ID -> GameState Object ID
    room_to_game: Table<object::ID, object::ID>,
}

fun init(ctx: &mut one::tx_context::TxContext) {
    let lobby = Lobby {
        id: object::new(ctx),
        room_to_game: table::new(ctx),
    };
    transfer::share_object(lobby);
}

/// Register a room-gamestate pair
public fun register_room(
    lobby: &mut Lobby,
    room_id: object::ID,
    game_state_id: object::ID,
) {
    assert!(!table::contains(&lobby.room_to_game, room_id), E_ROOM_ALREADY_REGISTERED);
    table::add(&mut lobby.room_to_game, room_id, game_state_id);
}

/// Resolve room to gamestate (frontend helper)
public fun get_game_state_id(
    lobby: &Lobby,
    room_id: object::ID,
): object::ID {
    assert!(table::contains(&lobby.room_to_game, room_id), E_ROOM_NOT_FOUND);
    *table::borrow(&lobby.room_to_game, room_id)
}

/// Check if room is registered
public fun is_room_registered(
    lobby: &Lobby,
    room_id: object::ID,
): bool {
    table::contains(&lobby.room_to_game, room_id)
}

#[test_only]
public fun init_for_testing(ctx: &mut one::tx_context::TxContext) {
    init(ctx);
}
