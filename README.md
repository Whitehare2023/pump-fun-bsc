# evm-pump 项目概述 

这个项目的主要目的是在区块链上实现一个基于价格曲线的带 swap 功能的代币交易系统。

最初的项目是在Solana上开发的，我们已经将其逻辑和功能一比一地复刻到Solidity中，以便在Binance Smart Chain (BSC)上运行。

项目的主要功能包括代币的创建、买卖、添加报价代币、配置管理、以及管理和维护元数据等。 

## 项目功能概述 

1. **Initialize Config**: 初始化项目的配置参数，设置初始状态。 

2. **Update Config**: 更新配置参数，修改项目的基本配置。
3. **Add Quote Token**: 添加新的报价代币，用于在价格曲线上交易。 
4. **Create Token**: 创建新的代币，配置其相关的价格曲线参数。 
5. **Buy Token**: 在价格曲线上买入代币。 
6. **Sell Token**: 在价格曲线上卖出代币。 
7. **Permit Launch**: 允许代币上线或启动交易。
8. **Withdraw Liquidity**: 提取价格曲线中的流动性，通常用于合约的清算或维护。 
9. **Deposit Token**: 向指定账户存入代币。
10. **Withdraw Token**: 从指定账户提取代币。
11. **Manage Metadata**: 管理代币的元数据，例如名称、符号和URI。  



## 文件和功能对照 

### Solana 项目文件 

#### 1.**lib.rs**:    

- **功能**: 项目入口，定义了所有公开的函数和逻辑。   
- **Solidity 对应文件**: `add_quote_token.sol`, `buy.sol`, `create.sol`, `deposit.sol`, `deposit2.sol`, `initialize_config.sol`, `permit.sol`, `sell.sol`, `update_config.sol`, `withdraw.sol`, `withdraw2.sol` 
- **Solidity 实现**: 在每个Solidity文件中，我们实现了相同的逻辑。每个函数都有对应的合约和处理函数。每个文件处理特定的业务逻辑（例如，买入、卖出、创建代币等）。



#### 2.**state.rs**:

- **功能**: 定义项目中使用的结构体和事件。

- **Solidity 对应文件**: `state.sol`  

- **Solidity 实现**: 直接将结构体和事件转换为Solidity中的`struct`和`event`。例如，`ProgramConfig`、`CurveInfoPart1`和`CurveInfoPart2`等结构体，`CreateEventPart1`等事件。

#### 3. **formula.rs**: 

- **功能**: 代币买卖的公式实现，用于计算价格曲线的代币数量和费用。

- **Solidity 对应文件**: `formula.sol`  
- **Solidity 实现**: 使用Solidity数学库来精确地计算买卖价格。通过函数`buy`和`sell`来计算用户的买入和卖出代币数量。 

#### 4.**token.rs**:  

- **功能**: 处理代币相关的操作，如创建和销毁代币账户。
- **Solidity 对应文件**: `token.sol`   
- **Solidity 实现**: 使用OpenZeppelin的ERC20合约和工具来实现代币的创建和销毁。包括代币转账、安全检查等功能。



#### 5. mpl.rs

- **功能**: 处理元数据管理，允许更新和获取代币的元数据。

- **Solidity 对应文件**: `mpl.sol`  
- **Solidity 实现**: 使用Solidity的映射和结构体来存储和管理元数据，通过函数来创建和获取代币的元数据。

#### 6. **error.rs**: 

- 功能**: 错误码定义，用于合约逻辑中的错误处理。  **
- **Solidity 对应文件**: `error.sol` 
- **Solidity 实现**: 直接使用Solidity的`require`和自定义错误消息来实现相同的功能。例如，`require(condition, "Error message")`。

### 7.**constants.rs**:  

- 功能**: 常量定义，用于配置和控制合约逻辑。**
- Solidity 对应文件**: `constants.sol` **
- **Solidity 实现**: 将常量直接定义在Solidity文件中，使用`constant`关键字。例如，`uint8 constant UPDATE_CONFIG_ACTION_ADMIN = 1;`。

#### 8. **utils/**:   - **功能**: 实用工具函数，用于处理与账户、代币等相关的辅助操作。   - **Solidity 对应文件**: `utils.sol` (未单独列出，但可以集成到其他文件中)   - **Solidity 实现**: 在需要的文件中实现类似的辅助函数。包括创建代币账户、转账操作等。

## Raydium 换 Pancake 的实现

- **Solana 上的 Raydium**: Solana 项目使用 Raydium 作为流动性池和 AMM（自动做市商）。

- **BSC 上的 Pancake**: 在Solidity中，我们替换了与Raydium相关的所有逻辑，改用PancakeSwap的接口和合约。例如，替换`is_on_raydium`为`isOnPancake`，并更新所有与流动性相关的操作。

#### 具体更改：

 - 将所有`Raydium`相关函数和变量名称替换为`Pancake`。 - 使用PancakeSwap的AMM接口和流动性池函数替换Raydium的相应接口。 - 所有基于Solana的流动性操作改为基于BSC的流动性操作。 ## Solana 代币换 BSC 代币的实现 - **Solana SPL 代币**: Solana 使用其本地的SPL代币标准。

 - **BSC ERC20 代币**: 在Solidity中，我们使用OpenZeppelin提供的ERC20标准来实现相同的代币功能。BSC上的代币通常遵循ERC20标准，因此需要对所有SPL代币操作进行等价转换。

####  具体更改：

 - 将Solana上的SPL代币接口替换为BSC上的ERC20代币接口。

 - 使用OpenZeppelin的ERC20工具库来进行代币转账、授权、铸币和销毁等操作。 - 调整代币的精度和格式，以适应BSC上的代币标准。
