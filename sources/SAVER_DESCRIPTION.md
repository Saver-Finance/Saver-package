
## Config
```
export const DEFAULT_CONFIG = {
    PACKAGE_ID: "0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a",
    MINTER_ID: "0x646cc2bcfe6cccad7581d9e105b626306ee8391b5fa644edf1db8f257f361a3d",
    ADAPTER_CONFIG: "0xa288c11f7866eeb5ce9d5eb27720881c4982da0468d8cab93f2e6037eeadd56e",
    UT_CONFIG: "0x69ec13a6e9d14a8d77f2622bf568c4bbbd123521f11173d837deef83b88e8a70",
    YOCT_VAULT: "0xe26e439422eeaedc01ef8dcca6638f406c6836d9062c90e701744e6e9a0384ec",
    MOCK_VAULT: "0xf70e7a95a68a0cf049bbf9425e0c2f6b30c4b6919ca1a2c2934b4cf34797eb75",
    CLOCK: "0x6",

    // Redeem Pool & Limiter (For Repay/Liquidate)
    RP_CONFIG: "0xf01aba7c4837d10ddc6ab71d827bb9c5b7c46717f6f536994de0cabbba7aabc1",
    RP_VAULT: "0x5d8ad3ff5be7acd0d38e7828e82c16668b0fe1f82e1ce47af4c263f6da82ec95",
    LIQUIDATE_LIMITER: "0xcacbde553bbb14c615aaf1507e9551acbae5747c2ad76142555df4267f76517c",

    // Coin Types
    COIN_OCT: "0x2::oct::OCT",
    COIN_YOCT: "0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::yoct::YOCT",
    COIN_SROCT: "0xcdf85ff5d1373a551e659b3e6cf4f6dde126e5b040bfdb4392305708fd42d55a::sroct::SROCT",
    SROCT_TREASURY_CAP: "0x4183c3f7e0d2f6eafe42c553a12781ccd33b5d483448650c5ab9927c4ffc112c"
};

```

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
