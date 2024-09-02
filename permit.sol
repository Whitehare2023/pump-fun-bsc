// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./state.sol"; // 确保导入 state.sol 中的结构和事件
import "./error.sol"; // 确保导入 error.sol 中的错误定义

contract PermitToken {
    CurveInfoPart1 public curveInfoPart1;
    CurveInfoPart2 public curveInfoPart2;

    constructor(address initialOwner) {
        // 在构造函数中初始化所有权
    }

    function permit(
        address user,
        address quoteMint,
        address baseMint
    ) public {
        require(user == curveInfoPart1.creator, ErrorCode.InvalidCreator);
        require(!curveInfoPart2.isOnPancake, ErrorCode.InvalidParameters);

        if (curveInfoPart2.isLaunchPermitted) {
            curveInfoPart2.isLaunchPermitted = false;
        } else {
            curveInfoPart2.isLaunchPermitted = true;
        }

        if (curveInfoPart2.isLaunchPermitted && curveInfoPart2.quoteBalance >= curveInfoPart1.target) {
            curveInfoPart2.isOnPancake = true;
        }

        // 直接使用 state.sol 中的事件
        emit PermitEvent(
            user,
            baseMint,
            quoteMint,
            curveInfoPart2.isLaunchPermitted,
            curveInfoPart2.isOnPancake,
            block.timestamp
        );
    }
}
