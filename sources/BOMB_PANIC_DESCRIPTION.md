## Project description
Bomb Panic is a multiplayer survival game where players pass a ticking bomb to avoid explosion. This document details the `bomb_panic` module, which contains the core gameplay logic, bomb state, explosion mechanisms, and reward calculations.

## Scope
- Module: `games::bomb_panic`
- Network: OneChain Move
- Dependencies: `gamehub` (external package for room management and funding)

## Summary
`bomb_panic` manages the round lifecycle (Waiting -> Playing -> Ended), the bomb passing mechanics, the probabilistic explosion logic, and the final settlement distribution. It relies on `gamehub` for room management, player readiness, and token pooling, but maintains its own independent game state.

## Module: bomb_panic

### Purpose
- Manage the "Round" lifecycle.
- Handle bomb mechanics (passing, explosion logic).
- Calculate settlement distribution (who survived, who gets holder rewards).
- Allow admin configuration of game parameters.

### Key objects
- `GameState<T>` (shared): The core game state. Tracks `bomb_holder`, `phase`, `holder_rewards`, `pool_value`, and configuration. Contains a `GameHubRef`.
- `GameHubRef`: Internal reference to the associated External GameHub room.

### Key events
- `RoomAndGameCreated`: Emitted when a game state is created and linked to a room.
- `RoundStarted`: Emitted when the game begins.
- `BombPassed`: Emitted when a player passes the bomb.
- `Exploded`: Emitted when the bomb explodes (round ends).
- `Victory`: Emitted if the pool is drained without an explosion (round ends).
- `GameReset`: Emitted when the game is reset for a new round.
- `PlayerExited`: Emitted when a player leaves (or dies by leaving).
- `RandomNumber`: Emitted during `try_explode` for transparency.
- `RoundSettled`: Emitted when settlement intent is consumed and ready for Hub settlement.

### GameHub Interactions
`bomb_panic` interacts with `gamehub` to coordinate the financial and room lifecycle aspects of the game.

| Function Call | Purpose |
| :--- | :--- |
| `gamehub::lobby::register_room` | Called by `create_game_for_room` to register the new GameState with the Lobby, making it discoverable. |
| `gamehub::gamehub::get_entry_fee` | Read by `create_game_for_room` and `start_round` to sync game config with room settings. |
| `gamehub::gamehub::get_pool_value` | Read by `start_round` to determine the total prize pool available for the round. |
| `gamehub::gamehub::start_room_internal` | Called by `start_round_with_hub`. Transitions the Room to `Started` and collects insurance fees. |
| `gamehub::gamehub::settle_internal` | Called by `settle_round_with_hub`. Executes the actual token transfers based on `bomb_panic`'s calculated payout vector. |

### Public & Entry Functions

#### Gameplay
- `join<T>(game, ctx)`
  - Adds player to the game list. Room must be in `Waiting` state.
- `start_round_with_hub<T>(rng, game, room, clock, config, ctx)`
  - **Main Entry**: Starts both the `Room` (in GameHub) and the `GameState`.
  - Validates `room` matches `game`.
  - Calls `gamehub::start_room_internal` to collect fees and lock the room.
  - Initializes internal game state (picks holder, sets timestamp) via `start_round`.
- `pass_bomb<T>(rng, game, clock, ctx)`
  - **Bomb Holder Only**.
  - Calculates time held -> pays reward from pool -> picks new random holder.
- `leave<T>(game, clock, ctx)`
  - Allows a player to leave.
  - If `Waiting`: clean exit.
  - If `Playing`: treated as death/forfeit. If holder leaves, bomb explodes.
- `try_explode<T>(game, clock, rng, ctx)`
  - **Bot/Public**. Called periodically.
  - Checks logic:
    1. **Max Hold Time**: If current holder exceeds limit -> Immediate Explosion.
    2. **RNG**: Flat probability (default 3%). If hit -> Explosion.
    3. **Victory**: If pool is empty -> Victory.

#### Setup & Admin
- `create_game_for_room<T>(lobby, room, ctx)`
  - Creates a `GameState` for an existing `Room`.
  - Registers the game with `gamehub::lobby`.
  - Syncs entry fee and max players from the Room.
- `configure_game_admin<T>(game, admin_cap, max_hold_time_ms, explosion_rate_bps, reward_divisor)`
  - **Admin Only**. Updates game configuration. Requires `gamehub::AdminCap` for authorization.
- `prepare_next_round<T>(game, new_room_id)`
  - Resets internal state to `Waiting` for the next round via `reset_game`.
  - Updates the `room_id` to point to a new Room object for the next match.

#### Settlement
- `settle_round_with_hub<T>(game, room, game_cap, ctx)`
  - **Main Settlement Entry**.
  - 1. Calculates payouts via `get_settlement_data` (Survivors split remainder, holders get timed rewards).
  - 2. Consumes settlement intent (prevent double spend).
  - 3. Calls `gamehub::settle_internal` to perform the token transfers.

### Access Control
- `pass_bomb`: Sender must be the current `bomb_holder`.
- `configure_game_admin`: Sender must hold `gamehub::AdminCap`.
- `start_round_with_hub`: Checks consistency between Game and Room.
- `settle_round_with_hub`: Requires `gamehub::GameCap` to authorize the settlement in the Hub.

### Reward Formula
- **Holder Reward**: `(Initial Pool / reward_divisor) * seconds_held`.
  - Paid instantly (accounting updates) upon passing bomb or game end.
- **Survivor Reward**: `(Remaining Pool) / Count(Survivors)`.
  - `Remaining Pool` = `Initial Pool` - `Sum(Holder Rewards)`.
