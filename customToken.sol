// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract CustomToken is IERC20 {
    string private _name;
    string private _symbol;
    uint8 private _decimals;
    uint256 private _totalSupply;
    string private _uri; // URI 存储

    // 保留 balance 和 allowance 的映射
    mapping(address => uint256) private _balances; // 用户余额
    mapping(address => mapping(address => uint256)) private _allowances; // 授权映射

    bool private initialized = false; // 初始化标记
    bool private factorySet = false; // 标记 factory 是否已经设置

    address public factory; // TokenFactory 合约地址
    address public operations; // TokenOperations 合约地址

    // 额外添加的状态变量
    uint256 private _target;
    uint256 private _initVirtualQuoteReserves;
    uint256 private _initVirtualBaseReserves;
    uint256 private _feeBps;
    uint256 private _createFee;
    bool private _isLaunchPermitted;

    event Debug(string message);
    event DebugValue(string message, uint256 value);

    // 初始化函数
    function initialize(
        string memory tokenName,
        string memory tokenSymbol,
        address _operations,
        string memory uri,
        uint256 initialSupply,
        uint256 target,
        uint256 initVirtualQuoteReserves,
        uint256 initVirtualBaseReserves,
        uint256 feeBps,
        uint8 tokenDecimals,  
        bool isLaunchPermitted
    ) external {
        require(!initialized, "Already initialized"); // 确保只在 createToken 函数里初始化一次，没有其他调用机会

        _name = tokenName;
        _symbol = tokenSymbol;
        _uri = uri;

        _decimals = tokenDecimals;

        _target = target;
        _initVirtualQuoteReserves = initVirtualQuoteReserves;
        _initVirtualBaseReserves = initVirtualBaseReserves;
        _feeBps = feeBps;
        _isLaunchPermitted = isLaunchPermitted;

        initialized = true; // 标记已初始化

        // 使用 mint 方法将代币 mint 到 operations 地址（池子地址）
        mint(_operations, initialSupply);
    }

    // 代币名称
    function name() public view returns (string memory) {
        return _name;
    }

    // 代币符号
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    // 代币小数位数
    function decimals() public view returns (uint8) {
        return _decimals;
    }

    // 代币总供应量
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    // 查看余额
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    // 查看授权额度
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    // 转账函数
    function transfer(address to, uint256 amount) public override returns (bool) {
        require(to != address(0), "ERC20: transfer to the zero address");
        require(_balances[msg.sender] >= amount, "ERC20: transfer amount exceeds balance");

        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    // **仅允许 owner 执行授权操作**
    function approve(address spender, uint256 amount) public override returns (bool) {
        require(spender != address(0), "ERC20: approve to the zero address");
        // require(msg.sender == _owner, "Only owner can approve");

        _allowances[msg.sender][spender] = amount;  // 保存授权额度
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    // 执行转账并减少授权额度
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");

        _balances[from] -= amount;
        _balances[to] += amount;
        _allowances[from][msg.sender] -= amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) internal {
        require(to != address(0), "Mint to the zero address");
        require(amount > 0, "Mint amount must be greater than zero");
        require(initialized, "Token is not initialized");

        _balances[to] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
}
