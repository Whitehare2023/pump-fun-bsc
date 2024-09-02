// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "./openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "./openzeppelin-contracts/contracts/access/Ownable.sol";

contract CustomToken is ERC20, ERC20Burnable, Ownable {
    string private _uri; // URI 存储
    bool private initialized; // 初始化标记
    uint8 private _decimals; // 自定义小数位数

    address private factory; // TokenFactory 合约地址
    address private factoryOwner; // TokenFactory 的 owner 地址

    // 额外添加的状态变量
    uint256 private _target;
    uint256 private _initVirtualQuoteReserves;
    uint256 private _initVirtualBaseReserves;
    uint256 private _feeBps;
    uint256 private _createFee;
    bool private _isLaunchPermitted;

    event Debug(string message); // 用于调试的事件

    // 使用内部变量来存储 name 和 symbol
    string private _name;
    string private _symbol;

    constructor() ERC20("", "") Ownable(msg.sender) { 
        _decimals = 6; // 默认设置为 6 位小数
        initialized = false; // 初始化标记为 false
        emit Debug("CustomToken Constructor Called"); // 调试信息
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

        require(bytes(uri).length > 0, "Token URI is required"); // 确保URI不为空
        emit Debug("Initialization step: check token URI");

        // 设置 name 和 symbol
        _name = tokenName;
        _symbol = tokenSymbol;
        emit Debug("Initialization step: set name and symbol");

        // 设置合约的拥有者
        _transferOwnership(owner);
        emit Debug("Initialization step: transfer ownership");

        // 设置代币的 URI
        _uri = uri;
        emit Debug("Initialization step: set URI");

        // 设置为已初始化
        initialized = true;
        emit Debug("Initialization step: set initialized to true");

        // 铸造初始供应量的代币
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
    function setFactory(address _factory) external onlyOwner {
        require(_factory != address(0), "Factory address is invalid");
        factory = _factory;
        factoryOwner = Ownable(factory).owner();
    }

    // 自定义修饰符，确保只有传入的 owner 地址能调用
    modifier onlyFactoryOwner(address owner) {
        require(owner == factoryOwner, "Caller is not the owner of the factory");
        _;
    }

    // 添加一个 public 的 mint 方法，允许工厂合约进行代币 mint
    function mint(address to, uint256 amount, address owner) external onlyFactoryOwner(owner) {
        require(to != address(0), "Mint to the zero address"); // 确保目标地址不为空
        require(amount > 0, "Mint amount must be greater than zero"); // 确保 mint 数量大于零
        require(initialized, "Token is not initialized"); // 确保合约已被初始化
        emit Debug("Mint function called"); // 调试信息
        _mint(to, amount);
        emit Debug("Mint function succeeded"); // 调试信息
    }
}