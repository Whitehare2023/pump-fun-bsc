// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./openzeppelin-contracts/contracts/access/Ownable.sol";
import "./openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "./state.sol";  // 包含 CurveInfo 结构体定义和事件声明
import "./customToken1.sol";  // 包含代币逻辑

contract Withdraw is Ownable {
    // 构造函数，传递初始所有者地址到 Ownable 合约
    constructor(address _initialOwner) Ownable(_initialOwner) {}

    struct CurveInfo {
        uint256 initVirtualQuoteReserves;
        uint256 initVirtualBaseReserves;
        uint256 currentQuoteReserves;
        uint256 currentBaseReserves;
        bool isOnPancake;
        uint256 quoteBalance;
        uint256 baseSupply;
        address creator;
        uint256 target;
        uint256 feeBps;
    }

    // 将所有曲线信息存储在一个映射中，使用代币地址作为键
    mapping(address => CurveInfo) public curves;

    address public platformAddress;

    function withdraw(
        address quoteToken,
        address baseToken,
        address receiver
    ) external onlyOwner {
        CurveInfo storage curve = curves[baseToken];
        require(curve.isOnPancake == true, "Curve is still on bonding curve");

        uint256 quoteAmount = curve.currentQuoteReserves;
        uint256 baseAmount = curve.currentBaseReserves;

        // 转移所有报价代币到接收者
        require(IERC20(quoteToken).transfer(receiver, quoteAmount), "Transfer quote token failed");
        
        // 转移所有基础代币到接收者
        CustomToken(baseToken).transfer(receiver, baseAmount);

        // 清空曲线数据
        curve.currentQuoteReserves = 0;
        curve.currentBaseReserves = 0;

        // 触发事件（事件声明已在 state.sol 中）
        emit WithdrawEvent(quoteToken, baseToken, quoteAmount, baseAmount, block.timestamp, receiver);
    }

    function withdraw2(
        address token,
        address receiverAccount,
        uint256 amount,
        string memory orderId
    ) external onlyOwner {
        address systemAccount = msg.sender;

        if (token == address(0)) {
            // Transfer BNB/ETH
            (bool success, ) = payable(receiverAccount).call{value: amount}("");
            require(success, "Transfer BNB/ETH failed");
        } else {
            // Transfer ERC20 Token
            require(IERC20(token).transfer(receiverAccount, amount), "Transfer ERC20 token failed");
        }

        // 触发事件（事件声明已在 state.sol 中）
        emit Withdraw2Event(systemAccount, receiverAccount, token, amount, orderId, block.timestamp);
    }

    // 添加必要的函数来设置和管理曲线信息
    function setCurveInfo(
        address baseToken,
        uint256 initVirtualQuoteReserves,
        uint256 initVirtualBaseReserves,
        uint256 currentQuoteReserves,
        uint256 currentBaseReserves,
        bool isOnPancake,
        uint256 quoteBalance,
        uint256 baseSupply,
        address creator,
        uint256 target,
        uint256 feeBps
    ) external onlyOwner {
        curves[baseToken] = CurveInfo({
            initVirtualQuoteReserves: initVirtualQuoteReserves,
            initVirtualBaseReserves: initVirtualBaseReserves,
            currentQuoteReserves: currentQuoteReserves,
            currentBaseReserves: currentBaseReserves,
            isOnPancake: isOnPancake,
            quoteBalance: quoteBalance,
            baseSupply: baseSupply,
            creator: creator,
            target: target,
            feeBps: feeBps
        });
    }

    function updatePlatformAddress(address _platformAddress) external onlyOwner {
        platformAddress = _platformAddress;
    }
    
    // 接受合约接收的原生代币
    receive() external payable {}
}
