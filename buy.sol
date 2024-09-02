// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./formula.sol";
import "./state.sol";
import "./token.sol";
import "./error.sol";  

contract BuyToken is Ownable {
    using SafeERC20 for IERC20;

    struct BuyArgs {
        uint256 quoteCost;
        uint256 minBaseAmount;
    }

    PumpFormula public pumpFormula;

    CurveInfoPart1 public curveInfoPart1;
    CurveInfoPart2 public curveInfoPart2;

    constructor(address _pumpFormulaAddress, address initialOwner) Ownable(initialOwner) {
        pumpFormula = PumpFormula(_pumpFormulaAddress);
    }

    function buy(
        BuyArgs memory args,
        address user,
        address quoteMint,
        address baseMint,
        address feeRecipientAccount,
        address bondingCurveQuote,
        address bondingCurveBase,
        address userBaseAccount
    ) public onlyOwner {
        require(!curveInfoPart2.isOnPancake, ErrorCode.OnPancake);  

        uint256 feeQuoteAmount = (args.quoteCost * curveInfoPart2.feeBps) / 10000;
        uint256 swapQuoteAmount = args.quoteCost - feeQuoteAmount;

        if (curveInfoPart2.isLaunchPermitted) {
            if (swapQuoteAmount + curveInfoPart2.quoteBalance >= curveInfoPart1.target) {
                swapQuoteAmount = curveInfoPart1.target - curveInfoPart2.quoteBalance;
                feeQuoteAmount = ((swapQuoteAmount * 10000) / (10000 - curveInfoPart2.feeBps)) - swapQuoteAmount;
                curveInfoPart2.isOnPancake = true;
            }
        }

        IERC20(quoteMint).safeTransferFrom(user, feeRecipientAccount, feeQuoteAmount);
        IERC20(quoteMint).safeTransferFrom(user, bondingCurveQuote, swapQuoteAmount);

        uint256 destinationBaseAmount = pumpFormula.buy(
            curveInfoPart2.baseSupply,
            curveInfoPart2.quoteBalance,
            swapQuoteAmount
        );

        require(destinationBaseAmount >= args.minBaseAmount, ErrorCode.ExceededSlippage);

        IERC20(baseMint).safeTransferFrom(bondingCurveBase, userBaseAccount, destinationBaseAmount);

        curveInfoPart2.quoteBalance += swapQuoteAmount;
        curveInfoPart2.baseSupply += destinationBaseAmount;

        emit TradeEventPart1(
            quoteMint,
            baseMint,
            swapQuoteAmount + feeQuoteAmount
        );

        emit TradeEventPart2(
            destinationBaseAmount,
            feeQuoteAmount,
            true,
            user
        );

        emit TradeEventPart3(
            block.timestamp,
            curveInfoPart1.initVirtualQuoteReserves + curveInfoPart2.quoteBalance,
            curveInfoPart1.initVirtualBaseReserves - curveInfoPart2.baseSupply
        );

        emit TradeEventPart4(
            curveInfoPart2.quoteBalance,
            curveInfoPart2.baseSupply
        );

        emit TradeEventPart5(
            curveInfoPart2.initSupply,
            curveInfoPart1.target,
            curveInfoPart1.initVirtualQuoteReserves,
            curveInfoPart1.initVirtualBaseReserves
        );

        emit TradeEventPart6(
            IERC20(quoteMint).balanceOf(user) - swapQuoteAmount - feeQuoteAmount
        );

        emit TradeEventPart7(
            IERC20(baseMint).balanceOf(user) + destinationBaseAmount
        );

        emit TradeEventPart8(
            curveInfoPart2.feeBps,
            curveInfoPart2.createFee,
            curveInfoPart2.isOnPancake
        );
    }
}
