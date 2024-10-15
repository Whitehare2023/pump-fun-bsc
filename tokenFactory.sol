// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./openzeppelin-contracts/contracts/access/Ownable.sol";
import "./openzeppelin-contracts/contracts/proxy/Clones.sol";
import "./customToken.sol";
import "./initialize_config.sol";
import "./add_quote_token.sol";
import "./state.sol"; 
import "./openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./tokenOperations.sol";

contract TokenFactory is Ownable {

    address public implementation;
    address public initialOwner;
    address WBNB;
    address pancake;
    address calculations;
    InitializeConfig public initializeConfig;
    QuoteTokenManager public quoteTokenManager;
    TokenOperations public tokenOperations;
    uint8 public decimals; 

    struct Addresses {
        address customToken;
        address tokenOperations;
    }

    mapping(uint256 => Addresses) public tokenAddresses;
    // 定义 baseToken 到 tokenOperations 地址的映射
    mapping(address => address) public baseTokenToOperations;
    uint256 public tokenIndex;

    struct TokenParams {
        string name;
        string symbol;
        string uri;
        address quoteToken;
        uint256 initialSupply;
        uint256 target;
        uint256 initVirtualQuoteReserves;
        uint256 initVirtualBaseReserves;
        uint256 feeBps;
        bool isLaunchPermitted;
    }

    constructor(
        address _implementation,
        address _initialOwner,
        address _initializeConfigAddress,
        address _quoteTokenManagerAddress,
        address _tokenOperationsAddress,
        bool isTestnet
    ) Ownable(_initialOwner) {
        implementation = _implementation;
        initialOwner = _initialOwner;
        initializeConfig = InitializeConfig(_initializeConfigAddress);
        quoteTokenManager = QuoteTokenManager(_quoteTokenManagerAddress);
        tokenOperations = TokenOperations(payable(_tokenOperationsAddress));
        decimals = 6; 

        setTokenAddresses(isTestnet);
    }

    function setTokenAddresses(bool isTestnet) internal {
        if (isTestnet) {
            // 测试网地址
            WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;  // WBNB 测试网地址
            pancake = 0x9Ac64Cc6e4415144c455Bd8E483E3Bb5CE9E4F84;  // PancakeSwap 测试网地址
            calculations = 0x95132af3E176E78ae19057Ac9Ae670c107588905;
        } else {
            // 主网地址
            WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;  // WBNB 主网地址
            pancake = 0x10ED43C718714eb63d5aA57B78B54704E256024E;  // PancakeSwap 主网地址
            calculations = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
        }
    }

    function createToken(TokenParams memory params) external payable {
        // 从 initializeConfig 中读取创建费用
        uint256 createFee = initializeConfig.createFee();
        
        // 确保创建费正确
        require(msg.value == createFee, "Insufficient creation fee");
        
        // 检查必要的参数是否存在
        require(bytes(params.name).length > 0, "Token name is required");
        require(bytes(params.symbol).length > 0, "Token symbol is required");
        require(bytes(params.uri).length > 0, "Token URI is required");
        require(params.initialSupply >= initializeConfig.baseMinSupply() && params.initialSupply <= initializeConfig.baseMaxSupply(), "Initial supply out of range");
        require(params.feeBps >= initializeConfig.baseMinFeeRate() && params.feeBps <= initializeConfig.baseMaxFeeRate(), "Fee Bps out of range");

        // 转移创建费
        (bool feeTransferSuccess, ) = payable(initializeConfig.feeRecipientAccount()).call{value: createFee}("");
        require(feeTransferSuccess, "Fee transfer failed");

        // 使用 Clone 进行 customToken 和 TokenOperations 的合约创建
        address cloneTokenInstance = Clones.clone(implementation);
        require(cloneTokenInstance != address(0), "Clone creation failed");

        address cloneOperationsInstance = Clones.clone(address(tokenOperations));
        require(cloneOperationsInstance != address(0), "Clone operations creation failed");

        // 初始化代币
        initializeToken(cloneTokenInstance, cloneOperationsInstance, params);

        // 设置 tokenFactory 地址
        TokenOperations(payable(cloneOperationsInstance)).setFactory(address(this));
        
        // 调用初始化方法传递所需的地址
        TokenOperations(payable(cloneOperationsInstance)).initialize(
            address(quoteTokenManager),        // 传入 quoteTokenManager 的地址
            address(initializeConfig),         // 传入 initializeConfig 的地址
            pancake,                           // pancakeAddress
            WBNB,                               // WBNB_ADDRESS
            calculations
        );

        // 确保 quoteToken 已注册
        QuoteTokenManager.QuoteTokenInfo memory quoteInfo = quoteTokenManager.getQuoteTokenInfo(params.quoteToken);
        require(quoteInfo.quoteMint != address(0), "Quote token not registered");

        // 初始化曲线，传递 bondingCurveBase
        TokenOperations(payable(cloneOperationsInstance)).initializeCurve(
            cloneTokenInstance,
            quoteInfo.quoteMint,
            params.initVirtualQuoteReserves,
            params.initVirtualBaseReserves,
            params.target,
            msg.sender,
            params.feeBps,
            params.isLaunchPermitted
        );

        // 记录新创建的代币和对应的 TokenOperations 实例
        tokenAddresses[tokenIndex] = Addresses({
            customToken: cloneTokenInstance,
            tokenOperations: cloneOperationsInstance
        });
        tokenIndex++;
        // 记录 新创建的 baseToken 和 tokenOperations
        baseTokenToOperations[cloneTokenInstance] = cloneOperationsInstance;

        // 触发 CreateEvent1 和 CreateEvent2
        emit CreateEvent1(
            msg.sender,
            cloneTokenInstance,
            cloneOperationsInstance,
            params.name,
            params.symbol,
            params.uri
        );

        emit CreateEvent2(
            params.initialSupply,
            params.target,
            params.initVirtualQuoteReserves,
            params.initVirtualBaseReserves,
            params.feeBps,
            params.isLaunchPermitted,
            block.timestamp
        );
    }

    function initializeToken(address cloneCustomToken, address cloneTokenOperations, TokenParams memory params) internal {

        (bool success, bytes memory data) = cloneCustomToken.call(
            abi.encodeWithSignature(
                "initialize(string,string,address,string,uint256,uint256,uint256,uint256,uint256,uint8,bool)",
                params.name,
                params.symbol,
                cloneTokenOperations,
                params.uri,
                params.initialSupply,
                params.target,
                params.initVirtualQuoteReserves,
                params.initVirtualBaseReserves,
                params.feeBps,
                decimals,
                params.isLaunchPermitted
            )
        );

        if (!success) {
            if (data.length > 0) {
                revert(string(data));
            } else {
                revert("Unknown error during initialization");
            }
        }
    }

    function buyToken(
        address baseToken, 
        uint256 quoteAmount, 
        uint256 minBaseAmount
    ) external payable {
        // 调用 TokenOperations 中的 buyToken 逻辑
        TokenOperations(payable(baseTokenToOperations[baseToken])).buyToken{value: msg.value}(baseToken, quoteAmount, minBaseAmount, msg.sender);

        // 获取曲线信息以触发事件
        CurveInfo memory curve = TokenOperations(payable(baseTokenToOperations[baseToken])).getCurveInfo(baseToken);

        // 触发 BuyEvent1
        emit BuyEvent1(
            curve.quoteToken,                     // 报价代币地址
            baseToken,                            // 基础代币地址
            quoteAmount,                          // 用户支付的报价代币数量
            curve.currentBaseReserves,            // 用户获得的基础代币数量
            curve.feeBps,                         // 手续费
            msg.sender,                           // 用户地址
            block.timestamp,                      // 时间戳
            curve.initVirtualQuoteReserves + curve.currentQuoteReserves,   // 虚拟报价代币储备量
            curve.initVirtualBaseReserves + curve.currentBaseReserves      // 虚拟基础代币储备量
        );

        // 触发 BuyEvent2
        emit BuyEvent2(
            curve.currentQuoteReserves,           // 当前报价代币储备量
            curve.currentBaseReserves,            // 当前基础代币供应量
            curve.initVirtualBaseReserves,        // 初始基础代币供应量
            curve.target,                         // 发射目标
            curve.initVirtualQuoteReserves,       // 初始虚拟报价代币储备量
            curve.initVirtualBaseReserves,        // 初始虚拟基础代币储备量
            uint16(curve.feeBps),                 // 手续费基点数
            initializeConfig.createFee(),         // 创建费用
            curve.isOnPancake                     // 是否上线 PancakeSwap
        );
    }

    function sellToken(
        address baseToken, 
        uint256 baseAmount
    ) external {
        // 调用 TokenOperations 中的 sellToken 逻辑
        TokenOperations(payable(baseTokenToOperations[baseToken])).sellToken(baseToken, baseAmount, msg.sender);

        // 获取曲线信息以触发事件
        CurveInfo memory curve = TokenOperations(payable(baseTokenToOperations[baseToken])).getCurveInfo(baseToken);

        // 触发 SellEvent1
        emit SellEvent1(
            curve.quoteToken,                        // 报价代币地址
            baseToken,                               // 基础代币地址
            curve.currentQuoteReserves,              // 用户获得的报价代币数量
            baseAmount,                              // 用户卖出的基础代币数量
            curve.feeBps,                            // 手续费
            msg.sender,                             // 用户地址
            block.timestamp,                         // 时间戳
            curve.initVirtualQuoteReserves - curve.currentQuoteReserves,  // 虚拟报价代币储备量
            curve.initVirtualBaseReserves - curve.currentBaseReserves     // 虚拟基础代币储备量
        );

        // 触发 SellEvent2
        emit SellEvent2(
            curve.currentQuoteReserves,              // 当前报价代币储备量
            curve.currentBaseReserves,               // 当前基础代币供应量
            curve.initVirtualBaseReserves,           // 初始基础代币供应量
            curve.target,                            // 发射目标
            curve.initVirtualQuoteReserves,          // 初始虚拟报价代币储备量
            curve.initVirtualBaseReserves,           // 初始虚拟基础代币储备量
            uint16(curve.feeBps),                    // 手续费基点数
            initializeConfig.createFee(),            // 创建费用
            curve.isOnPancake                        // 是否上线 PancakeSwap
        );
    }

    // 返回所有 customToken 的地址数组
    function getAllCustomTokenAddresses() public view returns (address[] memory) {
        address[] memory customTokenAddresses = new address[](tokenIndex); // 创建 customToken 地址数组
        for (uint256 i = 0; i < tokenIndex; i++) {
            customTokenAddresses[i] = tokenAddresses[i].customToken; // 从结构体中提取 customToken 地址
        }
        return customTokenAddresses;
    }

    // 返回所有 tokenOperations 的地址数组
    function getAllTokenOperationsAddresses() public view returns (address[] memory) {
        address[] memory tokenOperationsAddresses = new address[](tokenIndex); // 创建 tokenOperations 地址数组
        for (uint256 i = 0; i < tokenIndex; i++) {
            tokenOperationsAddresses[i] = tokenAddresses[i].tokenOperations; // 从结构体中提取 tokenOperations 地址
        }
        return tokenOperationsAddresses;
    }

    // Deposit 功能
    function deposit(
        uint256 cost,
        address mint,
        address baseToken
    ) external payable  {
        TokenOperations(payable(baseTokenToOperations[baseToken])).deposit{value: msg.value}(cost, mint, msg.sender);

        // 触发 DepositEvent
        emit DepositEvent(
            msg.sender,   // 存款操作的用户地址
            mint,         // 存款代币的合约地址
            cost,         // 存款的代币数量
            block.timestamp // 事件发生的时间戳
        );
    }

    function deposit2(
        uint256 cost1,        // 第一个代币的存款金额
        uint256 cost2,        // 第二个代币的存款金额
        address mint1,        // 第一个代币的地址
        address mint2,        // 第二个代币的地址
        address baseToken     // TokenOperations 实例
    ) external payable  {
        TokenOperations(payable(baseTokenToOperations[baseToken])).deposit2{value: msg.value}(cost1, cost2, mint1, mint2, msg.sender);

        // 触发 Deposit2Event 事件
        emit Deposit2Event(
            msg.sender,    // 用户地址
            mint1,         // 第一个代币地址
            cost1,         // 第一个代币的存款金额
            mint2,         // 第二个代币地址
            cost2,         // 第二个代币的存款金额
            block.timestamp  // 事件发生的时间戳
        );
    }

    function withdraw(
        address baseToken
    ) external {
        // 检查调用者是否为平台账户
        require(msg.sender == initializeConfig.platform(), "Caller is not the platform");

        // 获取曲线信息以触发事件
        CurveInfo memory curve = TokenOperations(payable(baseTokenToOperations[baseToken])).getCurveInfo(baseToken);

        // 获取池子实例中的报价代币和基础代币的储备数量
        uint256 quoteAmount = IERC20(curve.quoteToken).balanceOf(baseTokenToOperations[baseToken]);
        uint256 baseAmount = IERC20(baseToken).balanceOf(baseTokenToOperations[baseToken]);

        // 调用具体池子实例的 withdraw 方法
        TokenOperations(payable(baseTokenToOperations[baseToken])).withdraw(baseToken, payable(msg.sender));

        // 触发 WithdrawEvent
        emit WithdrawEvent(
            curve.quoteToken,                 // 报价代币的合约地址
            baseToken,                        // 基础代币的合约地址
            quoteAmount,                      // 提取的报价代币数量
            baseAmount,                       // 提取的基础代币数量
            block.timestamp,                  // 事件发生的时间戳
            msg.sender                        // 接收者（平台地址）
        );
    }

    function withdraw2(
        uint256 cost,
        address mint,
        address payable receiver,
        address baseToken
    ) external {
        // 调用 TokenOperations 合约中的 withdraw2 方法
        TokenOperations(payable(baseTokenToOperations[baseToken])).withdraw2(cost, mint, receiver);

        // 触发 Withdraw2Event
        emit Withdraw2Event(
            msg.sender,                       // 发起提现操作的系统账户地址
            receiver,                         // 接收者账户地址
            mint,                             // 提取的代币合约地址
            cost,                             // 提取的代币数量
            "OrderID",                        // 订单 ID，实际代码中你可以传入真实的 order_id
            block.timestamp                   // 事件发生的时间戳
        );
    }

    function permit(address baseToken) external {
        // 调用 TokenOperations 合约中的 permit 函数
        TokenOperations(payable(baseTokenToOperations[baseToken])).permit(baseToken, msg.sender);

        // 获取曲线信息以触发事件
        CurveInfo memory curve = TokenOperations(payable(baseTokenToOperations[baseToken])).getCurveInfo(baseToken);

        // 触发 PermitEvent
        emit PermitEvent(
            msg.sender,                          // 发起 permit 操作的用户地址
            baseToken,                           // 基础代币的合约地址
            curve.quoteToken,                    // 报价代币的合约地址
            curve.isLaunchPermitted,             // 是否允许发射
            curve.isOnPancake,                   // 是否上线 PancakeSwap
            block.timestamp                      // 时间戳
        );
    }
}