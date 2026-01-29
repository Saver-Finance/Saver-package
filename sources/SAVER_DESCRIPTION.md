## Project description
SAVER is a synthetic asset protocol that allows users to deposit Yield-Bearing Tokens (YT) to mint a synthetic stablecoin or share token (SROCT). It uses a "Credit" system to accrue yield and manage debt, ensuring the system remains over-collateralized.
- **Deposit**: Users deposit Underlying/Yield tokens to receive structural "Shares".
- **Mint**: Users use their Shares as collateral to mint the synthetic token (SROCT).
- **Yield Distribution**: Yield from the underlying vault is distributed to users as "Credit", which automatically pays down their debt (self-repaying loans).
- **Safety**: Implements strict debt ceilings, minting limits, and liquidation mechanisms.

## Scope
- Modules: `saver::saver`, `saver::redeem_pool`, `saver::limiter`
- Network: OneChain Move

## Summary
- `saver` is the core module managing user credit, debt, vaults, and the minting engine (`Minter`).
- `redeem_pool` handles the secondary market or "insurance" buffer where users can redeem the synthetic token for underlying assets (usually fed by liquidations/donations).
- `limiter` provides rate-limiting safety features for minting and liquidation to prevent economic exploits.

## Module: saver

### Purpose
- Manage the main `Vault` (reserves).
- Handle `User` positions (Debt, Profit, Shares).
- Execute core actions: Deposit, Mint, Burn, Repay, Harvest, Liquidate.
- Manage Yield Token configurations (LTV, Credit Unlock Rate).

### Key objects
- `Minter<S>` (shared): The central controller for minting token `S`. Holds configuration for all supported Yield Tokens (`YieldTokenConfig`) and the `Limiter`.
- `Vault<T>` (shared): Holds the physical reserve of yield token `T`.
- `UserInfo<T, S>` (owned): Stores an individual user's position:
  - `debt`: Amount of `S` minted/owed.
  - `profit`: Accrued yield (credit) available to claim or offset debt.
  - `deposited_token`: User's share balance and accrue weights.
- `AdapterCap` (owned): Admin capability for trusted adapters/keepers.

### Public & Entry Functions

#### User Actions
- `deposit<T, S>(...)`
  - User deposits `Coin<T>`.
  - Protocol calculates `Shares` based on current exchange rate and issues them to `UserInfo`.
- `mint<T, S>(...)`
  - User mints `Coin<S>` against their `Shares`.
  - Increases `UserInfo.debt`. Checks `Limiter` and Collateralization Ratio (`minimum_collateralization`).
- `burn<T, S>(...)`
  - User burns `Coin<S>` to repay debt.
  - Reduces `debt`. Increases `Limiter` capacity (replenishes limit).
- `repay<T, S>(...)`
  - User repays debt using `Coin<U>` (underlying) or other recognized assets (via adapter logic).
- `withdraw<T, S>(...)`
  - User burns `Shares` to withdraw `Coin<T>`.
  - Checks remaining collateralization if debt exists.
- `liquidate<T, S>(...)`
  - **Public/Keeper**. Liquidates a position below the MCR (Minimum Collateralization Ratio).
  - Burns `Shares` to repay `debt`. Liquidator captures collateral.

#### Keeper / Admin Actions
- `harvest<T, S>(...)`
  - Updates the global yield indices (`accrued_weight`).
  - Distributes new yield as `Credit` to share holders.
- `create_new_minter`, `create_vault`: Initialization functions.

### State Invariants
- **Over-collateralization**: Total Value of Collateral > Total Debt * MCR.
- **Credit System**: Debt is always $\ge$ 0. Yield acts as negative debt (Credit).
- **Limiter**: Minting rate $\le$ Configured Max Limit.

## Module: redeem_pool

### Purpose
- Act as a buffer/sink for excess assets (donated from fees/liquidations).
- Allow users to "Redeem" synthetic tokens for underlying assets 1:1 (or at market rate) independently of the main vault.

### Key objects
- `Vault<U, S>` (shared): Holds Underlying Token `U` reserves available for redemption by `S`.
- `Config` (shared): Admin controls (pausing).

### Functions
- `donate<U, S>(...)`: Adds `Coin<U>` to the vault (verified safe source like liquidation residue).
- `redeem<U, S>(...)`: User burns `Coin<S>` to receive `Coin<U>` from this pool.

## Module: limiter

### Purpose
- Provide a linear-growth rate limiter for sensitive operations (Minting, Liquidation).
- Prevents flash-loan attacks or rapid protocol draining.

### Key objects
- `Limiter` (store): Struct attached to Minter/Config. Tracks `maximum`, `rate`, `last_value`.

### Functions
- `decrease`: Consumes limit capacity (e.g., Minting). Aborts if limit hit.
- `increase`: Replenishes or grows capacity over time (e.g., Burning/Repaying).
