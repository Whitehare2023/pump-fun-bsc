# sepolia 测试

initializeConfig 参数：

1. **baseMinSupply**：100000000 （1 亿，不乘以精度）
2. **baseMaxSupply**：100000000000 （1,000 亿，不乘以精度）
3. **baseMinFeeRate**：1%（100 基点）
4. **baseMaxFeeRate**：50%（5000 基点）
5. **createFee**：0.02 个 BNB（以 wei 为单位，如果 BNB 的最小单位是 10^18 wei，那么 0.02 BNB = 0.02 × 10^18 = 20000000000000000 wei）
6. programConfig.admin address: 
   0x9E948eB280dFee511c1df2906913da0Cb0671932
7. programConfig.platform address: 0xE5fC99493Dbeef9dfA5Aa5336b35c5d32FE3e2Fe
8. programConfig.feeRecipientAccount address: 0x220DA69Dc256114B0455cB61f953C8E25b41c1f6
9. programConfig.depositAccount address: 0x6ccEB0EF13934D850baE2627077f91612efcd94f



**InitializeConfig 合约地址**: 0x83f8067fc818BDA28Ed02Bb9F0a2f2C982a0d2e7

**QuoteTokenManager 合约地址**: 0x8C52E9257ccC2Dc852563aba7dF88bB094C6FF14

**PumpFormula 合约地址**: 0x7CD18636A7Cdc608540453fa6d5Df895fd3a4A02

CustomToken 合约地址：0xD5a1fE9Ee4Bf299565ef447E55bd25c0cC6E0EED

TokenFactory 合约地址：
0x670FAB30c1b14BF2CF88C71f4340a3352F4164Be

createToken 合约地址：
0x671e3971Ca24d26Be0652715267d978B743569e0



WBNB testnet 合约地址：
0x0dE8FCAE8421fc79B29adE9ffF97854a424Cad09

在 createToken 之前，要去 swap 一下 WBNB 然后申请权限：
https://testnet.bscscan.com/token/0x0dE8FCAE8421fc79B29adE9ffF97854a424Cad09?a=CREATE_TOKEN_ADDRESS#writeContract

### createToken 参数：

tokenFactory：

["TestToken", "TTK", "https://aquamarine-cheerful-giraffe-141.mypinata.cloud/ipfs/QmfCPNvgraRie4WuW6t92hzH8TcAiD2CYEhCNWvbBTHjSb","0x9E948eB280dFee511c1df2906913da0Cb0671932",1000000000, 85000000, 30000000, 1073000000, 100, 20000000000000000, true]

createArgs：
["TestToken", "TTK", "https://aquamarine-cheerful-giraffe-141.mypinata.cloud/ipfs/QmfCPNvgraRie4WuW6t92hzH8TcAiD2CYEhCNWvbBTHjSb", 1000000000, 85000000, 30000000, 1073000000, 100, true]

msg.value = 20000000000000000

每个参数分别是：

**Token Name (`name`)**: `"TestToken"` (string)

**Token Symbol (`symbol`)**: `"TTK"` (string)

**URI (`uri`)**: `"https://aquamarine-cheerful-giraffe-141.mypinata.cloud/ipfs/QmfCPNvgraRie4WuW6t92hzH8TcAiD2CYEhCNWvbBTHjSb"` (string)

**Initial Supply (`initialSupply`)**: `100000000000000` (uint256)

**Target (`target`)**: `85000000` (uint256)

**Initial Virtual Quote Reserves (`initVirtualQuoteReserves`)**: `30000000` (uint256)

**Initial Virtual Base Reserves (`initVirtualBaseReserves`)**: `1073000000` (uint256)

**Fee Bps (`feeBps`)**: `100` (uint256)

**Is Launch Permitted (`isLaunchPermitted`)**: `true` (bool)

// User 地址
"0x9E948eB280dFee511c1df2906913da0Cb0671932"

// QuoteMint 地址
"0x0dE8FCAE8421fc79B29adE9ffF97854a424Cad09"

