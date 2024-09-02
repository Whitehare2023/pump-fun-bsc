// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./openzeppelin-contracts/contracts/access/Ownable.sol";
import "./openzeppelin-contracts/contracts/proxy/Clones.sol";
import "./customToken1.sol";
import "./initialize_config.sol";
import "./add_quote_token.sol";
import "./state.sol";
import "./ABDKMath64x64.sol";
import "./openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./formula.sol";  // 引入 PumpFormula 合约
import "./deposit.sol";  // 引入 Deposit 合约

contract TokenFactory is Ownable {
    using ABDKMath64x64 for int128;

    address public implementation;
    address public initialOwner;
    InitializeConfig public initializeConfig;
    QuoteTokenManager public quoteTokenManager;
    PumpFormula public pumpFormula;  // PumpFormula 实例

    address public constant WBNB_ADDRESS = 0x0dE8FCAE8421fc79B29adE9ffF97854a424Cad09;
    address public constant USDT_ADDRESS = 0x557fD01B268b20635C1deD60622FA1185C9329E4;
    address public constant USDC_ADDRESS = 0x64544969ed7EBf5f083679233325356EbE738930;
    address public constant BUSD_ADDRESS = 0x78867BbEeF44f2326bF8DDd1941a4439382EF2A7;
    address public constant DAI_ADDRESS = 0x8a9424745056Eb399FD19a0EC26A14316684e274;

    struct CurveInfo {
        address baseToken;
        address quoteToken;
        uint256 initVirtualQuoteReserves;
        uint256 initVirtualBaseReserves;
        uint256 currentQuoteReserves;
        uint256 currentBaseReserves;
        uint256 feeBps;
        uint256 target; // 新增的 target 变量
        bool isLaunchPermitted;
        bool isOnPancake; // 替换 isOnRaydium 为 isOnPancake
    }

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
    event TokenPurchased(address indexed buyer, address baseToken, uint256 quoteAmount, uint256 baseAmount);
    event TokenSold(address indexed seller, address baseToken, uint256 baseAmount, uint256 quoteAmount);
    event PermitEvent(address indexed creator, address indexed baseToken, address indexed quoteToken, bool isLaunchPermitted, bool isOnPancake);

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
        address _pumpFormulaAddress // 添加 PumpFormula 合约地址
    ) Ownable(_initialOwner) {
        implementation = _implementation;
        initialOwner = _initialOwner;
        initializeConfig = InitializeConfig(_initializeConfigAddress);
        quoteTokenManager = QuoteTokenManager(_quoteTokenManagerAddress);
        pumpFormula = PumpFormula(_pumpFormulaAddress); // 实例化 PumpFormula
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

        // 直接使用传入的 initialSupply，无需调整
        initializeToken(cloneInstance, params);

        // 每次创建新的 Token 合约实例时都调用 setFactory
        CustomToken(cloneInstance).setFactory(address(this));

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
            isLaunchPermitted: params.isLaunchPermitted,
            isOnPancake: false // 初始设置为 false
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
                params.initialSupply, // 直接使用 initialSupply
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

        // 确保 TokenFactory 和 CustomToken 的所有者一致
        require(CustomToken(baseToken).owner() == owner(), "TokenFactory and CustomToken owner mismatch");

        curve.currentQuoteReserves = curve.initVirtualQuoteReserves;
        curve.currentBaseReserves = curve.initVirtualBaseReserves;

        // 铸造代币到工厂合约地址
        CustomToken(baseToken).mint(address(this), curve.initVirtualBaseReserves);
        emit Debug("Bonding curve accounts created", address(this));
    }

    function permit(address baseToken) external {
        CurveInfo storage curve = curves[baseToken];
        require(curve.baseToken != address(0), "Curve does not exist for the provided baseToken");
        
        // 检查调用者是否为 bonding curve 的创建者
        require(msg.sender == owner(), "Caller is not the creator of the bonding curve");

        // 确保尚未将 bonding curve 设置为 PancakeSwap
        require(!curve.isOnPancake, "Invalid parameters");

        // 切换 isLaunchPermitted 状态
        curve.isLaunchPermitted = !curve.isLaunchPermitted;

        // 检查是否应将代币投放到 PancakeSwap
        if (curve.isLaunchPermitted && curve.currentQuoteReserves >= curve.target) {
            curve.isOnPancake = true;
        }

        emit PermitEvent(msg.sender, baseToken, curve.quoteToken, curve.isLaunchPermitted, curve.isOnPancake);
    }

    function buyToken(address baseToken, uint256 quoteAmount) external payable {
        CurveInfo storage curve = curves[baseToken];
        require(curve.isLaunchPermitted, "Token launch is not permitted");

        if (curve.quoteToken == WBNB_ADDRESS) {
            require(msg.value == quoteAmount, "Incorrect BNB amount sent");
            (bool success, ) = WBNB_ADDRESS.call{value: quoteAmount}(
                abi.encodeWithSignature("deposit()")
            );
            require(success, "WBNB deposit failed");
        } else {
            require(IERC20(curve.quoteToken).transferFrom(msg.sender, address(this), quoteAmount), "Transfer failed");
        }

        curve.currentQuoteReserves += quoteAmount;

        // 使用 PumpFormula 计算买入的基础代币数量
        uint256 baseAmount = pumpFormula.buy(
            curve.quoteToken,
            curve.currentBaseReserves,
            curve.currentQuoteReserves,
            quoteAmount
        );
        require(baseAmount > 0, "Invalid base amount calculated");

        CustomToken(baseToken).mint(msg.sender, baseAmount);
        curve.currentBaseReserves += baseAmount;

        emit TokenPurchased(msg.sender, baseToken, quoteAmount, baseAmount);
    }

    function sellToken(address baseToken, uint256 baseAmount) external {
        CurveInfo storage curve = curves[baseToken];
        require(curve.isLaunchPermitted, "Token launch is not permitted");

        require(curve.currentBaseReserves >= baseAmount, "Not enough base reserves");
        curve.currentBaseReserves -= baseAmount;
        uint256 quoteAmount = pumpFormula.sell(
            curve.quoteToken,
            curve.currentBaseReserves,
            curve.currentQuoteReserves,
            baseAmount
        );
        require(quoteAmount > 0, "Invalid quote amount calculated");

        CustomToken(baseToken).burnFrom(msg.sender, baseAmount);

        if (curve.quoteToken == WBNB_ADDRESS) {
            (bool success, ) = WBNB_ADDRESS.call(
                abi.encodeWithSignature("withdraw(uint256)", quoteAmount)
            );
            require(success, "WBNB withdraw failed");
            (success, ) = payable(msg.sender).call{value: quoteAmount}("");
            require(success, "Transfer failed");
        } else {
            require(IERC20(curve.quoteToken).transfer(msg.sender, quoteAmount), "Transfer failed");
        }

        curve.currentQuoteReserves -= quoteAmount;

        emit TokenSold(msg.sender, baseToken, baseAmount, quoteAmount);
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
}
