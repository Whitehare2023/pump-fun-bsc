// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./openzeppelin-contracts/contracts/access/Ownable.sol";
import "./openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract TokenOperations is Ownable {
    address public depositAccount;
    address public factory; // TokenFactory 合约地址
    bool private factorySet = false; // 确保 factory 只能设置一次

    // 代币地址
    address public WBNB_ADDRESS; 
    address public USDT_ADDRESS;
    address public USDC_ADDRESS;
    address public BUSD_ADDRESS;
    address public DAI_ADDRESS;

    bool private addressesSet = false; // 确保地址只能设置一次

    event Debug(string message, address addr);
    event DebugValue(string message, uint256 value);
    event PermitEvent(address indexed creator, address indexed baseToken, address indexed quoteToken, bool isLaunchPermitted, bool isOnPancake);
    event DepositEvent(address indexed user, address indexed mint, uint256 cost, string orderId, string command, string extraInfo, uint8 maxIndex, uint8 index, uint256 timestamp);
    event DepositEvent2Part1(address indexed user, address mint1, uint256 cost1, address mint2);
    event DepositEvent2Part2(uint256 cost2, string orderId, string command, string extraInfo, uint8 maxIndex, uint8 index, uint256 timestamp);
    event WithdrawEvent(address indexed quoteToken, address indexed baseToken, uint256 quoteAmount, uint256 baseAmount, uint256 timestamp, address receiver);
    event Withdraw2Event(address indexed systemAccount, address indexed receiverAccount, address indexed mint, uint256 cost, string orderId, uint256 timestamp);

    modifier onlyFactory() {
        require(msg.sender == factory, "Caller is not the factory");
        _;
    }

    constructor(address _depositAccount) Ownable(msg.sender) {
        depositAccount = _depositAccount;
    }

    // 设置 factory 地址的函数，只能调用一次
    function setFactory(address _factory) external {
        require(!factorySet, "Factory already set"); // 确保 factory 只能被设置一次
        require(_factory != address(0), "Invalid factory address");
        factory = _factory;
        factorySet = true; // 设置 factory 已经设置
    }

    // 合并后的函数，用于设置所有代币地址，只能调用一次
    function setTokenAddresses(bool isTestnet) external {
        require(!addressesSet, "Token addresses already set"); // 确保代币地址只能被设置一次

        if (isTestnet) {
            // 测试网地址
            WBNB_ADDRESS = 0x0dE8FCAE8421fc79B29adE9ffF97854a424Cad09; // WBNB Testnet
            USDT_ADDRESS = 0x7ef95A0fEab5e1dA0041a2FD6B44cF59FFbEEf2B; // USDT Testnet
            USDC_ADDRESS = 0x64544969ed7EBf5f083679233325356EbE738930; // USDC Testnet
            BUSD_ADDRESS = 0x78867BbEeF44f2326bF8DDd1941a4439382EF2A7; // BUSD Testnet
            DAI_ADDRESS = 0x8a9424745056Eb399FD19a0EC26A14316684e274; // DAI Testnet
        } else {
            // 主网地址
            WBNB_ADDRESS = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // WBNB Mainnet
            USDT_ADDRESS = 0x55d398326f99059fF775485246999027B3197955; // USDT Mainnet
            USDC_ADDRESS = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d; // USDC Mainnet
            BUSD_ADDRESS = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56; // BUSD Mainnet
            DAI_ADDRESS = 0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3; // DAI Mainnet
        }

        addressesSet = true; // 设置代币地址已被设置
    }

    // Deposit 功能
    function deposit(
        string calldata orderId,
        string calldata command,
        string calldata extraInfo,
        uint8 maxIndex,
        uint8 index,
        uint256 cost,
        address mint
    ) external payable onlyFactory { 
        require(cost > 0, "Invalid parameters");

        if (mint == WBNB_ADDRESS) {
            require(msg.value == cost, "Incorrect BNB amount sent");
            (bool success, ) = payable(depositAccount).call{value: cost}("");
            require(success, "Transfer failed");
        } else {
            require(IERC20(mint).transferFrom(msg.sender, depositAccount, cost), "Transfer failed");
        }

        emit DepositEvent(msg.sender, mint, cost, orderId, command, extraInfo, maxIndex, index, block.timestamp);
    }

    struct DepositParams {
        string orderId;
        string command;
        string extraInfo;
        uint8 maxIndex;
        uint8 index;
        uint256 cost1;
        uint256 cost2;
        address mint1;
        address mint2;
    }

    function deposit2(DepositParams calldata params) external payable onlyFactory { 
        require(params.cost1 > 0 && params.cost2 > 0, "Invalid parameters");
        require(params.mint1 != address(0) && params.mint2 != address(0), "Invalid mint addresses");

        if (params.mint1 == WBNB_ADDRESS) {
            require(msg.value == params.cost1, "Incorrect BNB amount sent");
            (bool success, ) = payable(depositAccount).call{value: params.cost1}("");
            require(success, "Transfer failed");
        } else {
            require(IERC20(params.mint1).transferFrom(msg.sender, depositAccount, params.cost1), "Transfer failed");
        }

        if (params.mint2 == WBNB_ADDRESS) {
            require(msg.value == params.cost2, "Incorrect BNB amount sent");
            (bool success, ) = payable(depositAccount).call{value: params.cost2}("");
            require(success, "Transfer failed");
        } else {
            require(IERC20(params.mint2).transferFrom(msg.sender, depositAccount, params.cost2), "Transfer failed");
        }

        emit DepositEvent2Part1(msg.sender, params.mint1, params.cost1, params.mint2);
        emit DepositEvent2Part2(params.cost2, params.orderId, params.command, params.extraInfo, params.maxIndex, params.index, block.timestamp);
    }

    // Withdraw 功能
    function withdraw(
        address baseToken,
        address quoteToken,
        uint256 quoteAmount,
        uint256 baseAmount,
        address payable receiver
    ) external onlyFactory {
        require(baseToken != address(0) && quoteToken != address(0), "Invalid token addresses");
        require(receiver != address(0), "Invalid receiver address");

        if (quoteToken == WBNB_ADDRESS) {
            (bool success, ) = WBNB_ADDRESS.call(abi.encodeWithSignature("withdraw(uint256)", quoteAmount));
            require(success, "WBNB withdraw failed");
            (success, ) = receiver.call{value: quoteAmount}("");
            require(success, "Transfer failed");
        } else {
            require(IERC20(quoteToken).transfer(receiver, quoteAmount), "Transfer failed");
        }

        require(IERC20(baseToken).transfer(receiver, baseAmount), "Transfer failed");

        emit WithdrawEvent(quoteToken, baseToken, quoteAmount, baseAmount, block.timestamp, receiver);
    }

    function withdraw2(
        string calldata orderId,
        uint256 cost,
        address mint,
        address payable receiver
    ) external onlyFactory { 
        require(mint != address(0), "Invalid token address");
        require(receiver != address(0), "Invalid receiver address");

        if (mint == WBNB_ADDRESS) {
            (bool success, ) = WBNB_ADDRESS.call(abi.encodeWithSignature("withdraw(uint256)", cost));
            require(success, "WBNB withdraw failed");
            (success, ) = receiver.call{value: cost}("");
            require(success, "Transfer failed");
        } else {
            require(IERC20(mint).transfer(receiver, cost), "Transfer failed");
        }

        emit Withdraw2Event(msg.sender, receiver, mint, cost, orderId, block.timestamp);
    }
}
