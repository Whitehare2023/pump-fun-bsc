// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { UD60x18, ud } from "@prb/math/src/UD60x18.sol"; // 引入 PRBMathUD60x18 库

contract TestSellCalculation {

    // 计算卖出代币数量的公式逻辑
    function calculateTokensSold(
        uint256 initVirtualQuoteReserves,
        uint256 initVirtualBaseReserves,
        uint256 currentBaseSupply,
        uint256 currentQuoteBalance,
        uint256 sellBaseAmount,
        uint8 tokenDecimals  // 代币的精度
    ) public pure returns (uint256) {
        // 动态调整精度因子，确保所有数值统一到 18 位小数精度
        uint256 scalingFactor = 10**(18 - tokenDecimals);  // 调整为 18 位精度
        uint256 fullPrecisionFactor = 10**18;  // 18 位精度的标准因子

        // 将输入统一转换为 18 位精度的最小单位
        UD60x18 k = ud(currentBaseSupply * fullPrecisionFactor).sub(ud(sellBaseAmount * fullPrecisionFactor));
        UD60x18 m = ud(initVirtualQuoteReserves * fullPrecisionFactor);  // 初始虚拟报价储备
        UD60x18 n = ud(initVirtualBaseReserves * fullPrecisionFactor);  // 初始虚拟基础储备

        // 计算 k * m 和 n - k
        UD60x18 km = k.mul(m);
        UD60x18 nMinusK = n.sub(k);

        // 检查除法是否会导致溢出
        require(nMinusK.unwrap() > 0, "nMinusK is zero, cannot divide by zero");

        // 计算出的 quoteAmount 是用户卖出基础代币后获得的报价代币数量
        UD60x18 quoteAmount = ud(currentQuoteBalance * fullPrecisionFactor).sub(km.div(nMinusK));

        // **注意**：返回前将结果转换回代币的原始精度
        return quoteAmount.unwrap() / (scalingFactor * 10 ** tokenDecimals);
    }

    // 测试函数，模拟用户卖出代币的情况
    function testSellWithDecimals(uint8 decimals) public pure returns (uint256) {
        // 设置测试参数
        uint256 initVirtualQuoteReserves = 30000000;  // 初始虚拟报价储备，基于最小单位
        uint256 initVirtualBaseReserves = 1073000000000000;  // 初始虚拟基础储备，基于最小单位
        uint256 currentBaseSupply = 34612903225806;  // 当前基础代币供应
        uint256 currentQuoteBalance = 1000000;  // 当前报价余额
        uint256 sellBaseAmount = 34612903225806;  // 卖出基础代币数量

        // 调用 calculateTokensSold 函数，传入代币精度
        return calculateTokensSold(
            initVirtualQuoteReserves,
            initVirtualBaseReserves,
            currentBaseSupply,
            currentQuoteBalance,
            sellBaseAmount,
            decimals  // 动态传入代币精度
        );
    }
}
