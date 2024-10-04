// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./openzeppelin-contracts/contracts/access/Ownable.sol";
import "./openzeppelin-contracts/contracts/token/ERC20/ERC20.sol"; // 引入 IERC20 接口以调用 decimals()

contract QuoteTokenManager is Ownable {
    struct QuoteTokenInfo {
        address quoteMint;
        uint8 decimals; // 用于存储代币的精度
        address feeRecipientAccount;
    }

    // 存储支持的报价代币信息
    mapping(address => QuoteTokenInfo) public quoteTokens;
    // 用于存储所有 quoteMint 的数组
    address[] public quoteMints;

    event QuoteTokenAdded(address indexed quoteMint, uint8 decimals, address feeRecipientAccount);

    constructor(address initialOwner) Ownable(initialOwner) {}

    function addQuoteToken(
        address quoteMint,
        address feeRecipientAccount
    ) external onlyOwner {
        require(quoteMint != address(0), "Invalid quote mint address");
        require(feeRecipientAccount != address(0), "Invalid fee recipient address");

        // 确保没有重复添加
        require(quoteTokens[quoteMint].quoteMint == address(0), "Quote token already added");

        // 通过 IERC20 接口调用 decimals() 函数自动获取精度
        uint8 decimals = ERC20(quoteMint).decimals();

        // 存储新的报价代币信息，包括自动获取的精度
        quoteTokens[quoteMint] = QuoteTokenInfo({
            quoteMint: quoteMint,
            decimals: decimals, // 存储自动获取的精度
            feeRecipientAccount: feeRecipientAccount
        });

        // 添加到 quoteMints 数组中
        quoteMints.push(quoteMint);

        emit QuoteTokenAdded(quoteMint, decimals, feeRecipientAccount);
    }

    function getQuoteTokenInfo(address quoteMint) external view returns (QuoteTokenInfo memory) {
        return quoteTokens[quoteMint];
    }

    // 获取报价代币的精度
    function getQuoteTokenDecimals(address quoteMint) external view returns (uint8) {
        require(quoteTokens[quoteMint].quoteMint != address(0), "Quote token not registered");
        return quoteTokens[quoteMint].decimals;
    }

    // 获取所有已注册的 quoteMint 地址
    function getAllQuoteMints() external view returns (address[] memory) {
        return quoteMints;
    }

    // 删除
    function removeQuoteToken(address quoteToken) external onlyOwner {
        require(quoteTokens[quoteToken].quoteMint != address(0), "Quote token not registered");

        // 删除映射中的报价代币信息
        delete quoteTokens[quoteToken];

        // 找到对应的地址在数组中的索引
        for (uint256 i = 0; i < quoteMints.length; i++) {
            if (quoteMints[i] == quoteToken) {
                // 移除数组中的元素
                quoteMints[i] = quoteMints[quoteMints.length - 1]; // 将最后一个元素移动到被删除的位置
                quoteMints.pop(); // 删除最后一个元素
                break;
            }
        }
    }
}
