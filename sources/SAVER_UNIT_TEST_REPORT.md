## 1. Project Information

| Item | Details |
| --- | --- |
| **Project Name** | Saver Lending Core |
| **Repository Link** | https://github.com/Saver-Finance/Saver-package/tree/main/sources/saver |
| **Network Tested** | OneChain Testnet |
| **Contracts Tested** | `saver` |
| **Test Date** | 27/1/2026 |

---

## 2. Scope of Testing

This report covers unit testing of the following package features:

- Deposits
- Withdrawals
- Minting logic
- Burning logic
- Liquidation
- Harvest
- Repay
- Redeem pool
- Failure and edge cases

**Out of Scope (if any):**

- Frontend production testing
- Load/stress testing
- Formal security audit

---

## 3. Test Environment

| Component | Version / Details |
| --- | --- |
| **Framework** | Sui Framework |
| **Test Network** | OneChain Testnet |
| **Wallet Used** | OneWallet |

---

## 4. Summary of Test Results

| Category | Total Tests | Passed | Failed |
| --- | --- | --- | --- |
| Deposit | 4 | 4 | 0 |
| Withdrawal | 2 | 2 | 0 |
| Mint | 3 | 3 | 0 |
| Burn | 3 | 3 | 0 |
| Liquidation | 1 | 1 | 0 |
| Repay | 1 | 1 | 0 |
| Harvest | 1 | 1 | 0 |
| Redeem pool | 4 | 4 | 4 |
| Overall | 16 | 16 | 0 |

**Result Summary:**

*All core financial flows (deposit, withdrawal, mint, burn) executed as expected with correct state updates and event emissions.*

---

## 5. Detailed Test Cases

### 5.1 Deposit Function

| Test ID | Description | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| DEP-01 | User can deposit valid amount of Yield Token directly | Call `deposit()` with X tokens | Contract balance increases | ✅ Pass |
| DEP-02 | User can deposit underlying valid amount of underlying token directly | Call `deposit_underlying()`  | Contract balance increase | ✅ Pass |
| DEP-03 | Deposit yield token after having | call `deposit()`  | Correct share amount receive | ✅ Pass |
| DEP-04 | Deposit a amount that its value is greater than maximum value | call `deposit()`  | Expect abort code 4 | ✅ Pass |

---

### 5.2 Withdrawal Function

| Test ID | Description | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| WDR-01 | User withdraws yield token | Call `withdraw()`  | User receives yield tokens, balance reduced, share reduced | ✅ Pass |
| WDR-02 | User withdraws underlying yoken | call `withdraw_underlying()`  | User receives underlying token, balance reduced, share reduced | ✅ Pass |

---

### 5.3 Mint Function

| Test ID | Description | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| MNT-01 | User mints when he/she has no profit | user calls `mint()` | Tokens minted correctly, their debt increased by exactly the amount they borrowed. | ✅ Pass |
| MNT-02 | User mints when he/she has profit | user calls `mint()`  | Token minted correcly, the debt increased by exactly the amount they borrowed minus the interest they earned. | ✅ Pass |
| MNT-02 | Users borrow more than they are entitled to. | user calls `mint()` | expected revert | ✅ Pass |

---

### 5.4 Burn Function

| Test ID | Description | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| BRN-01 | User burns tokens when he/she has no profit | Call `burn()` | Token supply reduced, user debt reduce | ✅ Pass |
| BRN-02 | User burns tokens when he/she has profit | call `burn()` | Token supply reduced, user debt reduce,   | ✅ Pass |
| BRN-03 | User over repay | call `burn()`  | User get leftover token | ✅ Pass |

---

### 5.5 Liquidation Function

| Test ID | Description | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| LIQ-01 | User use there shares to liquidate | Call `liquidate()` | debt decrease, share decrease | ✅ Pass |

### 5.6 Repay Function

| Test ID | Description | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| RPY-01 | User use OCT to repay the loan | Call `repay()` | Debt decrease | ✅ Pass |

### 5.7 Harvest Function

| Test ID | Description | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| HRV-01 | Keeper call harvest | Call `harvest()` | Weigh increase, user have profit | ✅ Pass |

### 5.8 Redeem pool Function

| Test ID | Description | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| RDP-01 | Deposit | Call `deposit()` | SROCT balance increase, user entry weigh is updated correctly | ✅ Pass |
| RDP-02 | Withdraw | call `withdraw()`  | user can only withdraw SROCT that has not been exchanged | ✅ Pass |
| RDP-03 | Donate | call `donate()`  | donate oct, buffer update right, total weight update right | ✅ Pass |
| RDP-04 | Claim | call `claim()`  | User receive oct | ✅ Pass |

---

## 6. Conclusion

The Package were successfully deployed and tested on **OneChain Testnet**. Unit tests confirm that **deposit, withdrawal, mint, and burn logic function correctly**, including proper validation, permissions, and failure handling.

No critical issues were identified during unit testing.