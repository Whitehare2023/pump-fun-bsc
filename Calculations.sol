// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";

contract Calculations {
    function calculateTokensBought(
        uint256 initVirtualQuoteReserves,
        uint256 initVirtualBaseReserves,
        uint256 currentBaseSupply,
        uint256 currentQuoteBalance,
        uint256 buyQuoteAmount,
        uint8 quoteTokenDecimals,
        uint8 baseTokenDecimals
    ) external pure returns (uint256) {
        uint256 scalingFactorQuote = 10**(18 - quoteTokenDecimals);
        uint256 scalingFactorBase = 10**(18 - baseTokenDecimals);

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

    function calculateNp(
        uint256 initVirtualBaseReserves,
        uint256 currentQuoteBalance,
        uint256 buyQuoteAmount,
        uint256 scalingFactorQuote,
        uint256 scalingFactorBase
    ) internal pure returns (uint256) {
        UD60x18 p = ud((currentQuoteBalance + buyQuoteAmount) * scalingFactorQuote);
        UD60x18 n = ud(initVirtualBaseReserves * scalingFactorBase);
        UD60x18 np = n.mul(p);
        return np.unwrap();
    }

    function calculateMPlusP(
        uint256 initVirtualQuoteReserves,
        uint256 currentQuoteBalance,
        uint256 buyQuoteAmount,
        uint256 scalingFactorQuote
    ) internal pure returns (uint256) {
        UD60x18 m = ud(initVirtualQuoteReserves * scalingFactorQuote);
        UD60x18 p = ud((currentQuoteBalance + buyQuoteAmount) * scalingFactorQuote);
        UD60x18 mPlusP = m.add(p);
        return mPlusP.unwrap();
    }

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
        return tokensBought.unwrap() / (10**(18 - baseTokenDecimals));
    }

    function calculateTokensSold(
        uint256 initVirtualQuoteReserves,
        uint256 initVirtualBaseReserves,
        uint256 currentBaseSupply,
        uint256 currentQuoteBalance,
        uint256 sellBaseAmount,
        uint8 quoteTokenDecimals,
        uint8 baseTokenDecimals
    ) external pure returns (uint256) {
        uint256 scalingFactorQuote = 10 ** (18 - quoteTokenDecimals);
        uint256 scalingFactorBase = 10 ** (18 - baseTokenDecimals);

        UD60x18 k = calculateK(currentBaseSupply, sellBaseAmount, scalingFactorBase);
        UD60x18 m = calculateM(initVirtualQuoteReserves, scalingFactorQuote);
        UD60x18 n = calculateN(initVirtualBaseReserves, scalingFactorBase);
        UD60x18 km = calculateKM(k, m);
        UD60x18 nMinusK = n.sub(k);

        require(nMinusK.unwrap() > 0, "nMinusK is zero, cannot divide by zero");

        return calculateFinalQuoteAmount(currentQuoteBalance, km, nMinusK, scalingFactorQuote);
    }

    function calculateK(
        uint256 currentBaseSupply,
        uint256 sellBaseAmount,
        uint256 scalingFactorBase
    ) internal pure returns (UD60x18) {
        return ud(currentBaseSupply * scalingFactorBase).sub(ud(sellBaseAmount * scalingFactorBase));
    }

    function calculateM(
        uint256 initVirtualQuoteReserves,
        uint256 scalingFactorQuote
    ) internal pure returns (UD60x18) {
        return ud(initVirtualQuoteReserves * scalingFactorQuote);
    }

    function calculateN(
        uint256 initVirtualBaseReserves,
        uint256 scalingFactorBase
    ) internal pure returns (UD60x18) {
        return ud(initVirtualBaseReserves * scalingFactorBase);
    }

    function calculateKM(
        UD60x18 k,
        UD60x18 m
    ) internal pure returns (UD60x18) {
        return k.mul(m);
    }

    function calculateFinalQuoteAmount(
        uint256 currentQuoteBalance,
        UD60x18 km,
        UD60x18 nMinusK,
        uint256 scalingFactorQuote
    ) internal pure returns (uint256) {
        UD60x18 quoteAmount = ud(currentQuoteBalance * scalingFactorQuote).sub(km.div(nMinusK));
        return quoteAmount.unwrap() / scalingFactorQuote;
    }
}
