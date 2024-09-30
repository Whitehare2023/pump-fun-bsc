// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./state.sol";  // 引入 state.sol 以使用 ProgramConfig 结构
import "./error.sol";  // 引入 error.sol 以使用 ErrorCode
import "./openzeppelin-contracts/contracts/access/Ownable.sol";

contract InitializeConfig is Ownable {

    // ProgramConfig 实例
    ProgramConfig public programConfig;

    // 构造函数，设置合约拥有者
    constructor(address initialOwner) Ownable(initialOwner) {}

    // 初始化配置参数
    function initializeConfig(
        address platform,
        address feeRecipientAccount,
        address depositAccount,
        uint256 baseMinSupply,
        uint256 baseMaxSupply,
        uint256 createFee,
        uint256 baseMinFeeRate,
        uint256 baseMaxFeeRate
    ) public onlyOwner {
        require(!programConfig.isInitialized, "Already initialized.");

        uint256 adjustedBaseMinSupply = baseMinSupply;
        uint256 adjustedBaseMaxSupply = baseMaxSupply;

        // 设置配置参数
        programConfig = ProgramConfig({
            isInitialized: true,
            bump: 0,  // 这里的 bump 是一个占位符，只是为了跟 Solana 参数保持一致
            admin: msg.sender,
            platform: platform,
            feeRecipientAccount: feeRecipientAccount,
            depositAccount: depositAccount,
            baseMinSupply: adjustedBaseMinSupply,
            baseMaxSupply: adjustedBaseMaxSupply,
            createFee: createFee,
            baseMinFeeRate: baseMinFeeRate,
            baseMaxFeeRate: baseMaxFeeRate
        });
    }

    // 获取 ProgramConfig 数据
    function getProgramConfig() external view returns (
        bool, uint8, address, address, address, address, uint256, uint256, uint256, uint256, uint256
    ) {
        return (
            programConfig.isInitialized,
            programConfig.bump,
            programConfig.admin,
            programConfig.platform,
            programConfig.feeRecipientAccount,
            programConfig.depositAccount,
            programConfig.baseMinSupply,
            programConfig.baseMaxSupply,
            programConfig.createFee,
            programConfig.baseMinFeeRate,
            programConfig.baseMaxFeeRate
        );
    }

    // 添加更新函数
    function updateAdmin(address newAdmin) external onlyOwner {
        require(newAdmin != address(0), "Invalid new admin address");
        programConfig.admin = newAdmin;
    }

    function updatePlatform(address newPlatform) external onlyOwner {
        require(newPlatform != address(0), "Invalid new platform address");
        programConfig.platform = newPlatform;
    }

    function updateFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(newFeeRecipient != address(0), "Invalid new fee recipient address");
        programConfig.feeRecipientAccount = newFeeRecipient;
    }

    function updateDepositAccount(address newDepositAccount) external onlyOwner {
        require(newDepositAccount != address(0), "Invalid new deposit account address");
        programConfig.depositAccount = newDepositAccount;
    }

    function updateSupplyLimits(uint256 newBaseMinSupply, uint256 newBaseMaxSupply) external onlyOwner {
        require(newBaseMinSupply <= newBaseMaxSupply, "Min supply must be less than or equal to max supply");

        uint256 adjustedNewBaseMinSupply = newBaseMinSupply;
        uint256 adjustedNewBaseMaxSupply = newBaseMaxSupply;

        programConfig.baseMinSupply = adjustedNewBaseMinSupply;
        programConfig.baseMaxSupply = adjustedNewBaseMaxSupply;
    }

    function updateFeeRates(uint256 newBaseMinFeeRate, uint256 newBaseMaxFeeRate) external onlyOwner {
        require(newBaseMinFeeRate <= newBaseMaxFeeRate, "Min fee rate must be less than or equal to max fee rate");
        programConfig.baseMinFeeRate = newBaseMinFeeRate;
        programConfig.baseMaxFeeRate = newBaseMaxFeeRate;
    }

    function updateCreateFee(uint256 newCreateFee) external onlyOwner {
        programConfig.createFee = newCreateFee;
    }
}
