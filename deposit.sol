// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./openzeppelin-contracts/contracts/access/Ownable.sol";

contract Deposit is Ownable {
    address public depositAccount; // 存款接收账户
    address public nativeToken; // 原生代币地址，例如 BNB 或 ETH

    struct DepositArgs {
        string orderId;
        string command;
        string extraInfo;
        uint8 maxIndex;
        uint8 index;
        uint256 cost;
    }

    struct DepositArgs2 {
        string orderId;
        string command;
        string extraInfo;
        uint8 maxIndex;
        uint8 index;
        uint256 cost1;
        uint256 cost2;
    }

    event DepositEvent(
        address indexed user,
        address indexed mint,
        uint256 cost,
        string orderId,
        string command,
        string extraInfo,
        uint8 maxIndex,
        uint8 index,
        uint256 timestamp
    );

    event DepositEvent2(
        address indexed user,
        address indexed mint1,
        uint256 cost1,
        address indexed mint2,
        uint256 cost2,
        string orderId,
        string command,
        string extraInfo,
        uint8 maxIndex,
        uint8 index,
        uint256 timestamp
    );

    constructor(address _depositAccount, address _nativeToken) {
        depositAccount = _depositAccount;
        nativeToken = _nativeToken;
    }

    function deposit(DepositArgs calldata args, address mint, address userTokenAccount) external payable {
        require(args.cost > 0, "Invalid parameters");

        if (mint == nativeToken) {
            // 转账原生代币，例如 BNB 或 ETH
            require(msg.value == args.cost, "Incorrect native token amount");
            payable(depositAccount).transfer(args.cost);
        } else {
            // 转账 ERC20 代币
            require(IERC20(mint).transferFrom(msg.sender, depositAccount, args.cost), "Transfer failed");
        }

        emit DepositEvent(
            msg.sender,
            mint,
            args.cost,
            args.orderId,
            args.command,
            args.extraInfo,
            args.maxIndex,
            args.index,
            block.timestamp
        );
    }

    function deposit2(DepositArgs2 calldata args, address mint1, address mint2, address userTokenAccount1, address userTokenAccount2) external payable {
        require(args.cost1 > 0 && args.cost2 > 0, "Invalid parameters");

        if (mint1 == nativeToken) {
            // 转账第一个原生代币
            require(msg.value == args.cost1, "Incorrect native token amount for mint1");
            payable(depositAccount).transfer(args.cost1);
        } else {
            // 转账第一个 ERC20 代币
            require(IERC20(mint1).transferFrom(msg.sender, depositAccount, args.cost1), "Transfer failed for mint1");
        }

        if (mint2 == nativeToken) {
            // 转账第二个原生代币
            require(msg.value == args.cost2, "Incorrect native token amount for mint2");
            payable(depositAccount).transfer(args.cost2);
        } else {
            // 转账第二个 ERC20 代币
            require(IERC20(mint2).transferFrom(msg.sender, depositAccount, args.cost2), "Transfer failed for mint2");
        }

        emit DepositEvent2(
            msg.sender,
            mint1,
            args.cost1,
            mint2,
            args.cost2,
            args.orderId,
            args.command,
            args.extraInfo,
            args.maxIndex,
            args.index,
            block.timestamp
        );
    }
}
