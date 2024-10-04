// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "./openzeppelin-contracts/contracts/access/Ownable.sol";

contract CustomToken is ERC20, Ownable {
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

    // 授权映射
    mapping(address => mapping(address => uint256)) private _allowances;

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
        uint8 tokenDecimals,  // 重命名为 tokenDecimals
        bool isLaunchPermitted
    ) external {
        require(!initialized, "Already initialized"); // 确保只初始化一次

        // 设置 name 和 symbol
        _name = tokenName;
        _symbol = tokenSymbol;
        _uri = uri; // 设置 URI

        // 设置合约的拥有者
        _transferOwnership(owner);

        // 设置为已初始化
        initialized = true; // 设置初始化状态

        // 设置代币精度
        _decimals = tokenDecimals; // 使用 tokenDecimals 来设置代币的精度

        // 不进行任何精度处理，用户输入的值直接用作代币单位
        _mint(owner, initialSupply); // 按照原始输入铸造代币

        // 设置其他初始化参数
        _target = target;
        _initVirtualQuoteReserves = initVirtualQuoteReserves;
        _initVirtualBaseReserves = initVirtualBaseReserves;
        _feeBps = feeBps;
        _isLaunchPermitted = isLaunchPermitted;
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
        
        // 不进行精度调整，直接按照用户输入的数量铸造
        _mint(to, amount);
    }

    // 设置代币精度
    function setDecimals(uint8 newDecimals) external  {
        _decimals = newDecimals;
    }

    // 重写 approve 方法，不进行精度转换
    function approveToken(address owner, address spender, uint256 amount) public returns (bool) {
        require(spender != address(0), "approve to the zero address");
        require(owner != address(0), "owner is the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
        return true;
    }

    // 重写 allowance 方法，返回用户输入的原始代币单位
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    // 重写 transferFrom 方法，直接处理用户输入的原始代币单位
    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        require(from != address(0), "transfer from the zero address");
        require(to != address(0), "transfer to the zero address");

        require(balanceOf(from) >= amount, "transfer amount exceeds balance");
        require(_allowances[from][msg.sender] >= amount, "transfer amount exceeds allowance");

        _allowances[from][msg.sender] -= amount; // 更新授权额度
        _transfer(from, to, amount); // 直接转移原始单位的代币
        return true;
    }
}
