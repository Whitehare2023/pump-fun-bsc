// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";  // 引入 PRBMathUD60x18 库

contract Calculations {

    // 计算 np
    function calculateNp(
        uint256 initVirtualBaseReserves,
        uint256 scalingFactorBase,
        uint256 currentQuoteBalance,
        uint256 buyQuoteAmount,
        uint256 scalingFactorQuote
    ) external pure returns (UD60x18) {
        return ud(initVirtualBaseReserves * scalingFactorBase)
            .mul(ud((currentQuoteBalance + buyQuoteAmount) * scalingFactorQuote));
    }

    // 计算 mPlusP
    function calculateMPlusP(
        uint256 initVirtualQuoteReserves,
        uint256 currentQuoteBalance,
        uint256 buyQuoteAmount,
        uint256 scalingFactorQuote
    ) external pure returns (UD60x18) {
        return ud(initVirtualQuoteReserves * scalingFactorQuote)
            .add(ud((currentQuoteBalance + buyQuoteAmount) * scalingFactorQuote));
    }

    // 计算买入代币数量
    function calculateTokensBought(
        uint256 initVirtualQuoteReserves,
        uint256 initVirtualBaseReserves,
        uint256 currentBaseSupply,
        uint256 currentQuoteBalance,
        uint256 buyQuoteAmount,
        uint8 quoteTokenDecimals,
        uint8 baseTokenDecimals
    ) external pure returns (uint256) {
        uint256 scalingFactorQuote = 10**(18 - quoteTokenDecimals);  // 调整为 18 位精度
        uint256 scalingFactorBase = 10**(18 - baseTokenDecimals);    // 调整为 18 位精度

        // 计算 np 和 mPlusP
        UD60x18 np = ud(initVirtualBaseReserves * scalingFactorBase)
            .mul(ud((currentQuoteBalance + buyQuoteAmount) * scalingFactorQuote));
        UD60x18 mPlusP = ud(initVirtualQuoteReserves * scalingFactorQuote)
            .add(ud((currentQuoteBalance + buyQuoteAmount) * scalingFactorQuote));

        // 计算 tokensBought
        UD60x18 tokensBought = np.div(mPlusP).sub(ud(currentBaseSupply * scalingFactorBase));

        // 返回结果前，将数值转换回原始代币精度
        return tokensBought.unwrap() / (scalingFactorBase * 10 ** baseTokenDecimals);
    }
}
