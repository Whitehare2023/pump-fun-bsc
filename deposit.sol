// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./openzeppelin-contracts/contracts/access/Ownable.sol";
import "./openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract Deposit is Ownable {
    using SafeERC20 for IERC20;

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

    address public depositAccount;
    address public nativeTokenAddress; // Native token address (e.g., WBNB or WETH)

    constructor(address _depositAccount, address _nativeTokenAddress) Ownable(msg.sender) {
        depositAccount = _depositAccount;
        nativeTokenAddress = _nativeTokenAddress;
    }

    // Single token deposit
    function deposit(
        address user,
        address mint,
        uint256 cost,
        string memory orderId,
        string memory command,
        string memory extraInfo,
        uint8 maxIndex,
        uint8 index
    ) external payable {
        require(cost > 0, "Invalid cost");

        if (mint == nativeTokenAddress) {
            // Handle native token (BNB/ETH)
            require(msg.value == cost, "Incorrect native token amount");
            (bool success, ) = depositAccount.call{value: cost}("");
            require(success, "Native token transfer failed");
        } else {
            // Handle ERC20 token
            IERC20(mint).safeTransferFrom(user, depositAccount, cost);
        }

        emit DepositEvent(
            user,
            mint,
            cost,
            orderId,
            command,
            extraInfo,
            maxIndex,
            index,
            block.timestamp
        );
    }

    // Two tokens deposit
    function depositTwoTokens(
        address user,
        address mint1,
        uint256 cost1,
        address mint2,
        uint256 cost2,
        string memory orderId,
        string memory command,
        string memory extraInfo,
        uint8 maxIndex,
        uint8 index
    ) external payable {
        require(cost1 > 0 && cost2 > 0, "Invalid costs");

        // Handle first token
        if (mint1 == nativeTokenAddress) {
            require(msg.value >= cost1, "Incorrect native token amount for mint1");
            (bool success, ) = depositAccount.call{value: cost1}("");
            require(success, "Native token transfer for mint1 failed");
        } else {
            IERC20(mint1).safeTransferFrom(user, depositAccount, cost1);
        }

        // Handle second token
        if (mint2 == nativeTokenAddress) {
            require(msg.value >= cost1 + cost2, "Incorrect native token amount for mint2");
            (bool success, ) = depositAccount.call{value: cost2}("");
            require(success, "Native token transfer for mint2 failed");
        } else {
            IERC20(mint2).safeTransferFrom(user, depositAccount, cost2);
        }

        emit DepositEvent2(
            user,
            mint1,
            cost1,
            mint2,
            cost2,
            orderId,
            command,
            extraInfo,
            maxIndex,
            index,
            block.timestamp
        );
    }

    // Set deposit account
    function setDepositAccount(address _depositAccount) external onlyOwner {
        depositAccount = _depositAccount;
    }

    // Set native token address
    function setNativeTokenAddress(address _nativeTokenAddress) external onlyOwner {
        nativeTokenAddress = _nativeTokenAddress;
    }
}
