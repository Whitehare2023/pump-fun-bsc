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
    InitializeConfig public initializeConfig;
    QuoteTokenManager public quoteTokenManager;
    TokenOperations public tokenOperations;
    uint8 public decimals; 

    uint256 public baseMinSupply;
    uint256 public baseMaxSupply;
    uint256 public baseMinFeeRate;
    uint256 public baseMaxFeeRate;
    uint256 public createFee;
    address public adminAddress;
    address public platformAddress;
    address public feeRecipientAccount;
    address public depositAccount;

    mapping(uint256 => address) public tokenAddresses;
    uint256 public tokenIndex;

    event TokenCreated(address indexed tokenAddress, string name, string symbol, uint256 initialSupply, address owner);
    event Debug(string message, address addr);
    event DebugInitializeParams(string name, string symbol, address user, string uri);
    event DebugCloneResult(address cloneAddress);
    event DebugCloneError(string reason);
    event DebugValue(string message, uint256 value);

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
        address _tokenOperationsAddress
    ) Ownable(_initialOwner) {
        implementation = _implementation;
        initialOwner = _initialOwner;
        initializeConfig = InitializeConfig(_initializeConfigAddress);
        quoteTokenManager = QuoteTokenManager(_quoteTokenManagerAddress);
        tokenOperations = TokenOperations(_tokenOperationsAddress);
        decimals = 6; 
        updateConfig();

        // 为 TokenOperations 设置 factory 地址
        tokenOperations.setFactory(address(this));

        emit Debug("TokenFactory Constructor Called", address(this));
    }

    function updateConfig() public {
        (
            ,
            ,
            address _admin,
            address _platform,
            address _feeRecipientAccount,
            address _depositAccount,
            uint256 _baseMinSupply,
            uint256 _baseMaxSupply,
            uint256 _createFee,
            uint256 _baseMinFeeRate,
            uint256 _baseMaxFeeRate
        ) = initializeConfig.getProgramConfig();

        baseMinSupply = _baseMinSupply;
        baseMaxSupply = _baseMaxSupply;
        createFee = _createFee;
        feeRecipientAccount = _feeRecipientAccount;
        baseMinFeeRate = _baseMinFeeRate;
        baseMaxFeeRate = _baseMaxFeeRate;
        adminAddress = _admin;
        platformAddress = _platform;
        depositAccount = _depositAccount;

        emit DebugValue("Updated baseMinFeeRate", baseMinFeeRate);
        emit DebugValue("Updated baseMaxFeeRate", baseMaxFeeRate);
        emit DebugValue("Updated baseMinSupply", baseMinSupply);
        emit DebugValue("Updated baseMaxSupply", baseMaxSupply);
        emit DebugValue("Updated createFee", createFee);
        emit Debug("Updated feeRecipientAccount", feeRecipientAccount);
    }

    function setDecimals(uint8 newDecimals) external onlyOwner {
        decimals = newDecimals;
        emit DebugValue("Decimals set to", newDecimals);
    }

    function getNetworkAddresses() internal view returns (
        address wbnb,
        address usdt,
        address usdc,
        address busd,
        address dai
    ) {
        return (
            tokenOperations.WBNB_ADDRESS(),
            tokenOperations.USDT_ADDRESS(),
            tokenOperations.USDC_ADDRESS(),
            tokenOperations.BUSD_ADDRESS(),
            tokenOperations.DAI_ADDRESS()
        );
    }

    function createToken(TokenParams memory params) external payable returns (address) {
        updateConfig();
        
        // 确保创建费正确
        require(msg.value == createFee, "Insufficient creation fee");
        
        // 检查必要的参数是否存在
        require(bytes(params.name).length > 0, "Token name is required");
        require(bytes(params.symbol).length > 0, "Token symbol is required");
        require(bytes(params.uri).length > 0, "Token URI is required");
        require(params.initialSupply >= baseMinSupply && params.initialSupply <= baseMaxSupply, "Initial supply out of range");
        require(params.feeBps >= baseMinFeeRate && params.feeBps <= baseMaxFeeRate, "Fee Bps out of range");

        // 转移创建费
        (bool feeTransferSuccess, ) = payable(feeRecipientAccount).call{value: createFee}("");
        require(feeTransferSuccess, "Fee transfer failed");

        // 使用 Clone 进行合约创建
        address cloneInstance = Clones.clone(implementation);
        require(cloneInstance != address(0), "Clone creation failed");

        // 初始化代币
        initializeToken(cloneInstance, params, params.initialSupply);

        // 设置小数位
        CustomToken(cloneInstance).setDecimals(decimals);

        // 设置 factory 地址
        CustomToken(cloneInstance).setFactory(address(this));

        // 设置 operations 地址
        CustomToken(cloneInstance).setOperations(address(tokenOperations));

        // 确保 quoteToken 已注册
        QuoteTokenManager.QuoteTokenInfo memory quoteInfo = quoteTokenManager.getQuoteTokenInfo(params.quoteToken);
        require(quoteInfo.quoteMint != address(0), "Quote token not registered");

        // 初始化曲线
        tokenOperations.initializeCurve(
            cloneInstance,
            quoteInfo.quoteMint,
            params.initVirtualQuoteReserves,
            params.initVirtualBaseReserves,
            params.target,
            msg.sender,
            params.feeBps,
            params.isLaunchPermitted
        );

        // 记录新创建的代币
        tokenAddresses[tokenIndex] = cloneInstance;
        tokenIndex++;

        // 触发事件
        emit TokenCreated(cloneInstance, params.name, params.symbol, params.initialSupply, initialOwner);

        return cloneInstance;
    }

    function initializeToken(address cloneInstance, TokenParams memory params, uint256 initialSupply) internal {
        emit DebugInitializeParams(params.name, params.symbol, initialOwner, params.uri);

        (bool success, bytes memory data) = cloneInstance.call(
            abi.encodeWithSignature(
                "initialize(string,string,address,string,uint256,uint256,uint256,uint256,uint256,uint256,bool)",
                params.name,
                params.symbol,
                initialOwner,
                params.uri,
                initialSupply,
                params.target,
                params.initVirtualQuoteReserves,
                params.initVirtualBaseReserves,
                params.feeBps,
                createFee,
                params.isLaunchPermitted
            )
        );

        if (!success) {
            emit Debug("Initialization failed", cloneInstance);
            if (data.length > 0) {
                emit DebugCloneError(string(data));
                revert(string(data));
            } else {
                revert("Unknown error during initialization");
            }
        }
    }

    // function initializeBondingCurve(address baseToken) external onlyOwner {
    //     CurveInfo memory curve = tokenOperations.getCurveInfo(baseToken);

    //     require(curve.baseToken != address(0), "Curve does not exist for the provided baseToken");
    //     require(CustomToken(baseToken).owner() == owner(), "TokenFactory and CustomToken owner mismatch");

    //     CustomToken(baseToken).mint(address(this), curve.initVirtualBaseReserves);
    //     emit Debug("Bonding curve accounts created", address(this));
    // }

    function buyToken(
        address baseToken, 
        uint256 quoteAmount, 
        uint256 minBaseAmount
    ) external payable {
        tokenOperations.buyToken{value: msg.value}(baseToken, quoteAmount, minBaseAmount, msg.sender);
    }

    function sellToken(address baseToken, uint256 baseAmount) external onlyOwner {
        tokenOperations.sellToken(baseToken, baseAmount, msg.sender);
    }

    function getAllTokenAddresses() public view returns (address[] memory) {
        address[] memory addresses = new address[](tokenIndex);
        for (uint256 i = 0; i < tokenIndex; i++) {
            addresses[i] = tokenAddresses[i];
        }
        return addresses;
    }

    function setTokenDecimals(address tokenAddress, uint8 newDecimals) internal onlyOwner {
        require(tokenAddress != address(0), "Invalid token address");

        (bool success, ) = tokenAddress.call(
            abi.encodeWithSignature("setDecimals(uint8)", newDecimals)
        );
        require(success, "Failed to set token decimals");

        emit DebugValue("Decimals set for token", newDecimals);
    }
    
    // Deposit 功能
    function deposit(
        uint256 cost,
        address mint
    ) external payable  {
        tokenOperations.deposit{value: msg.value}(cost, mint, msg.sender);
    }

    function deposit2(
        TokenOperations.DepositParams calldata params
    ) external payable  {
        tokenOperations.deposit2{value: msg.value}(params);
    }

    // Withdraw 功能
    function withdraw(
        address baseToken,
        address quoteToken,
        uint256 quoteAmount,
        uint256 baseAmount,
        address payable receiver
    ) external  {
        tokenOperations.withdraw(baseToken, quoteToken, quoteAmount, baseAmount, receiver);
    }

    function withdraw2(
        uint256 cost,
        address mint,
        address payable receiver
    ) external  {
        tokenOperations.withdraw2(cost, mint, receiver);
    }

    // 用户传入完整的代币数量
    function approveToken(address owner, address token, uint256 amount, address spender) external {
        require(CustomToken(token).approveToken(owner, spender, amount), "Approve failed");
        emit DebugValue("Approved amount", amount);
    }

    function permit(address baseToken) external {
        // 调用 TokenOperations 合约中的 permit 函数
        tokenOperations.permit(baseToken);
    }
}
