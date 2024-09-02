// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BSCManager is Ownable {
    using SafeERC20 for IERC20;

    event TokensTransferred(address indexed token, address indexed to, uint256 amount);
    event TokensMinted(address indexed token, address indexed to, uint256 amount);
    event TokensBurned(address indexed token, uint256 amount);

    // 构造函数，初始化合约所有者
    constructor(address initialOwner) Ownable(initialOwner) {
        
    }

    // 转移代币
    function transferTokens(address token, address to, uint256 amount) public onlyOwner {
        require(token != address(0), "Invalid token address");
        require(to != address(0), "Invalid recipient address");

        IERC20(token).safeTransfer(to, amount);
        emit TokensTransferred(token, to, amount);
    }

    // 铸造新的代币（假设合约有铸造权限）
    function mintTokens(address token, address to, uint256 amount) public onlyOwner {
        require(token != address(0), "Invalid token address");
        require(to != address(0), "Invalid recipient address");

        // 假设代币合约有 mint 功能，可以通过继承 ERC20Mintable 实现
        IERC20Mintable(token).mint(to, amount);
        emit TokensMinted(token, to, amount);
    }

    // 销毁代币（假设合约有销毁权限）
    function burnTokens(address token, uint256 amount) public onlyOwner {
        require(token != address(0), "Invalid token address");

        IERC20Burnable(token).burn(amount);
        emit TokensBurned(token, amount);
    }
}

// 下面是两个接口的定义，用于铸造和销毁功能
interface IERC20Mintable is IERC20 {
    function mint(address to, uint256 amount) external;
}

interface IERC20Burnable is IERC20 {
    function burn(uint256 amount) external;
}
