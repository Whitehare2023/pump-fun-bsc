// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./customToken.sol"; // 引入 CustomToken 合约
import "./add_quote_token.sol"; // 引入 QuoteTokenManager 合约
import "./state.sol";
import "./initialize_config.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";  // 引入 PRBMathUD60x18 库

contract TokenOperations {
    QuoteTokenManager public quoteTokenManager; // 引入 QuoteTokenManager 实例
    InitializeConfig public initializeConfig;  // 添加 initializeConfig 实例

    address public factory; // TokenFactory 合约地址
    bool private factorySet = false; // 确保 factory 只能设置一次

    // 定义 PancakeSwap 地址
    address public pancakeAddress = 0x9Ac64Cc6e4415144c455Bd8E483E3Bb5CE9E4F84;

    // 代币地址，默认初始化为测试网地址
    address public WBNB_ADDRESS = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;

    mapping(address => CurveInfo) public curves; // 将 curves 迁移到 TokenOperations

    // event Debug(string message, address addr);
    // event DebugValue(string message, uint256 value);
    // event PermitEvent(address indexed creator, address indexed baseToken, address indexed quoteToken, bool isLaunchPermitted, bool isOnPancake);
    // event DepositEvent(address indexed user, address indexed mint, uint256 cost, string orderId, string command, string extraInfo, uint8 maxIndex, uint8 index, uint256 timestamp);
    // event WithdrawEvent(address indexed quoteToken, address indexed baseToken, uint256 quoteAmount, uint256 baseAmount, uint256 timestamp, address receiver);
    // event TokenPurchased(address indexed buyer, address baseToken, uint256 quoteAmount, uint256 baseAmount, uint256 currentQuoteReserves, uint256 currentBaseReserves, uint256 timestamp);
    // event TokenSold(address indexed seller, address baseToken, uint256 baseAmount, uint256 quoteAmount);

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
        address _WBNB_ADDRESS              // WBNB_ADDRESS
    ) external onlyFactory {
        quoteTokenManager = QuoteTokenManager(_quoteTokenManager);
        initializeConfig = InitializeConfig(_initializeConfig);
        pancakeAddress = _pancakeAddress;
        WBNB_ADDRESS = _WBNB_ADDRESS;
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
    ) external payable onlyFactory {
        CurveInfo storage curve = curves[baseToken];
        require(userAddress == curve.creator, "Caller is not the creator of the bonding curve");
        require(!curve.isOnPancake, "Liquidity already on PancakeSwap");

        // 获取 quoteToken 和 baseToken 的精度
        uint8 quoteTokenDecimals = uint8(quoteTokenManager.getQuoteTokenDecimals(curve.quoteToken));
        uint8 baseTokenDecimals = CustomToken(baseToken).decimals();

        // 处理 WBNB 或其他 quoteToken 的转移
        if (curve.quoteToken == WBNB_ADDRESS) {
            require(msg.value == quoteAmount, "Incorrect BNB amount sent");
            (bool success, ) = WBNB_ADDRESS.call{value: quoteAmount}(abi.encodeWithSignature("deposit()"));
            require(success, "WBNB deposit failed");
        } else {
            uint256 allowance = IERC20(curve.quoteToken).allowance(userAddress, address(this));
            require(allowance >= quoteAmount, "Insufficient allowance");
            require(IERC20(curve.quoteToken).transferFrom(userAddress, address(this), quoteAmount), "Transfer failed");
        }

        // 计算手续费并更新 quoteAmount
        uint256 feeAmount = (quoteAmount * curve.feeBps) / 10000;
        uint256 newQuoteAmount = quoteAmount - feeAmount;

        // 将手续费转移到指定的 feeRecipientAccount
        require(IERC20(curve.quoteToken).transfer(initializeConfig.feeRecipientAccount(), feeAmount), "Fee transfer failed");

        // 计算购买的 baseToken 数量，使用新的逻辑
        uint256 baseAmount = calculateTokensBought(
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
        require(IERC20(baseToken).transferFrom(address(this), userAddress, baseAmount), "Base token transfer failed");

        // 更新储备
        curve.currentQuoteReserves += newQuoteAmount;
        curve.currentBaseReserves += baseAmount;

        // 检查是否达到 PancakeSwap 的上线条件
        if (curve.isLaunchPermitted && curve.currentQuoteReserves >= curve.target && !curve.isOnPancake) {
            curve.isOnPancake = true;
        }

        // 触发事件
        // emit TokenPurchased(userAddress, baseToken, newQuoteAmount, baseAmount, curve.currentQuoteReserves, curve.currentBaseReserves, block.timestamp);
    }

    // 新的 calculateTokensBought 函数逻辑
    function calculateTokensBought(
        uint256 initVirtualQuoteReserves,
        uint256 initVirtualBaseReserves,
        uint256 currentBaseSupply,
        uint256 currentQuoteBalance,
        uint256 buyQuoteAmount,
        uint8 quoteTokenDecimals,
        uint8 baseTokenDecimals
    ) internal pure returns (uint256) {
        // 动态调整精度因子，确保所有数值统一到 18 位小数精度
        uint256 scalingFactorQuote = 10**(18 - quoteTokenDecimals);  // 调整为 18 位精度
        uint256 scalingFactorBase = 10**(18 - baseTokenDecimals);    // 调整为 18 位精度

        // 计算 np 和 mPlusP
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

    // 分开的第一步：计算 np (n * p)
    function calculateNp(
        uint256 initVirtualBaseReserves,
        uint256 currentQuoteBalance,
        uint256 buyQuoteAmount,
        uint256 scalingFactorQuote,
        uint256 scalingFactorBase
    ) internal pure returns (uint256) {
        UD60x18 p = ud((currentQuoteBalance + buyQuoteAmount) * scalingFactorQuote);  // p
        UD60x18 n = ud(initVirtualBaseReserves * scalingFactorBase);  // n
        UD60x18 np = n.mul(p);  // n * p
        return np.unwrap();
    }

    // 分开的第二步：计算 mPlusP (m + p)
    function calculateMPlusP(
        uint256 initVirtualQuoteReserves,
        uint256 currentQuoteBalance,
        uint256 buyQuoteAmount,
        uint256 scalingFactorQuote
    ) internal pure returns (uint256) {
        UD60x18 m = ud(initVirtualQuoteReserves * scalingFactorQuote);  // m
        UD60x18 p = ud((currentQuoteBalance + buyQuoteAmount) * scalingFactorQuote);  // p
        UD60x18 mPlusP = m.add(p);  // m + p
        return mPlusP.unwrap();
    }

    // 分开的第三步：计算最终的 tokensBought
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
        return tokensBought.unwrap() / (10**(18 - baseTokenDecimals));  // 还原精度
    }

    function sellToken(
        address baseToken, 
        uint256 baseAmount, 
        address userAddress
    ) external onlyFactory {
        CurveInfo storage curve = curves[baseToken];
        require(!curve.isOnPancake, "Liquidity already on PancakeSwap");
        require(curve.currentBaseReserves >= baseAmount, "Not enough base reserves");

        // 获取 quoteToken 和 baseToken 的精度
        uint8 quoteTokenDecimals = uint8(quoteTokenManager.getQuoteTokenDecimals(curve.quoteToken));
        uint8 baseTokenDecimals = CustomToken(baseToken).decimals();

        // 调用拆分后的计算函数来计算获得的 quoteAmount
        uint256 quoteAmount = calculateTokensSold(
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

        // 将基础代币（baseToken）转回池子
        require(IERC20(baseToken).transferFrom(userAddress, address(this), baseAmount), "Base token transfer failed");

        // 处理 WBNB 或其他 quoteToken 的转移逻辑
        if (curve.quoteToken == WBNB_ADDRESS) {
            // 转移 netQuoteAmount 到用户账户
            (bool success, ) = WBNB_ADDRESS.call(abi.encodeWithSignature("withdraw(uint256)", newQuoteAmount));
            require(success, "WBNB withdraw failed");
            (success, ) = payable(userAddress).call{value: newQuoteAmount}("");
            require(success, "Transfer failed");

            // 转移手续费到 feeRecipientAccount
            (success, ) = WBNB_ADDRESS.call(abi.encodeWithSignature("withdraw(uint256)", feeAmount));
            require(success, "WBNB withdraw failed");
            (success, ) = payable(initializeConfig.feeRecipientAccount()).call{value: feeAmount}("");
            require(success, "Fee transfer failed");

        } else {
            // 非 WBNB 的 quoteToken 转移
            require(IERC20(curve.quoteToken).transfer(userAddress, newQuoteAmount), "Transfer failed");
            // 将手续费转移到 feeRecipientAccount
            require(IERC20(curve.quoteToken).transfer(initializeConfig.feeRecipientAccount(), feeAmount), "Fee transfer failed");
        }

        // 更新储备
        curve.currentQuoteReserves -= quoteAmount;
        curve.currentBaseReserves -= baseAmount;
    }

    function calculateTokensSold(
        uint256 initVirtualQuoteReserves,
        uint256 initVirtualBaseReserves,
        uint256 currentBaseSupply,
        uint256 currentQuoteBalance,
        uint256 sellBaseAmount,
        uint8 quoteTokenDecimals,
        uint8 baseTokenDecimals
    ) internal pure returns (uint256) {
        // 动态调整精度因子，确保所有数值统一到 18 位小数精度
        uint256 scalingFactorQuote = 10 ** (18 - quoteTokenDecimals);  // 调整为 18 位精度
        uint256 scalingFactorBase = 10 ** (18 - baseTokenDecimals);    // 调整为 18 位精度

        // 计算 k、m、n 以及最终的 quoteAmount
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

    // Deposit 功能
    function deposit(
        uint256 cost,
        address token,
        address userAddress
    ) external payable onlyFactory { 
        require(cost > 0, "Invalid parameters");

        // 判断是否是原生 BNB 还是 ERC20 代币
        if (msg.value > 0) {
            // 用户存的是原生 BNB
            require(token == address(0), "Token address must be zero for BNB");
            require(msg.value == cost, "Incorrect BNB amount sent");

            // 直接将 BNB 转移到存款账户
            (bool success, ) = payable(getDepositAccount()).call{value: cost}("");
            require(success, "BNB transfer failed");

            // emit DepositEvent(userAddress, address(0), cost, "OrderID", "Deposit", "ExtraInfo", 1, 1, block.timestamp);

        } else {
            // 用户存的是 ERC20 代币，确保 token 地址有效
            require(token != address(0), "Invalid token address");

            // 执行 ERC20 代币的 transferFrom 操作，将资金从用户转移到存款账户
            require(IERC20(token).transferFrom(userAddress, getDepositAccount(), cost), "ERC20 transfer failed");

            // emit DepositEvent(userAddress, token, cost, "OrderID", "Deposit", "ExtraInfo", 1, 1, block.timestamp);
        }
    }

    // Deposit 功能
    function deposit2(
        uint256 cost1,        // 第一个代币的存款金额
        uint256 cost2,        // 第二个代币的存款金额
        address mint1,        // 第一个代币的地址
        address mint2,        // 第二个代币的地址
        address userAddress   // 用户的地址
    ) external payable onlyFactory { 
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

        // 事件触发，记录存款事件
        // emit DepositEvent2(userAddress, mint1, cost1, mint2, cost2, block.timestamp);
    }

    // Withdraw 功能
    function withdraw(
        address baseToken,
        address payable receiver
    ) external onlyFactory {
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

        // emit WithdrawEvent(curve.quoteToken, baseToken, quoteBalance, baseBalance, block.timestamp, receiver);
    }

    function withdraw2(
        uint256 cost,
        address token,  
        address payable receiver
    ) external onlyFactory { 
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

        // 记录转账事件
        // emit Withdraw2Event(msg.sender, receiver, token, cost, block.timestamp);
    }

}