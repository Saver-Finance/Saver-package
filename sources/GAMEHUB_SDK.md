# GameHub SDK Documentation

This document provides a guide for interacting with the `gamehub` module on the One blockchain. It is intended for SDK developers and game integrators.

## Addresses
PACKAGE_ID="0xf4cd45ff567345209a32d2d2e962638d1ff73ab2ffca0a1eeceb6c469a95c414"
GAME_REGISTRY = "0x4df5ad6828579b290b84ae252f0e05a2d2f850f9a9ec05c175381b486b686c8a"
GAME_CAP = "0x3affbb9de92065747eaeced9fe1bda6961e25cc09e6a97e8d9ed557fae460156"
ADMIN_CAP = "0x73c8cbf91ddff5eba8f14620f084a8b664e80d7c504d3beecfde0e34eaaf91aa"
CONFIG = "0xe8cba26df7110c0048783482195502223e38cec7a72f7fdc7099f58f8234b00c"
LOBBY_ID="0xf08db774dd55e6a43bea48a8d49a6ae376403269297a538df36c5dc1f08839a6"
UPGRADE_CAP = "0x9b372265ce25312f1eed3d37cdb10f5ef18cc1664ffe7f5ef91e31deed4e1abe"
GAME_CAP_HACKATHON = "0x88862b4e4114ba2353aac81b93a33a83e55d4a3911beec6249821fa3dfe3fdb3"

## Overview

The GameHub module acts as a lobby and escrow system for on-chain games. It handles:
- Game Registration
- Room Creation
- Player Joining & Readying (with Entry Fees)
- Game Starting (Locking funds)
- Settlement (Distributing payouts)

## Core Structures

### Shared Objects
- **`GameRegistry`**: Stores information about registered games.
- **`Config`**: Stores configuration like fee rates, insurance pool address, and whitelisted tokens.
- **`Room<T>`**: Represents a game lobby for a specific token type `T`.

### Capabilities
- **`GameCap`**: Minted when a game is registered. Required for game server operations like settling and resetting rooms.

---

## 1. Interaction Flow

### A. Setup (Admin)
Before games can be played, the GameHub must be initialized and configured.
1. `init` (called on deployment) creates `GameRegistry`, `Config`, and `AdminCap`.
2. Admin calls `update_config` to set fees.
3. Admin calls `add_whitelist` to allow specific tokens (e.g., OCT).
4. Admin calls `register_game` to register a new game type and receive a `GameCap`.

### B. Room Lifecycle (User)
1. **Create**: A user creates a room for a specific game and token.
2. **Join**: Other users join the room.
3. **Ready**: Users pay the entry fee to mark themselves as "Ready".
4. **Start**: Once enough players are ready, the game server (or admin) starts the room.
5. **Play**: Off-chain gameplay occurs.
6. **Settle**: The game server submits results and payouts.
7. **Reset**: The room can be reset for a new round.

---

## 2. Function Reference

### User Functions

#### `start_room<T>`
Locks the room and changes status to `Started`. Validates that players are ready and fees are collected.
- **Generic Types**: `T`
- **Arguments**:
  - `room`: `&mut Room<T>`
  - `admin_cap`: `&AdminCap` (Required to authorize start)
  - `config`: `&Config` (For calculating insurance fees)

#### `create_room<T, G>`
Creates a new game room.
- **Generic Types**:
  - `T`: The token type for betting (e.g., `0x...::oct::OCT`).
  - `G`: The game type witness (e.g., `0x...::rock_paper_scissors::ROCK_PAPER_SCISSORS`).
- **Arguments**:
  - `registry`: `&GameRegistry` (Shared Object)
  - `config`: `&Config` (Shared Object)
  - `entry_fee`: `u64` (Amount per player)
  - `max_players`: `u8` (Maximum capacity)
  - `creation_fee`: `Coin<T>` (Fee paid to create room, defined in Config)

#### `join_room<T>`
Joins an existing room in `Waiting` status.
- **Generic Types**: `T` (Token type)
- **Arguments**:
  - `room`: `&mut Room<T>` (Shared Object)

#### `leave_room<T>`
Leaves a room. Can only be done if *not* ready.
- **Generic Types**: `T`
- **Arguments**:
  - `room`: `&mut Room<T>`

#### `ready_to_play<T>`
Signals readiness and escrows the entry fee.
- **Generic Types**: `T`
- **Arguments**:
  - `room`: `&mut Room<T>`
  - **`coin`: `Coin<T>`**
    - **Standard Tokens**: Value must be exactly equal to `entry_fee`.
    - **OCT Token**: Value must be at least **2x** `entry_fee` (proof of 50% balance rule). The entry fee is deducted, and the remaining balance is refunded immediately to the sender.

#### `cancel_ready<T>`
Cancels readiness and refunds the entry fee.
- **Generic Types**: `T`
- **Arguments**:
  - `room`: `&mut Room<T>`

---

### Game Server / Admin Functions

#### `settle<T>`
Distributes payouts based on game results. **Payouts are sent directly to the winner addresses; no claim step is required.**
- **Generic Types**: `T`
- **Arguments**:
  - `room`: `&mut Room<T>`
  - `addresses`: `vector<address>` (List of winner addresses)
  - `amounts`: `vector<u64>` (Amount to send to each address)
  - `game_cap`: `&GameCap` (Proof of authority for this game type)

#### `reset_room<T>`
Clears the room players and state after settlement, setting status back to `Waiting`.
- **Generic Types**: `T`
- **Arguments**:
  - `room`: `&mut Room<T>`
  - `game_cap`: `&GameCap`

---

## 3. Error Codes

| Code | Name | Description |
|------|------|-------------|
| 0 | `EFullPlayerInRoom` | Room is full |
| 1 | `EInvalidEntryFee` | Invalid entry fee amount |
| 2 | `ERoomNotWaiting` | Room status is not Waiting |
| 3 | `EGameNotRegistered` | Game type is not registered |
| 4 | `EGameAlreadyRegistered` | Game type already registered |
| 5 | `ERoomCanNotStart` | Room cannot start (e.g. not enough players) |
| 6 | `EPlayerNotFound` | Player is not in the room |
| 7 | `ERoomNotSettled` | Room is not in Settled state |
| 8 | `ENothingToClaim` | No balance to claim |
| 9 | `EInsufficientPoolBalance` | Pool balance insufficient for operation |
| 10 | `EUnauthorizedGame` | Game type mismatch or unauthorized |
| 11 | `EAlreadyReady` | Player is already ready |
| 12 | `ENotReady` | Player is not ready |
| 13 | `ENotAllPlayersReady` | Not all players are ready |
| 14 | `EAlreadyJoined` | Player already joined the room |
| 15 | `EInvalidCreationFee` | Invalid room creation fee |
| 16 | `ECannotLeaveWhenReady` | Cannot leave room while ready |
| 17 | `EPoolNotEmpty` | Pool must be empty (e.g. for reset) |


