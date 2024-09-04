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
import "./deposit&withdraw.sol";

contract TokenFactory is Ownable {
    using ABDKMath64x64 for int128;

    address public implementation;
    address public initialOwner;
    InitializeConfig public initializeConfig;
    QuoteTokenManager public quoteTokenManager;
    PumpFormula public pumpFormula;  // PumpFormula 实例
    DepositAndWithdraw public depositAndWithdraw; // 把 deposit 和 withdraw 分离出去避免合约过大

    // 定义 PancakeSwap Router 地址
    address public constant PANCAKE_TESTNET_ADDRESS = 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3; // BSC Testnet
    address public constant PANCAKE_MAINNET_ADDRESS = 0x10ED43C718714eb63d5aA57B78B54704E256024E; // BSC Mainnet

    // 测试网和主网的代币地址
    address public constant WBNB_TESTNET_ADDRESS = 0x0dE8FCAE8421fc79B29adE9ffF97854a424Cad09; // WBNB Testnet
    address public constant WBNB_MAINNET_ADDRESS = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // WBNB Mainnet

    address public constant USDT_TESTNET_ADDRESS = 0x7ef95A0fEab5e1dA0041a2FD6B44cF59FFbEEf2B; // USDT Testnet
    address public constant USDT_MAINNET_ADDRESS = 0x55d398326f99059fF775485246999027B3197955; // USDT Mainnet

    address public constant USDC_TESTNET_ADDRESS = 0x64544969ed7EBf5f083679233325356EbE738930; // USDC Testnet
    address public constant USDC_MAINNET_ADDRESS = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d; // USDC Mainnet

    address public constant BUSD_TESTNET_ADDRESS = 0x78867BbEeF44f2326bF8DDd1941a4439382EF2A7; // BUSD Testnet
    address public constant BUSD_MAINNET_ADDRESS = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56; // BUSD Mainnet

    address public constant DAI_TESTNET_ADDRESS = 0x8a9424745056Eb399FD19a0EC26A14316684e274; // DAI Testnet
    address public constant DAI_MAINNET_ADDRESS = 0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3; // DAI Mainnet

    // 当前使用的地址（主网或测试网）
    address public pancakeAddress;
    address public wbnbAddress;
    address public usdtAddress;
    address public usdcAddress;
    address public busdAddress;
    address public daiAddress;

    uint256 public baseMinSupply;
    uint256 public baseMaxSupply;
    uint256 public baseMinFeeRate;
    uint256 public baseMaxFeeRate;
    uint256 public createFee;
    address public adminAddress;
    address public platformAddress;
    address public feeRecipientAccount;
    address public depositAccount;
    address public depositAndWithdrawAddress;

    mapping(uint256 => address) public tokenAddresses;
    uint256 public tokenIndex;
    mapping(address => CurveInfo) public curves;

    event TokenCreated(address indexed tokenAddress, string name, string symbol, uint256 initialSupply, address owner);
    event Debug(string message, address addr);
    event DebugInitializeParams(string name, string symbol, address user, string uri);
    event DebugCloneResult(address cloneAddress);
    event DebugCloneError(string reason);
    event DebugValue(string message, uint256 value);

    // 更新事件声明，包含所有参数
    event TokenPurchased(
        address indexed buyer, 
        address baseToken, 
        uint256 quoteAmount, 
        uint256 baseAmount,
        uint256 currentQuoteReserves, 
        uint256 currentBaseReserves,
        uint256 timestamp
    );

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
        address _pumpFormulaAddress,
        address _depositAndWithdrawAddress,
        bool isTestnet // 新增参数，用于选择测试网或主网
    ) Ownable(_initialOwner) {
        implementation = _implementation;
        initialOwner = _initialOwner;
        initializeConfig = InitializeConfig(_initializeConfigAddress);
        quoteTokenManager = QuoteTokenManager(_quoteTokenManagerAddress);
        pumpFormula = PumpFormula(_pumpFormulaAddress);
        depositAndWithdraw = DepositAndWithdraw(_depositAndWithdrawAddress);

        // 根据 isTestnet 参数选择相应的地址
        if (isTestnet) {
            pancakeAddress = PANCAKE_TESTNET_ADDRESS;
            wbnbAddress = WBNB_TESTNET_ADDRESS;
            usdtAddress = USDT_TESTNET_ADDRESS;
            usdcAddress = USDC_TESTNET_ADDRESS;
            busdAddress = BUSD_TESTNET_ADDRESS;
            daiAddress = DAI_TESTNET_ADDRESS;
        } else {
            pancakeAddress = PANCAKE_MAINNET_ADDRESS;
            wbnbAddress = WBNB_MAINNET_ADDRESS;
            usdtAddress = USDT_MAINNET_ADDRESS;
            usdcAddress = USDC_MAINNET_ADDRESS;
            busdAddress = BUSD_MAINNET_ADDRESS;
            daiAddress = DAI_MAINNET_ADDRESS;
        }

        depositAndWithdraw.setFactory(address(this)); // 初始化时设置 factory
        depositAndWithdraw.setTokenAddresses(isTestnet); // 初始化时设置 WBNB 地址

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

    function permit(address baseToken) external {
        CurveInfo storage curve = curves[baseToken];
        require(curve.baseToken != address(0), "Curve does not exist for the provided baseToken");
        
        require(msg.sender == curve.creator, "Caller is not the creator of the bonding curve");

        require(!curve.isOnPancake, "Invalid parameters");

        curve.isLaunchPermitted = !curve.isLaunchPermitted;

        if (curve.isLaunchPermitted && curve.currentQuoteReserves >= curve.target) {
            curve.isOnPancake = true;
        }

        emit PermitEvent(msg.sender, baseToken, curve.quoteToken, curve.isLaunchPermitted, curve.isOnPancake);
    }

    function buyToken(
        address baseToken, 
        uint256 quoteAmount, 
        uint256 minBaseAmount  
    ) external payable {
        CurveInfo storage curve = curves[baseToken];
        
        // 状态检查：确保代币还未在 PancakeSwap 上
        require(!curve.isOnPancake, "Liquidity already on PancakeSwap");

        require(curve.isLaunchPermitted, "Token launch is not permitted");

        // 新增权限检查：确保调用者是曲线的创建者
        require(msg.sender == curve.creator, "Caller is not the creator of the bonding curve");

        if (curve.quoteToken == wbnbAddress) {
            require(msg.value == quoteAmount, "Incorrect BNB amount sent");
            (bool success, ) = wbnbAddress.call{value: quoteAmount}(
                abi.encodeWithSignature("deposit()")
            );
            require(success, "WBNB deposit failed");
        } else {
            require(IERC20(curve.quoteToken).transferFrom(msg.sender, address(this), quoteAmount), "Transfer failed");
        }

        curve.currentQuoteReserves += quoteAmount;

        uint256 fee_quote_amount = quoteAmount * curve.feeBps / 10000;
        uint256 swap_quote_amount = quoteAmount - fee_quote_amount;

        if (curve.isLaunchPermitted && curve.currentQuoteReserves >= curve.target) {
            swap_quote_amount = curve.target - curve.currentQuoteReserves;
            fee_quote_amount = (swap_quote_amount * 10000 / (10000 - curve.feeBps)) - swap_quote_amount;
            curve.isOnPancake = true;
        }

        // 滑点保护：检查接收到的基础代币数量是否低于用户期望的最小接收量
        uint256 baseAmount = pumpFormula.buy(
            curve.quoteToken,
            curve.currentBaseReserves,
            curve.currentQuoteReserves,
            quoteAmount
        );

        require(baseAmount >= minBaseAmount, "Slippage too high, minBaseAmount not met");
        require(baseAmount > 0, "Invalid base amount calculated");

        CustomToken(baseToken).mint(msg.sender, baseAmount);
        curve.currentBaseReserves += baseAmount;

        // 检查是否达到了目标，并添加流动性到 PancakeSwap
        if (curve.currentQuoteReserves >= curve.target && !curve.isOnPancake) {
            curve.isOnPancake = true;

            if (curve.quoteToken == wbnbAddress) {
                bytes memory addLiquidityETHData = abi.encodeWithSignature(
                    "addLiquidityETH(address,uint256,uint256,uint256,address,uint256)",
                    baseToken,
                    curve.currentBaseReserves,
                    0,
                    0,
                    address(this),
                    block.timestamp
                );

                (bool success, ) = pancakeAddress.call{value: curve.currentQuoteReserves}(addLiquidityETHData);
                require(success, "PancakeSwap: addLiquidityETH failed");

            } else {
                IERC20(baseToken).approve(pancakeAddress, curve.currentBaseReserves);
                IERC20(curve.quoteToken).approve(pancakeAddress, curve.currentQuoteReserves);

                bytes memory addLiquidityData = abi.encodeWithSignature(
                    "addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)",
                    baseToken,
                    curve.quoteToken,
                    curve.currentBaseReserves,
                    curve.currentQuoteReserves,
                    0,
                    0,
                    address(this),
                    block.timestamp
                );

                (bool success, ) = pancakeAddress.call(addLiquidityData);
                require(success, "PancakeSwap: addLiquidity failed");
            }

            emit PermitEvent(msg.sender, baseToken, curve.quoteToken, curve.isLaunchPermitted, curve.isOnPancake);
        }

        emit TokenPurchased(
            msg.sender, 
            baseToken, 
            quoteAmount, 
            baseAmount,
            curve.currentQuoteReserves, 
            curve.currentBaseReserves,
            block.timestamp
        );
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

        if (curve.quoteToken == wbnbAddress) {
            (bool success, ) = wbnbAddress.call(
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

    function deposit(
        string calldata orderId,
        string calldata command,
        string calldata extraInfo,
        uint8 maxIndex,
        uint8 index,
        uint256 cost,
        address mint
    ) external payable onlyOwner {
        depositAndWithdraw.deposit{value: msg.value}(orderId, command, extraInfo, maxIndex, index, cost, mint);
    }

    function deposit2(
        DepositAndWithdraw.DepositParams calldata params
    ) external payable onlyOwner {
        depositAndWithdraw.deposit2{value: msg.value}(params);
    }

    function withdraw(
        address baseToken,
        address quoteToken,
        uint256 quoteAmount,
        uint256 baseAmount,
        address payable receiver
    ) external onlyOwner {
        depositAndWithdraw.withdraw(baseToken, quoteToken, quoteAmount, baseAmount, receiver);
    }

    function withdraw2(
        string calldata orderId,
        uint256 cost,
        address mint,
        address payable receiver
    ) external onlyOwner {
        depositAndWithdraw.withdraw2(orderId, cost, mint, receiver);
    }
}