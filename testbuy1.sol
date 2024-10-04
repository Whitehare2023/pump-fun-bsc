// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { UD60x18, ud } from "@prb/math/src/UD60x18.sol"; // 引入 PRBMathUD60x18 库

contract TestBuyCalculation {

    // 计算购买代币数量的公式逻辑
    function calculateTokensBought(
        uint256 initVirtualQuoteReserves,
        uint256 initVirtualBaseReserves,
        uint256 currentBaseSupply,
        uint256 currentQuoteBalance,
        uint256 buyQuoteAmount,
        uint8 quoteTokenDecimals,  // 传入 quoteToken 的精度
        uint8 baseTokenDecimals   // 传入 baseToken 的精度
    ) public pure returns (uint256) {
        // 动态调整精度因子，确保所有数值统一到 18 位小数精度
        uint256 scalingFactorQuote = 10**(18 - quoteTokenDecimals);  // 调整为 18 位精度
        uint256 scalingFactorBase = 10**(18 - baseTokenDecimals);  // 调整为 18 位精度

        // 将输入统一转换为 18 位精度的最小单位
        uint256 npResult = calculateNp(
            initVirtualBaseReserves,
            currentQuoteBalance,
            buyQuoteAmount,
            scalingFactorQuote,
            scalingFactorBase
        );

        uint256 mPlusPResult = calculateMPlusP(
            initVirtualQuoteReserves,
            currentQuoteBalance,
            buyQuoteAmount,
            scalingFactorQuote
        );

        return calculateFinalTokensBought(
            npResult,
            mPlusPResult,
            currentBaseSupply,
            scalingFactorBase,
            baseTokenDecimals
        );
    }

    // 计算手续费后的购买代币数量
    function calculateTokensBoughtWithFee(
        uint256 initVirtualQuoteReserves,
        uint256 initVirtualBaseReserves,
        uint256 currentBaseSupply,
        uint256 currentQuoteBalance,
        uint256 buyQuoteAmount,
        uint256 feeBps,  // 手续费率（基点）
        uint8 quoteTokenDecimals,  // 传入 quoteToken 的精度
        uint8 baseTokenDecimals   // 传入 baseToken 的精度
    ) public pure returns (uint256) {
        // 计算扣除手续费后的 quoteAmount
        uint256 feeAmount = (buyQuoteAmount * feeBps) / 10000;
        uint256 netQuoteAmount = buyQuoteAmount - feeAmount;  // 扣除手续费后的实际报价代币数量

        return calculateTokensBought(
            initVirtualQuoteReserves,
            initVirtualBaseReserves,
            currentBaseSupply,
            currentQuoteBalance,
            netQuoteAmount,
            quoteTokenDecimals,
            baseTokenDecimals
        );
    }

    // 分开的第一步：计算 np (n * p)
    function calculateNp(
        uint256 initVirtualBaseReserves,
        uint256 currentQuoteBalance,
        uint256 buyQuoteAmount,
        uint256 scalingFactorQuote,
        uint256 scalingFactorBase
    ) internal pure returns (uint256) {
        UD60x18 p = ud((currentQuoteBalance + buyQuoteAmount) * scalingFactorQuote);  // p
        UD60x18 n = ud(initVirtualBaseReserves * scalingFactorBase);  // n
        UD60x18 np = n.mul(p);  // n * p
        return np.unwrap();
    }

    // 分开的第二步：计算 mPlusP (m + p)
    function calculateMPlusP(
        uint256 initVirtualQuoteReserves,
        uint256 currentQuoteBalance,
        uint256 buyQuoteAmount,
        uint256 scalingFactorQuote
    ) internal pure returns (uint256) {
        UD60x18 m = ud(initVirtualQuoteReserves * scalingFactorQuote);  // m
        UD60x18 p = ud((currentQuoteBalance + buyQuoteAmount) * scalingFactorQuote);  // p
        UD60x18 mPlusP = m.add(p);  // m + p
        return mPlusP.unwrap();
    }

    // 分开的第三步：计算最终的 tokensBought
    function calculateFinalTokensBought(
        uint256 npResult,
        uint256 mPlusPResult,
        uint256 currentBaseSupply,
        uint256 scalingFactorBase,
        uint8 baseTokenDecimals
    ) internal pure returns (uint256) {
        UD60x18 np = ud(npResult);
        UD60x18 mPlusP = ud(mPlusPResult);
        UD60x18 tokensBought = np.div(mPlusP).sub(ud(currentBaseSupply * scalingFactorBase));
        return tokensBought.unwrap() / (10**(18 - baseTokenDecimals));  // 还原精度
    }

    // 测试函数，输入指定参数并返回计算结果（不考虑手续费）
    function testBuyWithDecimals(uint8 quoteTokenDecimals, uint8 baseTokenDecimals) public pure returns (uint256) {
        // 设置测试参数
        uint256 initVirtualQuoteReserves = 30000000000;  // 30 * 10^9
        uint256 initVirtualBaseReserves = 1073000000 * 10**baseTokenDecimals;  // 1073 * 10^6
        uint256 currentBaseSupply = 0;  // 当前基础供应量为 0
        uint256 currentQuoteBalance = 0;  // 当前报价余额为 0
        uint256 buyQuoteAmount = 1000000000;  // 用户购买 1 个报价代币，基于最小单位

        // 调用 calculateTokensBought 函数
        return calculateTokensBought(
            initVirtualQuoteReserves,
            initVirtualBaseReserves,
            currentBaseSupply,
            currentQuoteBalance,
            buyQuoteAmount,
            quoteTokenDecimals,
            baseTokenDecimals
        );
    }

    // 测试函数，输入指定参数并返回计算结果（考虑手续费）
    function testBuyWithDecimalsAndFee(uint8 quoteTokenDecimals, uint8 baseTokenDecimals, uint256 feeBps) public pure returns (uint256) {
        // 设置测试参数
        uint256 initVirtualQuoteReserves = 30000000000;  // 30 * 10^9
        uint256 initVirtualBaseReserves = 1073000000 * 10**baseTokenDecimals;  // 1073 * 10^6
        uint256 currentBaseSupply = 0;  // 当前基础供应量为 0
        uint256 currentQuoteBalance = 0;  // 当前报价余额为 0
        uint256 buyQuoteAmount = 1000000000;  // 用户购买 1 个报价代币，基于最小单位

        // 调用 calculateTokensBoughtWithFee 函数，考虑手续费
        return calculateTokensBoughtWithFee(
            initVirtualQuoteReserves,
            initVirtualBaseReserves,
            currentBaseSupply,
            currentQuoteBalance,
            buyQuoteAmount,
            feeBps,
            quoteTokenDecimals,
            baseTokenDecimals
        );
    }
}
