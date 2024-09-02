// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./openzeppelin-contracts/contracts/access/Ownable.sol";
import "./openzeppelin-contracts/contracts/proxy/Clones.sol"; // 使用 OpenZeppelin Clones 库
import "./customToken.sol"; // 引入 CustomToken 实现
import "./initialize_config.sol"; // 导入 InitializeConfig 合约定义

contract TokenFactory is Ownable {
    address public implementation; // CustomToken 的实现地址
    address public initialOwner;
    InitializeConfig public initializeConfig; // initialize_config 合约实例

    // 从 initialize_config 获取的状态变量
    uint256 public baseMinSupply;
    uint256 public baseMaxSupply;
    uint256 public baseMinFeeRate;
    uint256 public baseMaxFeeRate;
    uint256 public createFee; // 确保以 wei 为单位
    address public adminAddress;
    address public platformAddress;
    address public feeRecipientAccount;
    address public depositAccount;

    // 记录每个代币的地址
    mapping(uint256 => address) public tokenAddresses;
    // 记录创建的代币数量
    uint256 public tokenIndex;

    event TokenCreated(address indexed tokenAddress, string name, string symbol, uint256 initialSupply, address owner);
    event Debug(string message, address addr); // 调试信息
    event DebugInitializeParams(string name, string symbol, address user, string uri); // 初始化参数调试信息
    event DebugCloneResult(address cloneAddress); // 克隆结果调试信息
    event DebugCloneError(string reason); // 克隆错误信息
    event DebugValue(string message, uint256 value); // 调试数值

    struct TokenParams {
        string name;
        string symbol;
        string uri;
        uint256 initialSupply;
        uint256 target;
        uint256 initVirtualQuoteReserves;
        uint256 initVirtualBaseReserves;
        uint256 feeBps;
        bool isLaunchPermitted;
    }

    constructor(address _implementation, address _initialOwner, address _initializeConfigAddress) Ownable(_initialOwner) {
        implementation = _implementation; // 设置 CustomToken 的实现合约地址
        initialOwner = _initialOwner;
        initializeConfig = InitializeConfig(_initializeConfigAddress); // 设置 initialize_config 合约实例
        updateConfig(); // 初始化时获取配置参数
        emit Debug("TokenFactory Constructor Called", address(this)); // 调试信息
    }

    // 更新配置函数，从 initialize_config 合约获取参数
    function updateConfig() public {
        (
            , // isInitialized
            , // bump
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

        // 更新状态变量
        baseMinSupply = _baseMinSupply;  
        baseMaxSupply = _baseMaxSupply;  
        createFee = _createFee; // 已经以 wei 为单位获取
        feeRecipientAccount = _feeRecipientAccount;
        baseMinFeeRate = _baseMinFeeRate;
        baseMaxFeeRate = _baseMaxFeeRate;
        adminAddress = _admin;
        platformAddress = _platform;
        depositAccount = _depositAccount;

        // 使用已声明的事件来调试
        emit DebugValue("Updated baseMinFeeRate", baseMinFeeRate);
        emit DebugValue("Updated baseMaxFeeRate", baseMaxFeeRate);
        emit DebugValue("Updated baseMinSupply", baseMinSupply);
        emit DebugValue("Updated baseMaxSupply", baseMaxSupply);
        emit DebugValue("Updated createFee", createFee);
        emit Debug("Updated feeRecipientAccount", feeRecipientAccount);
    }

    function createToken(TokenParams memory params) external payable onlyOwner returns (address) {
        // 在创建代币之前，确保使用最新的配置
        updateConfig();

        // 检查支付的费用是否足够
        emit DebugValue("Provided msg.value", msg.value);
        emit DebugValue("Required createFee", createFee);

        require(msg.value == createFee, "Insufficient creation fee"); // 精确匹配 msg.value 和 createFee
        require(bytes(params.name).length > 0, "Token name is required");
        require(bytes(params.symbol).length > 0, "Token symbol is required");
        require(bytes(params.uri).length > 0, "Token URI is required");
        require(params.initialSupply >= baseMinSupply && params.initialSupply <= baseMaxSupply, "Initial supply out of range");
        require(params.feeBps >= baseMinFeeRate && params.feeBps <= baseMaxFeeRate, "Fee Bps out of range");

        // 转移创建费用到指定的接收地址
        (bool feeTransferSuccess, ) = payable(feeRecipientAccount).call{value: createFee}("");
        require(feeTransferSuccess, "Fee transfer failed");

        // 克隆 CustomToken 实例
        address cloneInstance = Clones.clone(implementation); // 使用 OpenZeppelin 的 Clones 库
        if (cloneInstance == address(0)) {
            emit DebugCloneError("Clone creation failed");
            revert("Clone creation failed");
        }

        emit Debug("Clone Instance Created", cloneInstance);
        emit DebugCloneResult(cloneInstance);

        // 调用单独的函数来初始化克隆实例
        initializeToken(cloneInstance, params);

        // 记录新创建的代币地址并更新计数器
        tokenAddresses[tokenIndex] = cloneInstance;
        tokenIndex++;

        emit TokenCreated(cloneInstance, params.name, params.symbol, params.initialSupply, initialOwner);
        return cloneInstance;
    }

    // 将初始化逻辑分离到单独的函数中，减少 createToken 函数的堆栈使用
    function initializeToken(address cloneInstance, TokenParams memory params) internal {
        emit DebugInitializeParams(params.name, params.symbol, initialOwner, params.uri);

        // 初始化新创建的实例
        (bool success, bytes memory data) = cloneInstance.call(
            abi.encodeWithSignature(
                "initialize(string,string,address,string,uint256,uint256,uint256,uint256,uint256,uint256,bool)",
                params.name,                     // string tokenName
                params.symbol,                   // string tokenSymbol
                initialOwner,                    // address owner (用户地址)
                params.uri,                      // string uri
                params.initialSupply,            // uint256 initialSupply
                params.target,                   // uint256 target
                params.initVirtualQuoteReserves, // uint256 initVirtualQuoteReserves
                params.initVirtualBaseReserves,  // uint256 initVirtualBaseReserves
                params.feeBps,                   // uint256 feeBps
                createFee,                       // uint256 createFee
                params.isLaunchPermitted         // bool isLaunchPermitted
            )
        );

        if (!success) {
            // 捕获初始化失败的错误信息
            emit Debug("Initialization failed", cloneInstance);
            if (data.length > 0) {
                emit DebugCloneError(string(data));  // 打印错误信息
                revert(string(data));
            } else {
                revert("Unknown error during initialization");
            }
        }
    }

    // 获取所有代币地址的函数
    function getAllTokenAddresses() public view returns (address[] memory) {
        address[] memory addresses = new address[](tokenIndex);
        for (uint256 i = 0; i < tokenIndex; i++) {
            addresses[i] = tokenAddresses[i];
        }
        return addresses;
    }

    function clone(address target) internal returns (address result) {
        bytes20 targetBytes = bytes20(target); 
        assembly {
            let clone_ptr := mload(0x40)
            mstore(clone_ptr, 0x3d602d80600a3d3981f3) // creation code
            mstore(add(clone_ptr, 0x14), targetBytes)
            mstore(add(clone_ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf3) // runtime code
            result := create(0, clone_ptr, 0x37)
        }
        require(result != address(0), "Clone failed");
        emit Debug("Clone Function Executed", result);
    }
}
