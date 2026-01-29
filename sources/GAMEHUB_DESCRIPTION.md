## Project description
GameHub is a generalized infrastructure for managing multiplayer game rooms, player entry fees, and pooling logic on OneChain. It creates a standardized way for players to join games, commit funds (ready state), and for game logic to settle rewards securely.
- **Room Management**: Allows creating, joining, and leaving rooms.
- **Pooling & Escrow**: Handles entry fee collection, insurance fee deduction, and final settlement.
- **Lobby Interaction**: Maps generic Room objects to specific game states (like Bomb Panic) for frontend discovery.

## Scope
- Modules: `gamehub::gamehub`, `gamehub::lobby`
- Network: OneChain Move

## Summary
- `gamehub` is the core logic for financial flows and room lifecycle (Waiting -> Started -> Settled).
- `lobby` acts as a registry service, linking `Room` objects (generic) to specific `GameState` objects (game-specific).

## Module: gamehub

### Purpose
- Create and administer game rooms.
- Securely hold entry fees (pool) until settlement.
- Manage "Ready" state commitments.
- Deduct insurance fees for the platform.
- Settle final payouts to players.

### Key objects
- `GameRegistry` (shared): Registry of allowed game types. Prevents unauthorized games from using the hub.
- `Room<T>` (shared): The main object holding players, their `ready` status, and the token `pool`.
- `Config` (shared): Stores system-wide settings like `fee_rate` (insurance) and `room_creation_fee`.
- `AdminCap` (owned): Admin privileges to update config.
- `GameCap`: Capability held by the specific game package (e.g., Bomb Panic) to authorize settlement.

### Public & Entry Functions

#### Room Cycle
- `create_room<T, G>(registry, config, entry_fee, max_players, creation_fee, ctx)`
  - Creates a new `Room` for game type `G`. Collects creation fee.
- `join_room<T>(room, ctx)`
  - Adds sender to the room in `Waiting` status.
- `leave_room<T>(room, ctx)`
  - Removes sender from the room. Only allowed if not `Ready`.
- `ready_to_play<T>(room, coin, ctx)`
  - Commits entry fee.
  - Verification: If token is OCT, requires 2x balance check (anti-bot/quality check).
  - Marks player as `Ready`.
- `cancel_ready<T>(room, ctx)`
  - Reverses `ready_to_play`. Refunds entry fee to user.
- `start_room<T>(room, config, ctx)`
  - Transitions `Room` to `Started`.
  - **Requirement**: All joined players must be `Ready`.
  - **Fee**: Deducts insurance fee from the pool and sends to insurance vault.
- `settle<T>(room, addresses, amounts, game_cap, ctx)`
  - **Restricted**: Requires `GameCap`.
  - Transitions `Room` to `Settled`.
  - Distributes tokens from `pool` to `addresses` according to `amounts`.
- `reset_room<T>(room, game_cap, ctx)`
  - Clears all players and status back to `Waiting` for a new round (re-use object).

### Access Control
- `settle`: Restricted to specific game modules (via `GameCap`).
- `start_room`: Can be called by anyone, but logic usually wraps this in the game-specific start function.
- `create_room`: Requires payment of `room_creation_fee`.

### State Invariants
- `status`: `Waiting` -> `Started` -> `Settled`.
- **Solvency**: The `pool` balance always reflects `(Entry Fee * Ready Players) - Insurance Fee`.

## Module: lobby

### Purpose
- Provide a lookup mechanism to find the specific `GameState` (e.g., Bomb Panic state) associated with a generic `Room`.
- Enable frontends to query "Which game is being played in this room?".

### Key objects
- `Lobby` (shared): The global registry table mapping `Room ID` -> `GameState ID`.

### Public Functions
- `register_room(lobby, room_id, game_state_id)`
  - Links a room to a specific game state.
  - Typically called during game creation (e.g., `bomb_panic::create_game_for_room`).
- `get_game_state_id(lobby, room_id) -> ID`
  - Lookup function for frontends/scripts.
- `is_room_registered(lobby, room_id) -> bool`
  - Existence check.

### Usage Pattern
1. **Game Creation**: `bomb_panic` creates a `Room` via `gamehub`.
2. **Registration**: `bomb_panic` creates its own `GameState` and calls `lobby::register_room(room_id, game_id)`.
3. **Discovery**: Frontend lists all Rooms, then queries `Lobby` to find the corresponding `GameState` to show game-specific data (bomb holder, etc.).
