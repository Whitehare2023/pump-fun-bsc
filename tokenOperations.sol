// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./openzeppelin-contracts/contracts/access/Ownable.sol";
import "./openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./customToken.sol"; // 引入 CustomToken 合约
import "./add_quote_token.sol"; // 引入 QuoteTokenManager 合约
import "./state.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";  // 引入 PRBMathUD60x18 库

contract TokenOperations is Ownable {
    QuoteTokenManager public quoteTokenManager; // 引入 QuoteTokenManager 实例

    address public depositAccount;
    address public factory; // TokenFactory 合约地址
    bool private factorySet = false; // 确保 factory 只能设置一次

    // 定义 PancakeSwap 地址
    address public pancakeAddress = 0x9Ac64Cc6e4415144c455Bd8E483E3Bb5CE9E4F84;

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

    // 在构造函数中初始化 isTestnet，并调用 setTokenAddresses 和初始化 QuoteTokenManager
    constructor(address _depositAccount, address _quoteTokenManager, bool isTestnet) Ownable(msg.sender) {
        depositAccount = _depositAccount;
        quoteTokenManager = QuoteTokenManager(_quoteTokenManager); // 初始化 quoteTokenManager
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

    function buyToken(address baseToken, uint256 quoteAmount, uint256 minBaseAmount, address userAddress) external payable onlyFactory {
        CurveInfo storage curve = curves[baseToken];
        require(owner() == curve.creator, "Caller is not the creator of the bonding curve");
        require(!curve.isOnPancake, "Liquidity already on PancakeSwap");

        // 如果使用 WBNB 作为报价代币，进行 WBNB 转换
        if (curve.quoteToken == WBNB_ADDRESS) {
            require(msg.value == quoteAmount, "Incorrect BNB amount sent");
            (bool success, ) = WBNB_ADDRESS.call{value: quoteAmount}(abi.encodeWithSignature("deposit()"));
            require(success, "WBNB deposit failed");
        } else {
            require(IERC20(curve.quoteToken).transferFrom(userAddress, address(this), quoteAmount), "Transfer failed");
        }

        // 动态获取虚拟储备和精度信息
        (uint256 initVirtualQuoteReserves, uint256 initVirtualBaseReserves) = getVirtualReserves(curve.quoteToken);

        // 获取代币精度并计算缩放因子
        uint256 decimals = quoteTokenManager.getQuoteTokenDecimals(curve.quoteToken);
        UD60x18 scalingFactor = ud(10 ** decimals);

        // 使用 PRBMathUD60x18 进行安全计算
        UD60x18 currentQuoteReserves = ud(curve.currentQuoteReserves);
        UD60x18 newQuoteAmount = ud(quoteAmount).mul(scalingFactor);
        curve.currentQuoteReserves = currentQuoteReserves.add(newQuoteAmount).unwrap();

        // 计算买入基础代币数量
        uint256 baseAmount = calculateBaseAmountForBuy(
            initVirtualQuoteReserves,
            initVirtualBaseReserves,
            curve.currentBaseReserves,
            curve.currentQuoteReserves,
            quoteAmount,
            minBaseAmount
        );
        require(baseAmount >= minBaseAmount, "Slippage too high, minBaseAmount not met");

        // 铸造基础代币并分发给用户
        CustomToken(baseToken).mint(userAddress, baseAmount);

        // 如果达到了目标并且尚未上线 PancakeSwap，则执行流动性添加
        if (curve.currentQuoteReserves >= curve.target && !curve.isOnPancake) {
            curve.isOnPancake = true;
        }
    }

    function sellToken(address baseToken, uint256 baseAmount, address userAddress) external onlyFactory {
        CurveInfo storage curve = curves[baseToken];
        require(curve.isLaunchPermitted, "Token launch is not permitted");
        require(curve.currentBaseReserves >= baseAmount, "Not enough base reserves");

        // 动态获取虚拟储备和精度信息
        (uint256 initVirtualQuoteReserves, uint256 initVirtualBaseReserves) = getVirtualReserves(curve.quoteToken);

        // 获取代币精度并计算缩放因子
        uint256 decimals = quoteTokenManager.getQuoteTokenDecimals(curve.quoteToken);
        UD60x18 scalingFactor = ud(10 ** decimals);

        // 使用 PRBMathUD60x18 安全计算更新 currentBaseReserves
        UD60x18 currentBaseReserves = ud(curve.currentBaseReserves).mul(scalingFactor);
        UD60x18 sellBaseAmount = ud(baseAmount).mul(scalingFactor);
        curve.currentBaseReserves = currentBaseReserves.sub(sellBaseAmount).unwrap();

        // 计算卖出时获得的报价代币数量
        uint256 quoteAmount = calculateTokensSold(
            initVirtualQuoteReserves,
            initVirtualBaseReserves,
            curve.currentBaseReserves,
            curve.currentQuoteReserves,
            baseAmount
        );
        require(quoteAmount > 0, "Invalid quote amount calculated");

        // 销毁基础代币
        CustomToken(baseToken).burnFrom(userAddress, baseAmount);

        // 处理 WBNB 或其他报价代币的提款逻辑
        if (curve.quoteToken == WBNB_ADDRESS) {
            (bool success, ) = WBNB_ADDRESS.call(abi.encodeWithSignature("withdraw(uint256)", quoteAmount));
            require(success, "WBNB withdraw failed");
            (success, ) = payable(userAddress).call{value: quoteAmount}("");
            require(success, "Transfer failed");
        } else {
            require(IERC20(curve.quoteToken).transfer(userAddress, quoteAmount), "Transfer failed");
        }

        // 使用 PRBMathUD60x18 安全计算更新 currentQuoteReserves
        UD60x18 currentQuoteReserves = ud(curve.currentQuoteReserves).mul(scalingFactor);
        UD60x18 newQuoteAmount = ud(quoteAmount).mul(scalingFactor);
        curve.currentQuoteReserves = currentQuoteReserves.sub(newQuoteAmount).unwrap();

        emit TokenSold(userAddress, baseToken, baseAmount, quoteAmount);
    }

    // Deposit 功能
    function deposit(
        uint256 cost,
        address mint,
        address userAddress
    ) external payable onlyFactory { 
        require(cost > 0, "Invalid parameters");

        // 获取代币精度并计算缩放因子
        uint256 decimals = quoteTokenManager.getQuoteTokenDecimals(mint);
        UD60x18 scalingFactor = ud(10 ** decimals);

        if (mint == WBNB_ADDRESS) {
            require(msg.value == cost, "Incorrect BNB amount sent");
            (bool success, ) = payable(depositAccount).call{value: cost}("");
            require(success, "Transfer failed");
        } else {
            // 应用精度缩放
            uint256 adjustedCost = ud(cost).mul(scalingFactor).unwrap();
            require(IERC20(mint).transferFrom(userAddress, depositAccount, adjustedCost), "Transfer failed");
        }
    }

    struct DepositParams {
        string command;
        string extraInfo;
        uint8 maxIndex;
        uint8 index;
        uint256 cost1;
        uint256 cost2;
        address mint1;
        address mint2;
        address userAddress;
    }

    function deposit2(DepositParams calldata params) external payable onlyFactory { 
        require(params.cost1 > 0 && params.cost2 > 0, "Invalid parameters");
        require(params.mint1 != address(0) && params.mint2 != address(0), "Invalid mint addresses");

        // 获取代币精度并计算缩放因子
        uint256 decimals1 = quoteTokenManager.getQuoteTokenDecimals(params.mint1);
        uint256 decimals2 = quoteTokenManager.getQuoteTokenDecimals(params.mint2);
        UD60x18 scalingFactor1 = ud(10 ** decimals1);
        UD60x18 scalingFactor2 = ud(10 ** decimals2);

        if (params.mint1 == WBNB_ADDRESS) {
            require(msg.value == params.cost1, "Incorrect BNB amount sent");
            (bool success, ) = payable(depositAccount).call{value: params.cost1}("");
            require(success, "Transfer failed");
        } else {
            // 应用精度缩放
            uint256 adjustedCost1 = ud(params.cost1).mul(scalingFactor1).unwrap();
            require(IERC20(params.mint1).transferFrom(params.userAddress, depositAccount, adjustedCost1), "Transfer failed");
        }

        if (params.mint2 == WBNB_ADDRESS) {
            require(msg.value == params.cost2, "Incorrect BNB amount sent");
            (bool success, ) = payable(depositAccount).call{value: params.cost2}("");
            require(success, "Transfer failed");
        } else {
            // 应用精度缩放
            uint256 adjustedCost2 = ud(params.cost2).mul(scalingFactor2).unwrap();
            require(IERC20(params.mint2).transferFrom(params.userAddress, depositAccount, adjustedCost2), "Transfer failed");
        }

        emit DepositEvent2Part1(params.userAddress, params.mint1, params.cost1, params.mint2);
        emit DepositEvent2Part2(params.cost2, params.command, params.extraInfo, params.maxIndex, params.index, block.timestamp);
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

        // 获取代币精度并计算缩放因子
        uint256 decimals = quoteTokenManager.getQuoteTokenDecimals(quoteToken);
        UD60x18 scalingFactor = ud(10 ** decimals);

        // 应用精度缩放
        uint256 adjustedQuoteAmount = ud(quoteAmount).mul(scalingFactor).unwrap();
        uint256 adjustedBaseAmount = ud(baseAmount).mul(scalingFactor).unwrap();

        if (quoteToken == WBNB_ADDRESS) {
            (bool success, ) = WBNB_ADDRESS.call(abi.encodeWithSignature("withdraw(uint256)", adjustedQuoteAmount));
            require(success, "WBNB withdraw failed");
            (success, ) = receiver.call{value: adjustedQuoteAmount}("");
            require(success, "Transfer failed");
        } else {
            require(IERC20(quoteToken).transfer(receiver, adjustedQuoteAmount), "Transfer failed");
        }

        require(IERC20(baseToken).transfer(receiver, adjustedBaseAmount), "Transfer failed");

        emit WithdrawEvent(quoteToken, baseToken, adjustedQuoteAmount, adjustedBaseAmount, block.timestamp, receiver);
    }

    function withdraw2(
        uint256 cost,
        address mint,
        address payable receiver
    ) external onlyFactory { 
        require(mint != address(0), "Invalid token address");
        require(receiver != address(0), "Invalid receiver address");

        // 获取代币精度并计算缩放因子
        uint256 decimals = quoteTokenManager.getQuoteTokenDecimals(mint);
        UD60x18 scalingFactor = ud(10 ** decimals);

        // 应用精度缩放
        uint256 adjustedCost = ud(cost).mul(scalingFactor).unwrap();

        if (mint == WBNB_ADDRESS) {
            (bool success, ) = WBNB_ADDRESS.call(abi.encodeWithSignature("withdraw(uint256)", adjustedCost));
            require(success, "WBNB withdraw failed");
            (success, ) = receiver.call{value: adjustedCost}("");
            require(success, "Transfer failed");
        } else {
            require(IERC20(mint).transfer(receiver, adjustedCost), "Transfer failed");
        }

        emit Withdraw2Event(msg.sender, receiver, mint, adjustedCost, block.timestamp);
    }

    // 计算买入基础代币数量的公式逻辑
    function calculateBaseAmountForBuy(
        uint256 initVirtualQuoteReserves,
        uint256 initVirtualBaseReserves,
        uint256 currentBaseSupply,
        uint256 currentQuoteBalance,
        uint256 buyQuoteAmount,
        uint256 minBaseAmount
    ) internal pure returns (uint256) {
        uint256 baseAmount = calculateTokensBought(
            initVirtualQuoteReserves,
            initVirtualBaseReserves,
            currentBaseSupply,
            currentQuoteBalance,
            buyQuoteAmount
        );
        require(baseAmount >= minBaseAmount, "Slippage too high, minBaseAmount not met");
        return baseAmount;
    }

    // 计算购买代币数量的公式逻辑
    function calculateTokensBought(
        uint256 initVirtualQuoteReserves,
        uint256 initVirtualBaseReserves,
        uint256 currentBaseSupply,
        uint256 currentQuoteBalance,
        uint256 buyQuoteAmount
    ) internal pure returns (uint256) {
        UD60x18 m = ud(initVirtualQuoteReserves);
        UD60x18 p = ud(currentQuoteBalance + buyQuoteAmount);
        UD60x18 n = ud(initVirtualBaseReserves);

        UD60x18 np = n.mul(p);
        UD60x18 mPlusP = m.add(p);

        uint256 tokensBought = np.div(mPlusP).unwrap() - currentBaseSupply;

        return tokensBought > 0 ? tokensBought : 0;
    }

    // 计算卖出代币数量的公式逻辑
    function calculateTokensSold(
        uint256 initVirtualQuoteReserves,
        uint256 initVirtualBaseReserves,
        uint256 currentBaseSupply,
        uint256 currentQuoteBalance,
        uint256 sellBaseAmount
    ) internal pure returns (uint256) {
        require(currentBaseSupply >= sellBaseAmount, "Sell base amount exceeds current base supply");

        UD60x18 k = ud(currentBaseSupply - sellBaseAmount);
        UD60x18 m = ud(initVirtualQuoteReserves);
        UD60x18 n = ud(initVirtualBaseReserves);

        UD60x18 km = k.mul(m);
        UD60x18 nMinusK = n.sub(k);

        require(nMinusK.unwrap() > 0, "nMinusK is zero, cannot divide by zero");
        uint256 quoteAmount = currentQuoteBalance - km.div(nMinusK).unwrap();

        return quoteAmount > 0 ? quoteAmount : 0;
    }

    // 从 QuoteTokenManager 获取虚拟储备值
    function getVirtualReserves(address quoteMint) internal view returns (uint256, uint256) {
        QuoteTokenManager.QuoteTokenInfo memory quoteInfo = quoteTokenManager.getQuoteTokenInfo(quoteMint);
        require(quoteInfo.quoteMint != address(0), "Invalid quoteMint provided");

        uint256 initVirtualQuoteReserves = uint256(uint160(quoteInfo.feeRecipientAccount));
        uint256 initVirtualBaseReserves = uint256(uint160(quoteInfo.feeRecipientQuote));
        return (initVirtualQuoteReserves, initVirtualBaseReserves);
    }
}
