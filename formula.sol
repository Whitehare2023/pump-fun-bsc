// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./add_quote_token.sol";  // 引入 QuoteTokenManager 合约
import "./ABDKMath64x64.sol"; // 引入 ABDKMath64x64 库

contract PumpFormula {
    using ABDKMath64x64 for int128; // 使用 ABDKMath64x64 库
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
        uint256 scalingFactor = 10**decimals;

        // 使用 ABDKMath64x64 进行浮点数运算
        int128 m = ABDKMath64x64.fromUInt(initVirtualQuoteReserves);
        int128 p = ABDKMath64x64.fromUInt(currentQuoteBalance + buyQuoteAmount).mul(ABDKMath64x64.fromUInt(scalingFactor));
        int128 n = ABDKMath64x64.fromUInt(initVirtualBaseReserves);

        int128 np = n.mul(p);
        int128 mPlusP = m.add(p);

        int128 tokensBought = np.div(mPlusP).sub(ABDKMath64x64.fromUInt(currentBaseSupply));

        if (tokensBought > 0) {
            return ABDKMath64x64.toUInt(tokensBought);
        } else {
            return 0;
        }
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
        uint256 scalingFactor = 10**decimals;

        // 使用 ABDKMath64x64 进行浮点数运算
        int128 k = ABDKMath64x64.fromUInt(currentBaseSupply - sellBaseAmount).mul(ABDKMath64x64.fromUInt(scalingFactor));
        int128 m = ABDKMath64x64.fromUInt(initVirtualQuoteReserves);
        int128 n = ABDKMath64x64.fromUInt(initVirtualBaseReserves);

        int128 km = k.mul(m);
        int128 nMinusK = n.sub(k);

        require(nMinusK > 0, "nMinusK is zero, cannot divide by zero"); // 防止除以零错误
        int128 lamportsReceived = ABDKMath64x64.fromUInt(currentQuoteBalance).sub(km.div(nMinusK));

        if (lamportsReceived > 0) {
            return ABDKMath64x64.toUInt(lamportsReceived);
        } else {
            return 0;
        }
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