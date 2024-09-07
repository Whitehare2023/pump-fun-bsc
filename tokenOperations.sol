// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./openzeppelin-contracts/contracts/access/Ownable.sol";
import "./openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./formula.sol";  // 引入 PumpFormula 合约
import "./customToken1.sol"; // 引入 CustomToken 合约
import "./state.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";  // 引入 PRBMathUD60x18 库

contract TokenOperations is Ownable {

    address public depositAccount;
    address public factory; // TokenFactory 合约地址
    bool private factorySet = false; // 确保 factory 只能设置一次

    // 定义 PancakeSwap 地址
    address public pancakeAddress = 0x9Ac64Cc6e4415144c455Bd8E483E3Bb5CE9E4F84;
    
    // PumpFormula 合约地址
    address public pumpFormula;

    // 代币地址，默认初始化为测试网地址
    address public WBNB_ADDRESS = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;
    address public USDT_ADDRESS = 0x7ef95A0fEab5e1dA0041a2FD6B44cF59FFbEEf2B;
    address public USDC_ADDRESS = 0x64544969ed7EBf5f083679233325356EbE738930;
    address public BUSD_ADDRESS = 0x78867BbEeF44f2326bF8DDd1941a4439382EF2A7;
    address public DAI_ADDRESS = 0x8a9424745056Eb399FD19a0EC26A14316684e274;

    bool private addressesSet = false; // 确保地址只能设置一次

    mapping(address => CurveInfo) public curves; // 将 curves 迁移到 TokenOperations

    event Debug(string message, address addr);
    event DebugValue(string message, uint256 value);
    event PermitEvent(address indexed creator, address indexed baseToken, address indexed quoteToken, bool isLaunchPermitted, bool isOnPancake);
    event DepositEvent(address indexed user, address indexed mint, uint256 cost, string orderId, string command, string extraInfo, uint8 maxIndex, uint8 index, uint256 timestamp);
    event WithdrawEvent(address indexed quoteToken, address indexed baseToken, uint256 quoteAmount, uint256 baseAmount, uint256 timestamp, address receiver);
    event TokenPurchased(address indexed buyer, address baseToken, uint256 quoteAmount, uint256 baseAmount, uint256 currentQuoteReserves, uint256 currentBaseReserves, uint256 timestamp);
    event TokenSold(address indexed seller, address baseToken, uint256 baseAmount, uint256 quoteAmount);

    // 自定义修饰符，确保只有 factory 地址能调用
    modifier onlyFactory() {
        require(msg.sender == factory, "Caller is not the factory");
        _;
    }

    // 返回 CurveInfo
    function getCurveInfo(address baseToken) external view returns (CurveInfo memory) {
        return curves[baseToken];
    }

    // 设置 factory 和 factoryOwner 的地址
    function setFactory(address _factory) external {
        require(!factorySet, "Factory already set"); // 确保只设置一次
        require(_factory != address(0), "Factory address is invalid");
        factory = _factory;
        factorySet = true; // 设置 factory 已经设置
    }

    // 在构造函数中初始化 isTestnet，并调用 setTokenAddresses
    constructor(address _depositAccount, address _pumpFormula, bool isTestnet) Ownable(msg.sender) {
        depositAccount = _depositAccount;
        pumpFormula = _pumpFormula;
        setTokenAddresses(isTestnet); // 构造时立即设置代币地址
    }

    function setTokenAddresses(bool isTestnet) internal {
        if (!isTestnet) {
            // 如果是主网，使用主网地址
            WBNB_ADDRESS = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // WBNB Mainnet
            USDT_ADDRESS = 0x55d398326f99059fF775485246999027B3197955; // USDT Mainnet
            USDC_ADDRESS = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d; // USDC Mainnet
            BUSD_ADDRESS = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56; // BUSD Mainnet
            DAI_ADDRESS = 0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3; // DAI Mainnet
            pancakeAddress = 0x10ED43C718714eb63d5aA57B78B54704E256024E; // PancakeSwap Router Mainnet
        }
        addressesSet = true; // 设置代币地址已被设置
    }

    function initializeCurve(
        address baseToken,
        address quoteToken,
        uint256 initVirtualQuoteReserves,
        uint256 initVirtualBaseReserves,
        uint256 target,
        address creator,
        uint256 feeBps,
        bool isLaunchPermitted
    ) external onlyFactory {
        curves[baseToken] = CurveInfo({
            baseToken: baseToken,
            quoteToken: quoteToken,
            initVirtualQuoteReserves: initVirtualQuoteReserves,
            initVirtualBaseReserves: initVirtualBaseReserves,
            currentQuoteReserves: initVirtualQuoteReserves,
            currentBaseReserves: initVirtualBaseReserves,
            feeBps: feeBps,
            target: target,
            creator: creator,
            isLaunchPermitted: isLaunchPermitted,
            isOnPancake: false
        });
    }

    function permit(address baseToken) external onlyFactory {
        CurveInfo storage curve = curves[baseToken];
        require(curve.baseToken != address(0), "Curve does not exist for the provided baseToken");
        require(owner() == curve.creator, "Caller is not the creator of the bonding curve");
        require(!curve.isOnPancake, "Invalid parameters");

        curve.isLaunchPermitted = !curve.isLaunchPermitted;

        if (curve.isLaunchPermitted && curve.currentQuoteReserves >= curve.target) {
            curve.isOnPancake = true;
        }

        emit PermitEvent(msg.sender, baseToken, curve.quoteToken, curve.isLaunchPermitted, curve.isOnPancake);
    }

    function buyToken(address baseToken, uint256 quoteAmount, uint256 minBaseAmount) external payable onlyFactory {
        CurveInfo storage curve = curves[baseToken];
        require(owner() == curve.creator, "Caller is not the creator of the bonding curve");
        require(!curve.isOnPancake, "Liquidity already on PancakeSwap");
        require(curve.isLaunchPermitted, "Token launch is not permitted");

        // 如果使用 WBNB 作为报价代币，进行 WBNB 转换
        if (curve.quoteToken == WBNB_ADDRESS) {
            require(msg.value == quoteAmount, "Incorrect BNB amount sent");
            (bool success, ) = WBNB_ADDRESS.call{value: quoteAmount}(abi.encodeWithSignature("deposit()"));
            require(success, "WBNB deposit failed");
        } else {
            require(IERC20(curve.quoteToken).transferFrom(msg.sender, address(this), quoteAmount), "Transfer failed");
        }

        // 使用 PRBMathUD60x18 进行安全计算
        UD60x18 currentQuoteReserves = ud(curve.currentQuoteReserves);
        UD60x18 newQuoteAmount = ud(quoteAmount);
        curve.currentQuoteReserves = currentQuoteReserves.add(newQuoteAmount).unwrap();

        // 计算手续费
        UD60x18 feeBps = ud(curve.feeBps);
        UD60x18 feeRate = feeBps.div(ud(10000));
        UD60x18 feeQuoteAmount = newQuoteAmount.mul(feeRate);
        UD60x18 swapQuoteAmount = newQuoteAmount.sub(feeQuoteAmount);

        // 如果达到了目标的处理
        UD60x18 targetAmount = ud(curve.target); // 将 curve.target 转换为 UD60x18

        if (currentQuoteReserves.add(newQuoteAmount).sub(targetAmount).unwrap() > 0) {
            // 当前的储备量大于目标
            swapQuoteAmount = targetAmount.sub(currentQuoteReserves); // 计算新的交易金额
            feeQuoteAmount = swapQuoteAmount.mul(feeRate).div(ud(10000).sub(feeBps));
            curve.isOnPancake = true; // 设置状态为上线 PancakeSwap
        }

        // 使用 PumpFormula 进行基础代币数量的计算
        uint256 baseAmount = PumpFormula(pumpFormula).buy(curve.quoteToken, curve.currentBaseReserves, curve.currentQuoteReserves, quoteAmount);
        require(baseAmount >= minBaseAmount, "Slippage too high, minBaseAmount not met");

        // 使用 PRBMathUD60x18 安全计算更新 currentBaseReserves
        UD60x18 currentBaseReserves = ud(curve.currentBaseReserves);
        UD60x18 newBaseAmount = ud(baseAmount);
        curve.currentBaseReserves = currentBaseReserves.add(newBaseAmount).unwrap();

        // 铸造基础代币并分发给用户
        CustomToken(baseToken).mint(tx.origin, baseAmount);

        // 如果达到了目标并且尚未上线 PancakeSwap，则执行流动性添加
        if (curve.currentQuoteReserves >= curve.target && !curve.isOnPancake) {
            curve.isOnPancake = true;
            // 添加 PancakeSwap 流动性逻辑
        }

        // emit TokenPurchased(tx.origin, baseToken, quoteAmount, baseAmount, curve.currentQuoteReserves, curve.currentBaseReserves, block.timestamp);
    }

    function sellToken(address baseToken, uint256 baseAmount) external onlyFactory {
        CurveInfo storage curve = curves[baseToken];
        require(curve.isLaunchPermitted, "Token launch is not permitted");
        require(curve.currentBaseReserves >= baseAmount, "Not enough base reserves");

        // 使用 PRBMathUD60x18 安全计算更新 currentBaseReserves
        UD60x18 currentBaseReserves = ud(curve.currentBaseReserves);
        UD60x18 sellBaseAmount = ud(baseAmount);
        curve.currentBaseReserves = currentBaseReserves.sub(sellBaseAmount).unwrap();

        // 计算卖出时获得的报价代币数量
        uint256 quoteAmount = PumpFormula(pumpFormula).sell(curve.quoteToken, curve.currentBaseReserves, curve.currentQuoteReserves, baseAmount);
        require(quoteAmount > 0, "Invalid quote amount calculated");

        // 销毁基础代币
        CustomToken(baseToken).burnFrom(tx.origin, baseAmount);

        // 处理 WBNB 或其他报价代币的提款逻辑
        if (curve.quoteToken == WBNB_ADDRESS) {
            (bool success, ) = WBNB_ADDRESS.call(abi.encodeWithSignature("withdraw(uint256)", quoteAmount));
            require(success, "WBNB withdraw failed");
            (success, ) = payable(tx.origin).call{value: quoteAmount}("");
            require(success, "Transfer failed");
        } else {
            require(IERC20(curve.quoteToken).transfer(tx.origin, quoteAmount), "Transfer failed");
        }

        // 使用 PRBMathUD60x18 安全计算更新 currentQuoteReserves
        UD60x18 currentQuoteReserves = ud(curve.currentQuoteReserves);
        UD60x18 newQuoteAmount = ud(quoteAmount);
        curve.currentQuoteReserves = currentQuoteReserves.sub(newQuoteAmount).unwrap();

        emit TokenSold(tx.origin, baseToken, baseAmount, quoteAmount);
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
            require(IERC20(params.mint1).transferFrom(tx.origin, depositAccount, params.cost1), "Transfer failed");
        }

        if (params.mint2 == WBNB_ADDRESS) {
            require(msg.value == params.cost2, "Incorrect BNB amount sent");
            (bool success, ) = payable(depositAccount).call{value: params.cost2}("");
            require(success, "Transfer failed");
        } else {
            require(IERC20(params.mint2).transferFrom(tx.origin, depositAccount, params.cost2), "Transfer failed");
        }

        emit DepositEvent2Part1(tx.origin, params.mint1, params.cost1, params.mint2);
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

        emit Withdraw2Event(tx.origin, receiver, mint, cost, orderId, block.timestamp);
    }
}
