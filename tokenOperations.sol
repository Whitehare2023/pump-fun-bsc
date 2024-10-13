// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./customToken.sol"; // 引入 CustomToken 合约
import "./add_quote_token.sol"; // 引入 QuoteTokenManager 合约
import "./state.sol";
import "./initialize_config.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";  // 引入 PRBMathUD60x18 库
import "./Calculations.sol";

contract TokenOperations is ReentrancyGuard {
    using SafeERC20 for IERC20;

    Calculations public calculations;  // 引入 Calculations 合约实例
    QuoteTokenManager public quoteTokenManager; // 引入 QuoteTokenManager 实例
    InitializeConfig public initializeConfig;  // 添加 initializeConfig 实例

    address public factory; // TokenFactory 合约地址
    bool private factorySet = false; // 确保 factory 只能设置一次

    // 定义 PancakeSwap 地址
    address public pancakeAddress;

    // 代币地址，默认初始化为测试网地址
    address public WBNB_ADDRESS;

    mapping(address => CurveInfo) public curves;

    // 自定义修饰符，确保只有 factory 地址能调用
    modifier onlyFactory() {
        require(msg.sender == factory, "Caller is not the factory");
        _;
    }

    // 返回 CurveInfo
    function getCurveInfo(address baseToken) external view returns (CurveInfo memory) {
        return curves[baseToken];
    }

    function getDepositAccount() public view returns(address _depositAccount) {
        _depositAccount = initializeConfig.depositAccount();
        return _depositAccount;
    }

    // 在构造函数中初始化 isTestnet，并调用 setTokenAddresses 和初始化 QuoteTokenManager
    constructor(address _quoteTokenManager, address _initializeConfig) {
        quoteTokenManager = QuoteTokenManager(_quoteTokenManager); // 初始化 quoteTokenManager
        initializeConfig = InitializeConfig(_initializeConfig);
    }

    // 设置 factory 地址，只能设置一次
    function setFactory(address _factory) external {
        require(!factorySet, "Factory already set"); // 确保只设置一次
        require(_factory != address(0), "Factory address is invalid");
        factory = _factory;
        factorySet = true; // 设置 factory 已经设置
    }

    // 初始化函数，用于设置 TokenOperations 的必要地址
    function initialize(
        address _quoteTokenManager,        // 传入 quoteTokenManager 的地址
        address _initializeConfig,         // 传入 initializeConfig 的地址
        address _pancakeAddress,           // pancakeAddress
        address _WBNB_ADDRESS,              // WBNB_ADDRESS
        address _calculations
    ) external onlyFactory {
        quoteTokenManager = QuoteTokenManager(_quoteTokenManager);
        initializeConfig = InitializeConfig(_initializeConfig);
        pancakeAddress = _pancakeAddress;
        WBNB_ADDRESS = _WBNB_ADDRESS;
        calculations = Calculations(_calculations);
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
            currentQuoteReserves: 0,
            currentBaseReserves: 0,
            feeBps: feeBps,
            target: target,
            creator: creator,
            isLaunchPermitted: isLaunchPermitted,
            isOnPancake: false
        });
    }

    function permit(address baseToken, address userAddress) external onlyFactory {
        CurveInfo storage curve = curves[baseToken];
        require(curve.baseToken != address(0), "Curve does not exist for the provided baseToken");
        require(userAddress == curve.creator, "Caller is not the creator of the bonding curve");
        require(!curve.isOnPancake, "Invalid parameters");

        curve.isLaunchPermitted = !curve.isLaunchPermitted;

        if (curve.isLaunchPermitted && curve.currentQuoteReserves >= curve.target) {
            curve.isOnPancake = true;
        }
    }

    function buyToken(
        address baseToken, 
        uint256 quoteAmount, 
        uint256 minBaseAmount, 
        address userAddress
    ) external payable onlyFactory nonReentrant {
        CurveInfo storage curve = curves[baseToken];
        require(userAddress == curve.creator, "Caller is not the creator of the bonding curve");
        require(!curve.isOnPancake, "Liquidity already on PancakeSwap");

        // 获取 quoteToken 和 baseToken 的精度
        uint8 quoteTokenDecimals = uint8(quoteTokenManager.getQuoteTokenDecimals(curve.quoteToken));
        uint8 baseTokenDecimals = CustomToken(baseToken).decimals();

        uint256 adjustedQuoteAmount = quoteAmount;
        uint256 adjustedFeeAmount = 0;
        uint256 refundAmount = 0;
        uint256 newQuoteAmount = 0;

        if (curve.quoteToken == WBNB_ADDRESS) {
            require(msg.value == quoteAmount, "Incorrect BNB amount sent");
            // 暂时不转换为 WBNB，先处理调整和退款
        } else {
            uint256 allowance = IERC20(curve.quoteToken).allowance(userAddress, address(this));
            require(allowance >= quoteAmount, "Insufficient allowance");
            require(IERC20(curve.quoteToken).transferFrom(userAddress, address(this), quoteAmount), "Transfer failed");
        }

        // 计算手续费和扣除手续费后的金额
        uint256 feeAmount = (quoteAmount * curve.feeBps) / 10000;
        newQuoteAmount = quoteAmount - feeAmount;

        // 检查是否已达到发射目标，如果接近目标，调整购买量
        if (curve.isLaunchPermitted && curve.currentQuoteReserves + newQuoteAmount > curve.target) {
            // 计算剩余的可购买额度
            uint256 remainingAmount = curve.target - curve.currentQuoteReserves;

            // 计算调整后的 quoteAmount，使得扣除手续费后的金额等于 remainingAmount
            uint256 feeRate = curve.feeBps;
            adjustedQuoteAmount = (remainingAmount * 10000) / (10000 - feeRate);

            // 计算调整后的手续费
            adjustedFeeAmount = adjustedQuoteAmount - remainingAmount;

            // 确保调整后的购买金额不超过用户最初想支付的金额
            require(adjustedQuoteAmount <= quoteAmount, "Adjusted quote amount exceeds initial quote amount");

            // 计算需要退款的金额
            refundAmount = quoteAmount - adjustedQuoteAmount;

            // 更新变量
            feeAmount = adjustedFeeAmount;
            newQuoteAmount = remainingAmount;
            quoteAmount = adjustedQuoteAmount; // 更新 quoteAmount 为调整后的金额

            curve.isOnPancake = true;  // 达到目标后上线 PancakeSwap
        } else {
            // 如果没有调整，使用原始的 feeAmount 和 newQuoteAmount
            adjustedFeeAmount = feeAmount;
            newQuoteAmount = quoteAmount - feeAmount;
        }

        // 退款多余的部分给用户
        if (refundAmount > 0) {
            if (curve.quoteToken == WBNB_ADDRESS) {
                // 退款 BNB 给用户
                (bool refundSuccess, ) = userAddress.call{value: refundAmount}("");
                require(refundSuccess, "Refund failed");
            } else {
                // 退款代币给用户
                require(IERC20(curve.quoteToken).transfer(userAddress, refundAmount), "Refund failed");
            }
        }

        // **现在** 处理手续费和转换 WBNB
        if (curve.quoteToken == WBNB_ADDRESS) {
            // 将手续费部分的 BNB 转给 feeRecipientAccount
            (bool feeTransferSuccess, ) = initializeConfig.feeRecipientAccount().call{value: feeAmount}("");
            require(feeTransferSuccess, "Fee transfer failed");

            // 将剩余的 newQuoteAmount 转换为 WBNB
            (bool success, ) = WBNB_ADDRESS.call{value: newQuoteAmount}(abi.encodeWithSignature("deposit()"));
            require(success, "WBNB deposit failed");
        } else {
            // 非 WBNB 的情况下，转移手续费
            require(IERC20(curve.quoteToken).transfer(initializeConfig.feeRecipientAccount(), feeAmount), "Fee transfer failed");
        }

        // 计算购买的 baseToken 数量，使用扣除手续费后的 newQuoteAmount 进行计算
        uint256 baseAmount = calculations.calculateTokensBought(
            curve.initVirtualQuoteReserves,
            curve.initVirtualBaseReserves,
            curve.currentBaseReserves,
            curve.currentQuoteReserves,
            newQuoteAmount,
            quoteTokenDecimals,
            baseTokenDecimals
        );

        require(baseAmount >= minBaseAmount, "Slippage too high, minBaseAmount not met");

        // 从 bondingCurveBase 转移 baseToken 给用户
        require(IERC20(baseToken).transfer(userAddress, baseAmount), "Base token transfer failed");

        // 更新储备
        curve.currentQuoteReserves += newQuoteAmount;
        curve.currentBaseReserves += baseAmount;
    }

    function sellToken(
        address baseToken, 
        uint256 baseAmount, 
        address userAddress
    ) external onlyFactory nonReentrant payable {
        CurveInfo storage curve = curves[baseToken];
        require(!curve.isOnPancake, "Liquidity already on PancakeSwap");
        require(curve.currentBaseReserves >= baseAmount, "Not enough base reserves");

        // 获取 quoteToken 和 baseToken 的精度
        uint8 quoteTokenDecimals = uint8(quoteTokenManager.getQuoteTokenDecimals(curve.quoteToken));
        uint8 baseTokenDecimals = CustomToken(baseToken).decimals();

        // 调用计算函数来计算获得的 quoteAmount
        uint256 quoteAmount = calculations.calculateTokensSold(
            curve.initVirtualQuoteReserves,
            curve.initVirtualBaseReserves,
            curve.currentBaseReserves,
            curve.currentQuoteReserves,
            baseAmount, // 使用原始的 baseAmount
            quoteTokenDecimals,
            baseTokenDecimals
        );

        // 计算手续费
        uint256 feeAmount = (quoteAmount * curve.feeBps) / 10000;
        uint256 newQuoteAmount = quoteAmount - feeAmount;

        require(newQuoteAmount > 0, "Invalid quote amount calculated");

        // 用户将 baseToken 转回合约
        require(IERC20(baseToken).transferFrom(userAddress, address(this), baseAmount), "Base token transfer failed");

        if (curve.quoteToken == WBNB_ADDRESS) {
            // 检查合约的 WBNB 余额是否足够
            uint256 contractWbnbBalance = IERC20(WBNB_ADDRESS).balanceOf(address(this));
            require(contractWbnbBalance >= quoteAmount, "Insufficient WBNB balance in contract");

            // 调用 withdraw，将 WBNB 转换为 BNB
            (bool successWithdraw, bytes memory returnData) = WBNB_ADDRESS.call(abi.encodeWithSignature("withdraw(uint256)", quoteAmount));
            require(successWithdraw, string(abi.encodePacked("WBNB withdraw failed: ", returnData)));

            // 确保合约能够接收 BNB，需要实现 receive() 函数
            // 将 BNB 分别转给用户和手续费接收者
            // 由于 withdraw 后，合约收到 quoteAmount 的 BNB
            // 将扣除手续费后的 BNB 转给用户
            (bool successUser, ) = userAddress.call{value: newQuoteAmount}("");
            require(successUser, "Transfer to user failed");

            // 将手续费部分的 BNB 转给 feeRecipientAccount
            (bool successFee, ) = initializeConfig.feeRecipientAccount().call{value: feeAmount}("");
            require(successFee, "Fee transfer failed");
        } else {
            // 非 WBNB 的 quoteToken 转移
            require(IERC20(curve.quoteToken).transfer(userAddress, newQuoteAmount), "Transfer to user failed");
            require(IERC20(curve.quoteToken).transfer(initializeConfig.feeRecipientAccount(), feeAmount), "Fee transfer failed");
        }

        // 更新储备
        curve.currentQuoteReserves -= quoteAmount;
        curve.currentBaseReserves -= baseAmount;
    }

    // 需要在合约中添加 receive() 函数，以便接收 BNB
    receive() external payable {}

    // Deposit 功能
    function deposit(
        uint256 cost,
        address token,
        address userAddress
    ) external payable onlyFactory nonReentrant { 
        require(cost > 0, "Invalid parameters");

        // 判断是否是原生 BNB 还是 ERC20 代币
        if (msg.value > 0) {
            // 用户存的是原生 BNB
            require(token == address(0), "Token address must be zero for BNB");
            require(msg.value == cost, "Incorrect BNB amount sent");

            // 直接将 BNB 转移到存款账户
            (bool success, ) = payable(getDepositAccount()).call{value: cost}("");
            require(success, "BNB transfer failed");

        } else {
            // 用户存的是 ERC20 代币，确保 token 地址有效
            require(token != address(0), "Invalid token address");

            // 执行 ERC20 代币的 transferFrom 操作，将资金从用户转移到存款账户
            require(IERC20(token).transferFrom(userAddress, getDepositAccount(), cost), "ERC20 transfer failed");
        }
    }

    // Deposit 功能
    function deposit2(
        uint256 cost1,        // 第一个代币的存款金额
        uint256 cost2,        // 第二个代币的存款金额
        address mint1,        // 第一个代币的地址
        address mint2,        // 第二个代币的地址
        address userAddress   // 用户的地址
    ) external payable onlyFactory nonReentrant { 
        require(cost1 > 0 && cost2 > 0, "Invalid parameters");
        require(mint1 != address(0) && mint2 != address(0), "Invalid mint addresses");

        // 处理第一个代币的存款
        if (mint1 == WBNB_ADDRESS) {
            require(msg.value == cost1, "Incorrect BNB amount sent");
            (bool success, ) = payable(getDepositAccount()).call{value: cost1}("");
            require(success, "Transfer failed");
        } else {
            // 执行 ERC20 代币的 transferFrom 操作
            require(IERC20(mint1).transferFrom(userAddress, getDepositAccount(), cost1), "Transfer failed");
        }

        // 处理第二个代币的存款
        if (mint2 == WBNB_ADDRESS) {
            require(msg.value == cost2, "Incorrect BNB amount sent");
            (bool success, ) = payable(getDepositAccount()).call{value: cost2}("");
            require(success, "Transfer failed");
        } else {
            // 执行 ERC20 代币的 transferFrom 操作
            require(IERC20(mint2).transferFrom(userAddress, getDepositAccount(), cost2), "Transfer failed");
        }

    }

    // Withdraw 功能
    function withdraw(
        address baseToken,
        address payable receiver
    ) external onlyFactory nonReentrant {
        require(baseToken != address(0), "Invalid base token address");
        require(receiver != address(0), "Invalid receiver address");

        CurveInfo storage curve = curves[baseToken];
        require(curve.isOnPancake, "Liquidity is not on PancakeSwap");

        // 获取池子里的所有 QuoteToken 和 BaseToken
        uint256 quoteBalance = IERC20(curve.quoteToken).balanceOf(address(this));
        uint256 baseBalance = IERC20(baseToken).balanceOf(address(this));

        // 处理 QuoteToken 的提取
        if (curve.quoteToken == WBNB_ADDRESS) {
            // 如果是 WBNB，先执行 WBNB 的提现
            (bool success, ) = WBNB_ADDRESS.call(abi.encodeWithSignature("withdraw(uint256)", quoteBalance));
            require(success, "WBNB withdraw failed");
            // 将提取后的 BNB 转给接收者
            (success, ) = receiver.call{value: quoteBalance}("");
            require(success, "Transfer failed");
        } else {
            // 直接转移 quoteToken 给接收者
            require(IERC20(curve.quoteToken).transfer(receiver, quoteBalance), "Quote token transfer failed");
        }

        // 处理 BaseToken 的提取
        require(IERC20(baseToken).transfer(receiver, baseBalance), "Base token transfer failed");

        // 清空池子的储备
        curve.currentQuoteReserves = 0;
        curve.currentBaseReserves = 0;

        // 将池子的 baseToken 和 quoteToken 地址设置为 address(0)，标记为关闭
        curve.baseToken = address(0);
        curve.quoteToken = address(0);

    }

    function withdraw2(
        uint256 cost,
        address token,  
        address payable receiver
    ) external onlyFactory nonReentrant { 
        require(token != address(0), "Invalid token address");
        require(receiver != address(0), "Invalid receiver address");

        if (token == WBNB_ADDRESS) {
            // 如果是 WBNB，提取 WBNB 转为 BNB，并转给接收者
            (bool success, ) = WBNB_ADDRESS.call(abi.encodeWithSignature("withdraw(uint256)", cost));
            require(success, "WBNB withdraw failed");
            (success, ) = receiver.call{value: cost}("");
            require(success, "Transfer failed");
        } else {
            // 如果是 ERC20 代币，则直接转账
            require(IERC20(token).transfer(receiver, cost), "Transfer failed");
        }
    }
}