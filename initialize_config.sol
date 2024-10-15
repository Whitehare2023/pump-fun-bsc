// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./state.sol";  // 引入 state.sol 以使用 ProgramConfig 结构
import "./error.sol";  // 引入 error.sol 以使用 ErrorCode
import "./openzeppelin-contracts/contracts/access/Ownable.sol";

contract InitializeConfig is Ownable {

    // 默认的初始化参数，状态变量
    uint256 public baseMinSupply = 1000000000;
    uint256 public baseMaxSupply = 10000000000000000000;
    uint256 public baseMinFeeRate = 100; // 1%
    uint256 public baseMaxFeeRate = 5000; // 50%
    uint256 public createFee = 100000000000000000; // 0.1 BNB (in wei)

    address public platform = 0xE5fC99493Dbeef9dfA5Aa5336b35c5d32FE3e2Fe;
    address public feeRecipientAccount = 0x220DA69Dc256114B0455cB61f953C8E25b41c1f6;
    address public depositAccount = 0x6ccEB0EF13934D850baE2627077f91612efcd94f;

    constructor(address initialOwner) Ownable(initialOwner){
        
    }

    // 更新平台地址
    function updatePlatform(address newPlatform) external onlyOwner {
        require(newPlatform != address(0), "Invalid platform address");
        platform = newPlatform;
    }

    // 更新手续费接收账户
    function updateFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(newFeeRecipient != address(0), "Invalid fee recipient address");
        feeRecipientAccount = newFeeRecipient;
    }

    // 更新存款账户
    function updateDepositAccount(address newDepositAccount) external onlyOwner {
        require(newDepositAccount != address(0), "Invalid deposit account address");
        depositAccount = newDepositAccount;
    }

    // 更新代币的最小和最大供应量
    function updateSupplyLimits(uint256 newBaseMinSupply, uint256 newBaseMaxSupply) external onlyOwner {
        require(newBaseMinSupply <= newBaseMaxSupply, "Min supply must be <= max supply");
        baseMinSupply = newBaseMinSupply;
        baseMaxSupply = newBaseMaxSupply;
    }

    // 更新手续费率
    function updateFeeRates(uint256 newBaseMinFeeRate, uint256 newBaseMaxFeeRate) external onlyOwner {
        require(newBaseMinFeeRate <= newBaseMaxFeeRate, "Min fee rate must be <= max fee rate");
        baseMinFeeRate = newBaseMinFeeRate;
        baseMaxFeeRate = newBaseMaxFeeRate;
    }

    // 更新创建费
    function updateCreateFee(uint256 newCreateFee) external onlyOwner {
        createFee = newCreateFee;
    }
}
