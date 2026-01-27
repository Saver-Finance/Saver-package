module saver::error;


const UnAuthorize: u64 = 0;
const NotEnoughBalance: u64 = 1;
const AlreadyInitialize: u64 = 2;
const FreezeVault: u64 = 3;
const OverMaximumExpectedValue: u64 = 4;
const InvalidDuration: u64 = 5;
const InvalidMaximum: u64 = 6;
const MintingLimitExceed: u64 = 7;

public fun unAuthorize(): u64 {
    UnAuthorize
}

public fun notEnoughBalance(): u64 {
    NotEnoughBalance
}

public fun alreadyInitialize(): u64 {
    AlreadyInitialize
}

public fun freezeVault(): u64 {
    FreezeVault
}

public fun overMaximumExpectedValue(): u64 {
    OverMaximumExpectedValue
}

public fun invalidDuration(): u64 {
    InvalidDuration
}

public fun invalidMaximum(): u64 {
    InvalidMaximum
}

public fun mintingLimitExceed(): u64 {
    MintingLimitExceed
}