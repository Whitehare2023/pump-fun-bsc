// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./openzeppelin-contracts/contracts/access/Ownable.sol";
import "./initialize_config.sol";  // 导入 InitializeConfig 合约定义
import "./formula.sol";  // 引入 PumpFormula 逻辑
import "./state.sol";  // 导入 state.sol 
import "./add_quote_token.sol"; // 导入 QuoteTokenManager 合约
import "./tokenFactory.sol"; // 导入 TokenFactory 合约

contract CreateToken is Ownable {
    using SafeERC20 for IERC20;

    struct TokenMetadata {
        string name;
        string symbol;
        string uri;
    }

    mapping(address => TokenMetadata) private _tokenMetadata;

    event MetadataCreated(address indexed baseMint, string name, string symbol, string uri);

    struct CreateArgs {
        string name;
        string symbol;
        string uri;
        uint256 supply;
        uint256 target;
        uint256 initVirtualQuoteReserves;
        uint256 initVirtualBaseReserves;
        uint256 feeBps;
        bool isLaunchPermitted;
    }

    uint8 public constant DECIMALS = 6;  // 代币的精度为 6
    uint256 public constant DECIMALS_FACTOR = 10 ** DECIMALS;  // 精度因子

    uint256 public baseMinFeeRate;
    uint256 public baseMaxFeeRate;
    uint256 public baseMinSupply;
    uint256 public baseMaxSupply;
    uint256 public createFee;
    address public feeRecipient;

    mapping(address => CurveInfoPart1) public bondingCurvesPart1;
    mapping(address => CurveInfoPart2) public bondingCurvesPart2;

    TokenFactory public tokenFactory;
    PumpFormula public pumpFormula;
    InitializeConfig public initializeConfig;
    QuoteTokenManager public quoteTokenManager;

    event Debug(string message, uint256 value); // 用于调试的事件
    event DebugAddress(string message, address addr); // 调试地址

    constructor(
        address _tokenFactoryAddress,
        address _pumpFormulaAddress,
        address _initializeConfigAddress,
        address _quoteTokenManagerAddress,
        address initialOwner
    ) Ownable(initialOwner) {
        tokenFactory = TokenFactory(_tokenFactoryAddress);
        pumpFormula = PumpFormula(_pumpFormulaAddress);
        initializeConfig = InitializeConfig(_initializeConfigAddress);
        quoteTokenManager = QuoteTokenManager(_quoteTokenManagerAddress);

        // 初始化配置
        updateConfig();
    }

    // 更新配置函数
    function updateConfig() public {
        (
            , // isInitialized
            , // bump
            , // admin
            , // platform
            address feeRecipientAccount,
            , // depositAccount
            uint256 _baseMinSupply,
            uint256 _baseMaxSupply,
            uint256 _createFee,
            uint256 _baseMinFeeRate,
            uint256 _baseMaxFeeRate
        ) = initializeConfig.getProgramConfig();

        // 将人类可读的值转换为代币的最小单位
        baseMinSupply = _baseMinSupply;  
        baseMaxSupply = _baseMaxSupply;  
        createFee = _createFee;  // 从配置中获取创建手续费
        feeRecipient = feeRecipientAccount;
        baseMinFeeRate = _baseMinFeeRate;
        baseMaxFeeRate = _baseMaxFeeRate;

        // 更新调试日志以确认状态变量的更改
        emit Debug("Updated baseMinFeeRate", baseMinFeeRate);
        emit Debug("Updated baseMaxFeeRate", baseMaxFeeRate);
        emit Debug("Updated baseMinSupply", baseMinSupply);
        emit Debug("Updated baseMaxSupply", baseMaxSupply);
        emit Debug("Updated createFee", createFee);
        emit DebugAddress("Updated feeRecipient", feeRecipient);
    }

    function createToken(CreateArgs memory args) public payable onlyOwner returns (address) {
        emit Debug("Starting createToken", 0);

        // 检查代币名称、符号和 URI 是否为空
        require(bytes(args.name).length > 0, "Token name is required");
        require(bytes(args.symbol).length > 0, "Token symbol is required");
        require(bytes(args.uri).length > 0, "Token URI is required");

        // 检查 feeBps 是否在有效范围内
        require(args.feeBps >= baseMinFeeRate && args.feeBps <= baseMaxFeeRate, "Invalid feeBps");

        // 将用户输入的供应量转换为最小单位
        uint256 adjustedSupply = args.supply * DECIMALS_FACTOR; 
        uint256 adjustedTarget = args.target * DECIMALS_FACTOR; 
        uint256 adjustedInitVirtualQuoteReserves = args.initVirtualQuoteReserves * DECIMALS_FACTOR; 
        uint256 adjustedInitVirtualBaseReserves = args.initVirtualBaseReserves * DECIMALS_FACTOR; 

        // 检查 supply 是否在有效范围内
        require(adjustedSupply >= baseMinSupply && adjustedSupply <= baseMaxSupply, "Invalid input supply");

        // 检查 target, initVirtualQuoteReserves 和 initVirtualBaseReserves 是否为正数
        require(adjustedTarget > 0, "Target must be greater than zero");
        require(adjustedInitVirtualQuoteReserves > 0, "Initial virtual quote reserves must be greater than zero");
        require(adjustedInitVirtualBaseReserves > 0, "Initial virtual base reserves must be greater than zero");

        // 检查 createFee 并确保用户有足够的 BNB 来支付 createFee
        if (createFee > 0) {
            require(msg.value == createFee, "msg.value != createFee!");

            // 转账 BNB 给 feeRecipient
            (bool sent, ) = payable(feeRecipient).call{value: createFee}("");
            require(sent, "Failed to send BNB to fee recipient");
        }

        // 使用 TokenFactory 创建新的 baseMint (代币) 合约
        address baseMint = tokenFactory.createToken(
            TokenFactory.TokenParams({
                name: args.name,
                symbol: args.symbol,
                uri: args.uri,
                initialSupply: adjustedSupply, // 使用调整后的供应量
                target: adjustedTarget,
                initVirtualQuoteReserves: adjustedInitVirtualQuoteReserves,
                initVirtualBaseReserves: adjustedInitVirtualBaseReserves,
                feeBps: args.feeBps,
                createFee: createFee,  // 使用从配置中获取的 createFee
                isLaunchPermitted: args.isLaunchPermitted
            })
        );

        require(baseMint != address(0), "Failed to create custom token");

        bondingCurvesPart1[baseMint] = CurveInfoPart1({
            bump: 0,
            quoteBump: 0,
            baseBump: 0,
            creator: msg.sender,
            target: adjustedTarget,
            initVirtualBaseReserves: adjustedInitVirtualBaseReserves,
            initVirtualQuoteReserves: adjustedInitVirtualQuoteReserves
        });

        bondingCurvesPart2[baseMint] = CurveInfoPart2({
            initSupply: adjustedSupply,
            feeBps: args.feeBps,
            quoteBalance: 0,
            baseSupply: 0,
            createFee: createFee,
            isLaunchPermitted: args.isLaunchPermitted,
            isOnPancake: false
        });

        _createTokenMetadata(baseMint, args.name, args.symbol, args.uri);

        emit CreateEventPart1(
            msg.sender,
            baseMint,
            args.name,
            args.symbol,
            args.uri
        );

        emit CreateEventPart2(
            baseMint,
            adjustedSupply,
            adjustedTarget,
            adjustedInitVirtualQuoteReserves,
            adjustedInitVirtualBaseReserves,
            args.feeBps,
            createFee,
            args.isLaunchPermitted,
            block.timestamp
        );

        return baseMint;  // 返回新创建的代币地址
    }

    // 提供获取所有创建的代币信息的接口
    function getTokenMetadata(address baseMint) public view returns (TokenMetadata memory) {
        require(baseMint != address(0), "Invalid token address");
        return _tokenMetadata[baseMint];
    }

    // 更新代币元数据
    function setTokenMetadata(address baseMint, string memory name, string memory symbol, string memory uri) public {
        require(baseMint != address(0), "Invalid token address");
        _tokenMetadata[baseMint] = TokenMetadata(name, symbol, uri);
        emit MetadataCreated(baseMint, name, symbol, uri);
    }

    function _createTokenMetadata(address baseMint, string memory name, string memory symbol, string memory uri) internal {
        setTokenMetadata(baseMint, name, symbol, uri);
        emit MetadataCreated(baseMint, name, symbol, uri);
    }

    // 设置参数
    function setParameters(
        uint256 _baseMinFeeRate,
        uint256 _baseMaxFeeRate,
        uint256 _baseMinSupply,
        uint256 _baseMaxSupply,
        uint256 _createFee
    ) external onlyOwner {
        baseMinFeeRate = _baseMinFeeRate;
        baseMaxFeeRate = _baseMaxFeeRate;
        baseMinSupply = _baseMinSupply * DECIMALS_FACTOR;  // 转换为最小单位
        baseMaxSupply = _baseMaxSupply * DECIMALS_FACTOR;  // 转换为最小单位
        createFee = _createFee;
    }

    // 获取合约的配置信息
    function getConfig() external view returns (uint256, uint256, uint256, uint256, uint256) {
        return (baseMinFeeRate, baseMaxFeeRate, baseMinSupply, baseMaxSupply, createFee);
    }

    event TokensSoldEvent(uint256 tokensSold);
}
