# Unit Test Report: Bomb Panic

## 1. Project Information

| Item | Details |
| --- | --- |
| **Project Name** | Bomb Panic Game |
| **Repository Link** | https://github.com/Saver-Finance/Saver-package/tree/main/sources/games/bomb_panic.move |
| **Network Tested** | OneChain Testnet |
| **Contracts Tested** | `bomb_panic` |
| **Test Date** | 28/1/2026 |

---

## 2. Scope of Testing

This report covers unit testing of the following package features:

- **Player Management**: Joining, leaving, capacity enforcement, and minimum player validation.
- **Game Flow**: Round start/reset, state transitions (Waiting -> Playing -> Ended), and victory conditions.
- **Bomb Mechanics**: Bomb passing, holder tracking, probabilistic explosion, and force-explosion on holder exit.
- **Settlement**: Settlement intent consumption, state verification, and double-spend prevention.
- **Admin**: Game configuration updates.

**Out of Scope:**

- Frontend production testing
- GameHub registry integration (covered in separate `gamehub` tests)
- Load/stress testing
- Formal security audit

---

## 3. Test Environment

| Component | Version / Details |
| --- | --- |
| **Framework** | OneChain Move Framework |
| **Test Network** | OneChain Testnet |
| **Wallet Used** | OneWallet |

---

## 4. Summary of Test Results

| Category | Total Tests | Passed | Failed |
| --- | --- | --- | --- |
| Player Management | 4 | 4 | 0 |
| Game Flow | 6 | 6 | 0 |
| Bomb Mechanics | 4 | 4 | 0 |
| Settlement | 2 | 2 | 0 |
| Admin / Config | 1 | 1 | 0 |
| **Overall** | **17** | **17** | **0** |

**Result Summary:**

*All core game mechanics including critical edge cases (holder leaving, pool draining victory, game reset) executed as expected with correct state updates.*

---

## 5. Detailed Test Cases

### 5.1 Player Management

| Test ID | Description | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| PLY-01 | Join adds players up to max | Call `join()` with multiple distinct signers | Game state updates player list up to max | ✅ Pass |
| PLY-02 | Cannot join twice | User calls `join()` a second time | Abort with `E_ALREADY_JOINED` | ✅ Pass |
| PLY-03 | Leave during waiting phase | User calls `leave()` while game is Waiting | Player removed from list, can re-join | ✅ Pass |
| PLY-04 | Start with insufficient players | Call `start_round()` with 1 player | Abort with `E_NOT_ENOUGH_PLAYERS` | ✅ Pass |

### 5.2 Game Flow & Lifecycle

| Test ID | Description | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| FLW-01 | Start round sets playing state | Call `start_round()` with sufficient players | Game phase transitions to `Playing` | ✅ Pass |
| FLW-02 | Full workflow happy path | Simulate join, start, pass, explode, settle | Complete game lifecycle executes; survivors identified | ✅ Pass |
| FLW-03 | Leave during playing (Non-Holder) | Non-holder calls `leave()` while Playing | Player marked dead, game continues | ✅ Pass |
| FLW-04 | Leave during playing (Holder) | Holder calls `leave()` while Playing | **Immediate Explosion**, game ends (suicide) | ✅ Pass |
| FLW-05 | Victory Condition (Pool Drained) | Play until pool reaches 0 without explosion | Game ends peacefully, all survivors win | ✅ Pass |
| FLW-06 | Reset Game | Call `reset_game()` after settlement | State clears (players empty, phase waiting), ready for new round | ✅ Pass |

### 5.3 Bomb Mechanics

| Test ID | Description | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| BMB-01 | Pass bomb changes holder | Holder calls `pass_bomb()` | Holder changes, pool value decreases (fee/reward) | ✅ Pass |
| BMB-02 | Only holder can pass bomb | Non-holder calls `pass_bomb()` | Abort with `E_NOT_HOLDER` | ✅ Pass |
| BMB-03 | Grace period logic | `try_explode()` during grace period | No explosion occurs (0% probability) | ✅ Pass |
| BMB-04 | Max duration logic | `try_explode()` after max duration | Explosion guaranteed (100% probability), game ends | ✅ Pass |

### 5.4 Settlement

| Test ID | Description | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| STL-01 | Consume settlement intent | Call `consume_settlement_intent()` after end | Returns valid `SettlementIntent` struct | ✅ Pass |
| STL-02 | Cannot consume twice | Call `consume_settlement_intent()` twice | Abort with `E_SETTLEMENT_CONSUMED` | ✅ Pass |

### 5.5 Admin / Configuration

| Test ID | Description | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| ADM-01 | Configure game parameters | Admin calls `configure_game_admin()` | Game config parameters (bps, timeout) updated | ✅ Pass |

---

## 6. Conclusion

The `bomb_panic` module was successfully tested on the local Move test environment. Unit tests confirm that **player management, game lifecycle (including reset & victory), bomb mechanics, and settlement logic function correctly**.

Implementation now covers 100% of identified critical logic paths.

## 7. Contract Test Coverage

All public entry functions and critical abort paths in the bomb_panic smart contract are covered by unit tests, including state transitions, permission checks, edge cases, and settlement finalization logic.

