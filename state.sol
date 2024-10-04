// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

struct ProgramConfig {
    bool isInitialized;
    uint8 bump;
    address admin;
    address platform;
    address feeRecipientAccount;
    address depositAccount;
    uint256 baseMinSupply;
    uint256 baseMaxSupply;
    uint256 createFee;
    uint256 baseMinFeeRate;
    uint256 baseMaxFeeRate;
}

struct CurveInfo {
    address baseToken;
    address quoteToken;
    uint256 initVirtualQuoteReserves;
    uint256 initVirtualBaseReserves;
    uint256 currentQuoteReserves;
    uint256 currentBaseReserves;
    uint256 feeBps;
    uint256 target;
    address creator; // 添加 creator 字段，修复权限问题
    bool isLaunchPermitted;
    bool isOnPancake;
}

event CreateEventPart1(
    address indexed user,
    address indexed baseMint,
    string name,
    string symbol,
    string uri
);

event CreateEventPart2(
    address bondingCurve,
    uint256 supply,
    uint256 target,
    uint256 initVirtualQuoteReserves,
    uint256 initVirtualBaseReserves,
    uint256 feeBps,
    uint256 createFee,
    bool isLaunchPermitted,
    uint256 timestamp
);

event TradeEventPart1(
    address indexed quoteMint,
    address indexed baseMint,
    uint256 quoteAmount
);

event TradeEventPart2(
    uint256 baseAmount,
    uint256 feeAmount,
    bool isBuy,
    address indexed user
);

event TradeEventPart3(
    uint256 timestamp,
    uint256 virtualQuoteReserves,
    uint256 virtualBaseReserves
);

event TradeEventPart4(
    uint256 newQuoteBalance,
    uint256 newBaseSupply
);

event TradeEventPart5(
    uint256 initSupply,
    uint256 target,
    uint256 initVirtualQuoteReserves,
    uint256 initVirtualBaseReserves
);

event TradeEventPart6(
    uint256 userQuoteBalance
);

event TradeEventPart7(
    uint256 userBaseBalance
);

event TradeEventPart8(
    uint256 feeBps,
    uint256 createFee,
    bool isOnPancake
);

event TradeEventPart9(
    uint256 baseCost
);

// 拆分后的 DepositEvent2
event DepositEvent2Part1(
    address indexed user,
    address indexed mint1,
    uint256 cost1,
    address indexed mint2
);

event DepositEvent2Part2(
    uint256 cost2,
    string command,
    string extraInfo,
    uint8 maxIndex,
    uint8 index,
    uint256 timestamp
);

event Withdraw2Event(
    address indexed systemAccount,
    address indexed receiverAccount,
    address indexed mint,
    uint256 cost,
    uint256 timestamp
);
