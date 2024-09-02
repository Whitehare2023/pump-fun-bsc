// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./openzeppelin-contracts/contracts/access/Ownable.sol";
import "./customToken.sol"; // 引入 CustomToken 实现
import "./openzeppelin-contracts/contracts/proxy/Clones.sol"; // 使用 OpenZeppelin Clones 库

contract TokenFactory is Ownable {
    address public implementation; // CustomToken 的实现地址
    address public initialOwner;

    event TokenCreated(address indexed tokenAddress, string name, string symbol, uint256 initialSupply, address owner);
    event Debug(string message, address addr); // 调试信息
    event DebugInitializeParams(string name, string symbol, address user, string uri); // 初始化参数调试信息
    event DebugCloneResult(address cloneAddress); // 克隆结果调试信息
    event DebugCloneError(string reason); // 克隆错误信息

    struct TokenParams {
        string name;
        string symbol;
        string uri;
        uint256 initialSupply;
        uint256 target;
        uint256 initVirtualQuoteReserves;
        uint256 initVirtualBaseReserves;
        uint256 feeBps;
        uint256 createFee;
        bool isLaunchPermitted;
    }

    constructor(address _implementation, address _initialOwner) Ownable(_initialOwner) {  // 使用传入的 _initialOwner 初始化 Ownable
        implementation = _implementation; // 设置 CustomToken 的实现合约地址
        initialOwner = _initialOwner;
        emit Debug("TokenFactory Constructor Called", address(this)); // 调试信息
    }

    function createToken(TokenParams memory params) external onlyOwner returns (address) {
        // 自定义权限检查：确保调用者是TokenFactory的所有者
        require(bytes(params.name).length > 0, "Token name is required");
        require(bytes(params.symbol).length > 0, "Token symbol is required");
        require(bytes(params.uri).length > 0, "Token URI is required");
        require(params.initialSupply > 0, "Initial supply must be greater than zero");

        // 克隆 CustomToken 实例
        address cloneInstance = Clones.clone(implementation); // 使用 OpenZeppelin 的 Clones 库
        if (cloneInstance == address(0)) {
            emit DebugCloneError("Clone creation failed");
            revert("Clone creation failed");
        }

        emit Debug("Clone Instance Created", cloneInstance);
        emit DebugCloneResult(cloneInstance);

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
                params.createFee,                // uint256 createFee
                params.isLaunchPermitted         // bool isLaunchPermitted
            )
        );

        if (!success) {
            // 捕获初始化失败的错误信息
            emit Debug("Initialization failed", cloneInstance);
            if (data.length > 0) {
                revert(string(data));
            } else {
                revert("Unknown error during initialization");
            }
        }

        emit TokenCreated(cloneInstance, params.name, params.symbol, params.initialSupply, initialOwner);
        return cloneInstance;
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
