// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./openzeppelin-contracts/contracts/access/Ownable.sol";
import "./openzeppelin-contracts/contracts/proxy/Clones.sol";
import "./customToken1.sol";
import "./initialize_config.sol";
import "./add_quote_token.sol";
import "./state.sol"; // 引入 state.sol 以使用其事件声明
import "./ABDKMath64x64.sol";
import "./openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./formula.sol";  // 引入 PumpFormula 合约
import "./tokenOperations.sol"; // 引入 TokenOperations 合约

contract TokenFactory is Ownable {
    using ABDKMath64x64 for int128;

    address public implementation;
    address public initialOwner;
    InitializeConfig public initializeConfig;
    QuoteTokenManager public quoteTokenManager;
    TokenOperations public tokenOperations; // 将原来的 DepositAndWithdraw 替换为 TokenOperations

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
    mapping(address => CurveInfo) public curves;

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
        address _tokenOperationsAddress // 使用新的 TokenOperations 地址
    ) Ownable(_initialOwner) {
        implementation = _implementation;
        initialOwner = _initialOwner;
        initializeConfig = InitializeConfig(_initializeConfigAddress);
        quoteTokenManager = QuoteTokenManager(_quoteTokenManagerAddress);
        tokenOperations = TokenOperations(_tokenOperationsAddress); // 初始化 TokenOperations 合约

        updateConfig();
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

    function createToken(TokenParams memory params) external payable onlyOwner returns (address) {
        updateConfig();
        require(msg.value == createFee, "Insufficient creation fee");
        require(bytes(params.name).length > 0, "Token name is required");
        require(bytes(params.symbol).length > 0, "Token symbol is required");
        require(bytes(params.uri).length > 0, "Token URI is required");
        require(params.initialSupply >= baseMinSupply && params.initialSupply <= baseMaxSupply, "Initial supply out of range");
        require(params.feeBps >= baseMinFeeRate && params.feeBps <= baseMaxFeeRate, "Fee Bps out of range");

        (bool feeTransferSuccess, ) = payable(feeRecipientAccount).call{value: createFee}("");
        require(feeTransferSuccess, "Fee transfer failed");

        address cloneInstance = Clones.clone(implementation);
        require(cloneInstance != address(0), "Clone creation failed");

        initializeToken(cloneInstance, params);

        QuoteTokenManager.QuoteTokenInfo memory quoteInfo = quoteTokenManager.getQuoteTokenInfo(params.quoteToken);
        require(quoteInfo.quoteMint != address(0), "Quote token not registered");

        curves[cloneInstance] = CurveInfo({
            baseToken: cloneInstance,
            quoteToken: quoteInfo.quoteMint,
            initVirtualQuoteReserves: params.initVirtualQuoteReserves,
            initVirtualBaseReserves: params.initVirtualBaseReserves,
            currentQuoteReserves: params.initVirtualQuoteReserves,
            currentBaseReserves: params.initialSupply,
            feeBps: params.feeBps,
            target: params.target,
            creator: msg.sender, // 添加creator参数
            isLaunchPermitted: params.isLaunchPermitted,
            isOnPancake: false
        });

        tokenAddresses[tokenIndex] = cloneInstance;
        tokenIndex++;

        emit TokenCreated(cloneInstance, params.name, params.symbol, params.initialSupply, initialOwner);
        return cloneInstance;
    }

    function initializeToken(address cloneInstance, TokenParams memory params) internal {
        emit DebugInitializeParams(params.name, params.symbol, initialOwner, params.uri);

        (bool success, bytes memory data) = cloneInstance.call(
            abi.encodeWithSignature(
                "initialize(string,string,address,string,uint256,uint256,uint256,uint256,uint256,uint256,bool)",
                params.name,
                params.symbol,
                initialOwner,
                params.uri,
                params.initialSupply,
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

    function initializeBondingCurve(address baseToken) external onlyOwner {
        CurveInfo storage curve = curves[baseToken];
        require(curve.baseToken != address(0), "Curve does not exist for the provided baseToken");

        require(CustomToken(baseToken).owner() == owner(), "TokenFactory and CustomToken owner mismatch");

        curve.currentQuoteReserves = curve.initVirtualQuoteReserves;
        curve.currentBaseReserves = curve.initVirtualBaseReserves;

        CustomToken(baseToken).mint(address(this), curve.initVirtualBaseReserves);
        emit Debug("Bonding curve accounts created", address(this));
    }

    // 更新后的 permit 函数
    function permit(address baseToken) external onlyOwner {
        tokenOperations.permit(baseToken);
    }

    // 更新后的 buyToken 函数
    function buyToken(
        address baseToken, 
        uint256 quoteAmount, 
        uint256 minBaseAmount
    ) external payable onlyOwner {
        tokenOperations.buyToken{value: msg.value}(baseToken, quoteAmount, minBaseAmount);
    }

    // 更新后的 sellToken 函数
    function sellToken(address baseToken, uint256 baseAmount) external onlyOwner {
        tokenOperations.sellToken(baseToken, baseAmount);
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

    function deposit(
        string calldata orderId,
        string calldata command,
        string calldata extraInfo,
        uint8 maxIndex,
        uint8 index,
        uint256 cost,
        address mint
    ) external payable onlyOwner {
        tokenOperations.deposit{value: msg.value}(orderId, command, extraInfo, maxIndex, index, cost, mint);
    }

    function deposit2(
        TokenOperations.DepositParams calldata params
    ) external payable onlyOwner {
        tokenOperations.deposit2{value: msg.value}(params);
    }

    function withdraw(
        address baseToken,
        address quoteToken,
        uint256 quoteAmount,
        uint256 baseAmount,
        address payable receiver
    ) external onlyOwner {
        tokenOperations.withdraw(baseToken, quoteToken, quoteAmount, baseAmount, receiver);
    }

    function withdraw2(
        string calldata orderId,
        uint256 cost,
        address mint,
        address payable receiver
    ) external onlyOwner {
        tokenOperations.withdraw2(orderId, cost, mint, receiver);
    }
}
