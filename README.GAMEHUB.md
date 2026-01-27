# GameHub SDK Documentation

This document provides a guide for interacting with the `gamehub` module on the One blockchain. It is intended for SDK developers and game integrators.

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
- **`AdminCap`**: Required for administrative tasks (updating config, registering games).
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

#### `start_room<T>`
Locks the room and changes status to `Started`. Validates that players are ready and fees are collected.
- **Generic Types**: `T`
- **Arguments**:
  - `room`: `&mut Room<T>`
  - `admin_cap`: `&AdminCap` (Required to authorize start)
  - `config`: `&Config` (For calculating insurance fees)

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

### Admin Configuration

#### `update_config`
- **Arguments**: `config`, `admin_cap`, `fee_rate`, `insurance_pool`, `room_creation_fee`.

#### `add_whitelist<T>`
- **Arguments**: `config`, `admin_cap`.
- **Generic Types**: `T` (Token to whitelist).

#### `register_game<G>`
- **Arguments**: `registry`, `admin_cap`, `game_name` (bytes).
- **Generic Types**: `G` (Game Type Witness).
- **Returns**: `GameCap` (Must be stored/transferred).

---

## 3. Error Codes

| Code | Name | Description |
|------|------|-------------|
| 0 | `EFullPlayerInRoom` | Room is at max capacity |
| 1 | `EInvalidEntryFee` | Coin value does not match entry fee |
| 2 | `ERoomNotWaiting` | Room is not in Waiting state |
| 10 | `ENotReady` | Player tried to cancel but wasn't ready |
| 11 | `ENotAllPlayersReady` | Cannot start room, players missing readiness |
| 13 | `EAlreadyJoined` | Player already in room |
| 14 | `EPlayerNotFound` | Player not in room |

