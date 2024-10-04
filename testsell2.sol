// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { UD60x18, ud } from "@prb/math/src/UD60x18.sol"; // 引入 PRBMathUD60x18 库

contract TestSellCalculation {

    // 计算卖出代币数量的公式逻辑，考虑到 baseToken 和 quoteToken 的不同精度
    function calculateTokensSold(
        uint256 initVirtualQuoteReserves,
        uint256 initVirtualBaseReserves,
        uint256 currentBaseSupply,
        uint256 currentQuoteBalance,
        uint256 sellBaseAmount,
        uint8 quoteTokenDecimals,  // quoteToken 的精度
        uint8 baseTokenDecimals    // baseToken 的精度
    ) public pure returns (uint256) {
        // 动态调整精度因子，确保所有数值统一到 18 位小数精度
        uint256 scalingFactorQuote = 10**(18 - quoteTokenDecimals);  // 调整为 18 位精度
        uint256 scalingFactorBase = 10**(18 - baseTokenDecimals);    // 调整为 18 位精度

        // 拆分计算，减少局部变量的深度
        UD60x18 k = calculateK(currentBaseSupply, sellBaseAmount, scalingFactorBase);
        UD60x18 m = calculateM(initVirtualQuoteReserves, scalingFactorQuote);
        UD60x18 n = calculateN(initVirtualBaseReserves, scalingFactorBase);
        UD60x18 km = calculateKM(k, m);
        UD60x18 nMinusK = n.sub(k);

        // 检查除法是否会导致溢出
        require(nMinusK.unwrap() > 0, "nMinusK is zero, cannot divide by zero");

        // 计算出的 quoteAmount 是用户卖出基础代币后获得的报价代币数量
        UD60x18 quoteAmount = calculateQuoteAmount(currentQuoteBalance, km, nMinusK, scalingFactorQuote);

        // **注意**：返回前将结果转换回代币的原始精度
        return quoteAmount.unwrap() / scalingFactorQuote;
    }

    // 计算 K (当前基础代币供应 - 卖出的基础代币)
    function calculateK(uint256 currentBaseSupply, uint256 sellBaseAmount, uint256 scalingFactorBase) internal pure returns (UD60x18) {
        return ud(currentBaseSupply * scalingFactorBase).sub(ud(sellBaseAmount * scalingFactorBase));
    }

    // 计算 M (初始虚拟报价储备)
    function calculateM(uint256 initVirtualQuoteReserves, uint256 scalingFactorQuote) internal pure returns (UD60x18) {
        return ud(initVirtualQuoteReserves * scalingFactorQuote);
    }

    // 计算 N (初始虚拟基础储备)
    function calculateN(uint256 initVirtualBaseReserves, uint256 scalingFactorBase) internal pure returns (UD60x18) {
        return ud(initVirtualBaseReserves * scalingFactorBase);
    }

    // 计算 K * M
    function calculateKM(UD60x18 k, UD60x18 m) internal pure returns (UD60x18) {
        return k.mul(m);
    }

    // 计算卖出基础代币后获得的报价代币数量
    function calculateQuoteAmount(
        uint256 currentQuoteBalance,
        UD60x18 km,
        UD60x18 nMinusK,
        uint256 scalingFactorQuote
    ) internal pure returns (UD60x18) {
        return ud(currentQuoteBalance * scalingFactorQuote).sub(km.div(nMinusK));
    }

    // 测试函数，模拟用户卖出代币的情况，考虑 baseToken 和 quoteToken 的不同精度
    function testSellWithDecimals(
        uint8 quoteTokenDecimals,  // quoteToken 的精度
        uint8 baseTokenDecimals    // baseToken 的精度
    ) public pure returns (uint256) {
        // 设置测试参数
        uint256 initVirtualQuoteReserves = 30 * (10 ** quoteTokenDecimals);  // 初始虚拟报价储备，基于 quoteToken 精度
        uint256 initVirtualBaseReserves = 1073000000 * (10 ** baseTokenDecimals);  // 初始虚拟基础储备，基于 baseToken 精度
        uint256 currentBaseSupply = 34277831558567;  // 当前基础代币供应
        uint256 currentQuoteBalance = 990000000;  // 当前报价余额
        uint256 sellBaseAmount = 34277831558567;  // 卖出基础代币数量

        // 调用 calculateTokensSold 函数，传入代币的不同精度
        return calculateTokensSold(
            initVirtualQuoteReserves,
            initVirtualBaseReserves,
            currentBaseSupply,
            currentQuoteBalance,
            sellBaseAmount,
            quoteTokenDecimals,  // 动态传入 quoteToken 的精度
            baseTokenDecimals    // 动态传入 baseToken 的精度
        );
    }

    // 新增：测试函数，考虑手续费的情况下
    function testSellWithDecimalsAndFee(
        uint8 quoteTokenDecimals,  // quoteToken 的精度
        uint8 baseTokenDecimals,   // baseToken 的精度
        uint256 feeBps             // 手续费的基点 (1 BPS = 0.01%)
    ) public pure returns (uint256, uint256) {
        // 计算卖出时获得的总 quoteAmount
        uint256 totalQuoteAmount = testSellWithDecimals(quoteTokenDecimals, baseTokenDecimals);

        // 计算手续费：1% 的手续费
        uint256 feeAmount = (totalQuoteAmount * feeBps) / 10000;
        uint256 netQuoteAmount = totalQuoteAmount - feeAmount;

        return (netQuoteAmount, feeAmount);
    }
}
