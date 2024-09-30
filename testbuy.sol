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
        uint8 tokenDecimals  // 代币的精度
    ) public pure returns (uint256) {
        // 动态调整精度因子，确保所有数值统一到 18 位小数精度
        uint256 scalingFactor = 10**(18 - tokenDecimals);
        uint256 fullPrecisionFactor = 10**18;  // 18 位精度的标准因子

        // 将输入统一转换为 18 位精度的最小单位
        UD60x18 m = ud(initVirtualQuoteReserves * fullPrecisionFactor);  // 初始虚拟报价储备
        UD60x18 p = ud((currentQuoteBalance + buyQuoteAmount) * fullPrecisionFactor);  // 当前报价余额 + 购买金额
        UD60x18 n = ud(initVirtualBaseReserves * fullPrecisionFactor);  // 初始虚拟基础储备

        // 计算 np 和 mPlusP
        UD60x18 np = n.mul(p);
        UD60x18 mPlusP = m.add(p);

        // 计算出的 tokensBought 需要减去 currentBaseSupply 的精度处理
        UD60x18 tokensBought = np.div(mPlusP).sub(ud(currentBaseSupply * fullPrecisionFactor));

        // **注意**：这里返回结果前，将数值转换回原始代币精度
        return tokensBought.unwrap() / scalingFactor;
    }

    // 测试函数，输入指定参数并返回计算结果
    function testBuyWithDecimals(uint8 decimals) public pure returns (uint256) {
        // 设置测试参数
        uint256 initVirtualQuoteReserves = 30;  // 初始虚拟报价储备
        uint256 initVirtualBaseReserves = 1073000000;  // 初始虚拟基础储备
        uint256 currentBaseSupply = 0;  // 当前基础供应量为 0
        uint256 currentQuoteBalance = 0;  // 当前报价余额为 0
        uint256 buyQuoteAmount = 1;  // 用户购买 1 个报价代币

        // 调用 calculateTokensBought 函数，传入代币精度
        return calculateTokensBought(
            initVirtualQuoteReserves,
            initVirtualBaseReserves,
            currentBaseSupply,
            currentQuoteBalance,
            buyQuoteAmount,
            decimals  // 动态传入代币精度
        );
    }
}
