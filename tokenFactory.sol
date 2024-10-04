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
        tokenOperations = TokenOperations(_tokenOperationsAddress);
        decimals = 6; 

        setTokenAddresses(isTestnet);
        initializeConfig.setFactory(address(this));
    }

    function setTokenAddresses(bool isTestnet) internal {
        if (isTestnet) {
            // 测试网地址
            WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;  // WBNB 测试网地址
            pancake = 0x9Ac64Cc6e4415144c455Bd8E483E3Bb5CE9E4F84;  // PancakeSwap 测试网地址
        } else {
            // 主网地址
            WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;  // WBNB 主网地址
            pancake = 0x10ED43C718714eb63d5aA57B78B54704E256024E;  // PancakeSwap 主网地址
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

        // 设置 operations 地址
        CustomToken(cloneTokenInstance).setOperations(cloneOperationsInstance);
        // 设置 tokenFactory 地址
        TokenOperations(cloneOperationsInstance).setFactory(address(this));

        // 调用初始化方法传递所需的地址
        TokenOperations(cloneOperationsInstance).initialize(
            address(quoteTokenManager),        // 传入 quoteTokenManager 的地址
            address(initializeConfig),         // 传入 initializeConfig 的地址
            pancake,                           // pancakeAddress
            WBNB                               // WBNB_ADDRESS
        );

        // 确保 quoteToken 已注册
        QuoteTokenManager.QuoteTokenInfo memory quoteInfo = quoteTokenManager.getQuoteTokenInfo(params.quoteToken);
        require(quoteInfo.quoteMint != address(0), "Quote token not registered");

        // 初始化曲线，传递 bondingCurveBase
        TokenOperations(cloneOperationsInstance).initializeCurve(
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
        TokenOperations(baseTokenToOperations[baseToken]).buyToken{value: msg.value}(baseToken, quoteAmount, minBaseAmount, msg.sender);
    }

    function sellToken(address baseToken, uint256 baseAmount) external onlyOwner {
        TokenOperations(baseTokenToOperations[baseToken]).sellToken(baseToken, baseAmount, msg.sender);
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
        TokenOperations(baseTokenToOperations[baseToken]).deposit{value: msg.value}(cost, mint, msg.sender);
    }

    function deposit2(
        uint256 cost1,        // 第一个代币的存款金额
        uint256 cost2,        // 第二个代币的存款金额
        address mint1,        // 第一个代币的地址
        address mint2,        // 第二个代币的地址
        address baseToken     // TokenOperations 实例
    ) external payable  {
        TokenOperations(baseTokenToOperations[baseToken]).deposit2{value: msg.value}(cost1, cost2, mint1, mint2, msg.sender);
    }

    // Withdraw 功能
    function withdraw(
        address baseToken
    ) external  {
        // 检查调用者是否为平台账户
        require(msg.sender == initializeConfig.platform(), "Caller is not the platform");

        // 调用具体池子实例的 withdraw 方法
        TokenOperations(baseTokenToOperations[baseToken]).withdraw(baseToken, payable(msg.sender));
    }

    function withdraw2(
        uint256 cost,
        address mint,
        address payable receiver,
        address baseToken
    ) external  {
        TokenOperations(baseTokenToOperations[baseToken]).withdraw2(cost, mint, receiver);
    }

    function permit(address baseToken) external {
        // 调用 TokenOperations 合约中的 permit 函数
        TokenOperations(baseTokenToOperations[baseToken]).permit(baseToken,msg.sender);
    }

    // 允许 TokenFactory 的拥有者通过这些接口修改 InitializeConfig 中的参数
    function updatePlatformAddress(address newPlatform) external onlyOwner {
        initializeConfig.updatePlatform(newPlatform);
    }

    function updateFeeRecipientAddress(address newFeeRecipient) external onlyOwner {
        initializeConfig.updateFeeRecipient(newFeeRecipient);
    }

    function updateDepositAccountAddress(address newDepositAccount) external onlyOwner {
        initializeConfig.updateDepositAccount(newDepositAccount);
    }

    function updateSupplyLimits(uint256 newBaseMinSupply, uint256 newBaseMaxSupply) external onlyOwner {
        initializeConfig.updateSupplyLimits(newBaseMinSupply, newBaseMaxSupply);
    }

    function updateFeeRates(uint256 newBaseMinFeeRate, uint256 newBaseMaxFeeRate) external onlyOwner {
        initializeConfig.updateFeeRates(newBaseMinFeeRate, newBaseMaxFeeRate);
    }

    function updateCreateFee(uint256 newCreateFee) external onlyOwner {
        initializeConfig.updateCreateFee(newCreateFee);
    }
}