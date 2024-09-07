// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./add_quote_token.sol";  // 引入 QuoteTokenManager 合约
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";  // 正确导入 UD60x18 库

contract PumpFormula {
    QuoteTokenManager public quoteTokenManager;  // 引用 QuoteTokenManager 合约实例

    constructor(address _quoteTokenManagerAddress) {
        quoteTokenManager = QuoteTokenManager(_quoteTokenManagerAddress);
    }

    function buy(
        address quoteMint,
        uint256 currentBaseSupply,
        uint256 currentQuoteBalance,
        uint256 buyQuoteAmount
    ) public view returns (uint256) {
        // 动态获取虚拟储备值
        (uint256 initVirtualQuoteReserves, uint256 initVirtualBaseReserves) = getVirtualReserves(quoteMint);

        // 动态获取代币的精度
        uint256 decimals = quoteTokenManager.getQuoteTokenDecimals(quoteMint);
        UD60x18 scalingFactor = ud(10 ** decimals);  // 将 10^decimals 转换为 UD60x18 格式

        // 使用 UD60x18 进行浮点数运算
        UD60x18 m = ud(initVirtualQuoteReserves);
        UD60x18 p = ud(currentQuoteBalance + buyQuoteAmount).mul(scalingFactor);
        UD60x18 n = ud(initVirtualBaseReserves);

        UD60x18 np = n.mul(p);
        UD60x18 mPlusP = m.add(p);

        uint256 tokensBought = np.div(mPlusP).unwrap() - currentBaseSupply;

        return tokensBought > 0 ? tokensBought : 0;
    }

    function sell(
        address quoteMint,
        uint256 currentBaseSupply,
        uint256 currentQuoteBalance,
        uint256 sellBaseAmount
    ) public view returns (uint256) {
        require(currentBaseSupply >= sellBaseAmount, "Sell base amount exceeds current base supply");

        // 动态获取虚拟储备值
        (uint256 initVirtualQuoteReserves, uint256 initVirtualBaseReserves) = getVirtualReserves(quoteMint);

        // 动态获取代币的精度
        uint256 decimals = quoteTokenManager.getQuoteTokenDecimals(quoteMint);
        UD60x18 scalingFactor = ud(10 ** decimals);  // 将 10^decimals 转换为 UD60x18 格式

        // 使用 UD60x18 进行浮点数运算
        UD60x18 k = ud(currentBaseSupply - sellBaseAmount).mul(scalingFactor);
        UD60x18 m = ud(initVirtualQuoteReserves);
        UD60x18 n = ud(initVirtualBaseReserves);

        UD60x18 km = k.mul(m);
        UD60x18 nMinusK = n.sub(k);

        require(nMinusK.unwrap() > 0, "nMinusK is zero, cannot divide by zero");
        uint256 lamportsReceived = currentQuoteBalance - km.div(nMinusK).unwrap();

        return lamportsReceived > 0 ? lamportsReceived : 0;
    }

    // 从 QuoteTokenManager 获取虚拟储备值
    function getVirtualReserves(address quoteMint) internal view returns (uint256, uint256) {
        QuoteTokenManager.QuoteTokenInfo memory quoteInfo = quoteTokenManager.getQuoteTokenInfo(quoteMint);
        require(quoteInfo.quoteMint != address(0), "Invalid quoteMint provided");

        uint256 initVirtualQuoteReserves = uint256(uint160(quoteInfo.feeRecipientAccount));
        uint256 initVirtualBaseReserves = uint256(uint160(quoteInfo.feeRecipientQuote));
        return (initVirtualQuoteReserves, initVirtualBaseReserves);
    }
}