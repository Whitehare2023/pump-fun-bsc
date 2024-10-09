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

event CreateEvent(
    address indexed creator,
    address indexed customToken,
    address indexed tokenOperations,
    string name,
    string symbol,
    string uri,
    uint256 supply,
    uint256 target,
    uint256 initVirtualQuoteReserves,
    uint256 initVirtualBaseReserves,
    uint256 feeBps,
    bool isLaunchPermitted,
    uint256 timestamp
);

event CreateEvent1(
    address indexed creator,
    address indexed customToken,
    address indexed tokenOperations,
    string name,
    string symbol,
    string uri
);

event CreateEvent2(
    uint256 supply,
    uint256 target,
    uint256 initVirtualQuoteReserves,
    uint256 initVirtualBaseReserves,
    uint256 feeBps,
    bool isLaunchPermitted,
    uint256 timestamp
);

// 定义 BuyEvent1 和 BuyEvent2
event BuyEvent1(
    address indexed quote_mint,               // 报价代币地址
    address indexed base_mint,                // 基础代币地址
    uint256 quote_amount,                     // 实际支付的报价代币数量
    uint256 base_amount,                      // 用户获得的基础代币数量
    uint256 fee_amount,                       // 手续费
    address indexed user,                     // 用户地址
    uint256 timestamp,                        // 时间戳
    uint256 virtual_quote_reserves,           // 虚拟报价代币储备量
    uint256 virtual_base_reserves             // 虚拟基础代币储备量
);

event BuyEvent2(
    uint256 new_quote_balance,                // 当前报价代币储备量
    uint256 new_base_supply,                  // 当前基础代币储备量
    uint256 supply,                           // 基础代币的初始供应量
    uint256 target,                           // 发射目标
    uint256 init_virtual_quote_reserves,      // 初始虚拟报价代币储备量
    uint256 init_virtual_base_reserves,       // 初始虚拟基础代币储备量
    uint256 fee_bps,                           // 手续费基点数
    uint256 create_fee,                       // 创建费用
    bool should2raydium                       // 是否转移到 Raydium
);

event SellEvent1(
    address indexed quote_mint,               // 报价代币地址
    address indexed base_mint,                // 基础代币地址
    uint256 quote_amount,                     // 用户获得的报价代币数量
    uint256 base_amount,                      // 用户卖出的基础代币数量
    uint256 fee_amount,                       // 手续费
    address indexed user,                     // 用户地址
    uint256 timestamp,                        // 时间戳
    uint256 virtual_quote_reserves,           // 虚拟报价代币储备量
    uint256 virtual_base_reserves             // 虚拟基础代币储备量
);

event SellEvent2(
    uint256 new_quote_balance,                // 当前报价代币储备量
    uint256 new_base_supply,                  // 当前基础代币供应量
    uint256 supply,                           // 初始基础代币供应量
    uint256 target,                           // 发射目标
    uint256 init_virtual_quote_reserves,      // 初始虚拟报价代币储备量
    uint256 init_virtual_base_reserves,       // 初始虚拟基础代币储备量
    uint16 fee_bps,                           // 手续费基点数
    uint256 create_fee,                       // 创建费用
    bool should2raydium                       // 是否转移到 Raydium
);

event PermitEvent(
    address indexed creator,            // 发起 permit 操作的用户地址
    address indexed base_mint,          // 基础代币的合约地址
    address indexed quote_mint,         // 报价代币的合约地址
    bool is_launch_permitted,           // 是否允许发射
    bool should2raydium,                // 是否转移到 Raydium
    uint256 timestamp                   // 事件发生的时间戳
);

event WithdrawEvent(
    address indexed quote_mint,           // 报价代币的合约地址
    address indexed base_mint,            // 基础代币的合约地址
    uint256 quote_amount,                 // 提取的报价代币数量
    uint256 base_amount,                  // 提取的基础代币数量
    uint256 timestamp,                    // 事件发生的时间戳
    address indexed receiver              // 接收者（平台地址）
);

event Withdraw2Event(
    address indexed system_account,      // 发起提现操作的系统账户地址
    address indexed receiver_account,    // 接收者账户地址
    address indexed mint,                // 提取的代币合约地址
    uint256 cost,                        // 提取的代币数量
    string order_id,                     // 订单 ID
    uint256 timestamp                    // 事件发生的时间戳
);

event DepositEvent(
    address indexed user,        // 存款操作的用户地址
    address indexed mint,        // 存款代币的合约地址
    uint256 cost,                // 存款的代币数量
    uint256 timestamp            // 事件发生的时间戳
);

event Deposit2Event(
    address indexed user,   // 存款的用户地址
    address indexed mint1,  // 第一个代币的合约地址
    uint256 cost1,          // 第一个代币的存款数量
    address indexed mint2,  // 第二个代币的合约地址
    uint256 cost2,          // 第二个代币的存款数量
    uint256 timestamp       // 事件发生的时间戳
);