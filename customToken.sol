// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "./openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "./openzeppelin-contracts/contracts/access/Ownable.sol";

contract CustomToken is ERC20, ERC20Burnable, Ownable {
    string private _uri; // URI 存储
    bool private initialized = false; // 初始化标记
    uint8 private _decimals = 6; // 自定义小数位数
    bool private factorySet = false; // 标记 factory 是否已经设置

    address public factory; // TokenFactory 合约地址
    address public operations; // TokenOperations 合约地址
    address public factoryOwner; // TokenFactory 的 owner 地址

    // 额外添加的状态变量
    uint256 private _target;
    uint256 private _initVirtualQuoteReserves;
    uint256 private _initVirtualBaseReserves;
    uint256 private _feeBps;
    uint256 private _createFee;
    bool private _isLaunchPermitted;

    event Debug(string message); // 用于调试的事件
    event DebugValue(string message, uint256 value); // 调试数值事件

    // 使用内部变量来存储 name 和 symbol
    string private _name;
    string private _symbol;

    constructor() ERC20("", "") Ownable(msg.sender) { 
        _decimals = 6; // 默认设置为 6 位小数
        initialized = false; // 初始化标记为 false
        factorySet = false; // 初始化时标记 factory 未设置
        emit Debug("CustomToken Constructor Called"); // 调试信息
    }

    // 重写 decimals 函数
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    // 重写 name 函数以返回代币的名称
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    // 重写 symbol 函数以返回代币的符号
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    // 返回 URI
    function tokenURI() public view returns (string memory) {
        return _uri;
    }

    // 初始化方法，用于设置代币的基本信息
    function initialize(
        string memory tokenName,
        string memory tokenSymbol,
        address owner,
        string memory uri,
        uint256 initialSupply,
        uint256 target,
        uint256 initVirtualQuoteReserves,
        uint256 initVirtualBaseReserves,
        uint256 feeBps,
        uint256 createFee,
        bool isLaunchPermitted
    ) external {
        require(!initialized, "Already initialized"); // 确保只初始化一次
        emit Debug("Initialization step: check not initialized");

        require(bytes(tokenName).length > 0, "Token name is required"); // 确保代币名称不为空
        emit Debug("Initialization step: check token name");

        require(bytes(tokenSymbol).length > 0, "Token symbol is required"); // 确保代币符号不为空
        emit Debug("Initialization step: check token symbol");

        require(owner != address(0), "Owner address is invalid"); // 确保所有者地址有效
        emit Debug("Initialization step: check owner address");

        require(bytes(uri).length > 0, "Token URI is required"); // 确保 URI 不为空
        emit Debug("Initialization step: check token URI");

        // 设置 name 和 symbol
        _name = tokenName;
        _symbol = tokenSymbol;
        _uri = uri; // 设置 URI
        emit Debug("Initialization step: set name, symbol, and URI");

        // 设置合约的拥有者
        _transferOwnership(owner);
        emit Debug("Initialization step: transfer ownership");

        // 设置为已初始化
        initialized = true; // 设置初始化状态
        emit Debug("Initialization step: set initialized to true");

        // 直接使用传入的初始供应量铸造代币
        _mint(owner, initialSupply);
        emit Debug("Initialization step: mint initial supply");

        // 设置其他初始化参数
        _target = target;
        _initVirtualQuoteReserves = initVirtualQuoteReserves;
        _initVirtualBaseReserves = initVirtualBaseReserves;
        _feeBps = feeBps;
        _createFee = createFee;
        _isLaunchPermitted = isLaunchPermitted;
        emit Debug("Initialization step: set additional parameters");

        emit Debug("Token initialized successfully"); // 调试信息
    }

    // 设置 factory 和 factoryOwner 的地址
    function setFactory(address _factory) external {
        require(!factorySet, "Factory already set"); // 确保只设置一次
        require(_factory != address(0), "Factory address is invalid");
        factory = _factory;
        factoryOwner = Ownable(factory).owner();
        factorySet = true; // 设置 factory 已经设置
    }

    // 设置 operations 地址
    function setOperations(address _operations) external {
        require(_operations != address(0), "Operations address is invalid");
        operations = _operations;
    }

    // 自定义修饰符，确保只有 factory 或 operations 地址能调用
    modifier onlyFactoryOrOperations() {
        require(msg.sender == factory || msg.sender == operations, "Caller is not the factory or operations");
        _;
    }

    // 修改后的 mint 方法，只允许 factory 或 operations 调用
    function mint(address to, uint256 amount) external onlyFactoryOrOperations {
        require(to != address(0), "Mint to the zero address"); // 确保目标地址不为空
        require(amount > 0, "Mint amount must be greater than zero"); // 确保 mint 数量大于零
        require(initialized, "Token is not initialized"); // 确保合约已被初始化
        emit Debug("Mint function called"); // 调试信息
        _mint(to, amount);
        emit Debug("Mint function succeeded"); // 调试信息
    }

    // 设置代币精度
    function setDecimals(uint8 newDecimals) external {
        _decimals = newDecimals;
        emit DebugValue("Decimals updated to", newDecimals);
    }
}
