// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ITraderRegistry} from "../interfaces/ITraderRegistry.sol";
import {ExecutorValidation} from "../libraries/ExecutorValidation.sol";

/**
 * @title ExecutorOwner
 * @notice Abstract contract containing all owner/admin functionality for the Executor
 * @dev Separates owner concerns from core trading logic
 */
abstract contract ExecutorOwner is Ownable {
    using SafeERC20 for IERC20;

    uint16 internal constant MAX_FEE_BPS = 1_000; // 10%

    ITraderRegistry public traderRegistry;
    uint256 public executorFee;
    mapping(address => bool) public whitelistedTokens;

    event TraderRegistryUpdated(address indexed newRegistry, address indexed updater);
    event ExecutorFeeUpdated(uint256 newFeeBps, address indexed updater);
    event TokenWhitelisted(address indexed token, address indexed updater);
    event TokenRemovedFromWhitelist(address indexed token, address indexed updater);

    error InvalidFee();
    error NotAContract();

    constructor(address initialOwner) Ownable(initialOwner) {}

    function updateTraderRegistry(address newRegistry) external onlyOwner {
        if (newRegistry == address(0)) revert ExecutorValidation.ZeroAddress();
        traderRegistry = ITraderRegistry(newRegistry);
        emit TraderRegistryUpdated(newRegistry, msg.sender);
    }

    function updateExecutorFee(uint256 newFee) external onlyOwner {
        if (newFee >= MAX_FEE_BPS) revert InvalidFee();
        executorFee = newFee;
        emit ExecutorFeeUpdated(newFee, msg.sender);
    }

    function addWhitelistedToken(address token) external onlyOwner {
        if (token == address(0)) revert ExecutorValidation.ZeroAddress();
        if (token.code.length == 0) revert NotAContract();
        whitelistedTokens[token] = true;
        emit TokenWhitelisted(token, msg.sender);
    }

    function removeWhitelistedToken(address token) external onlyOwner {
        whitelistedTokens[token] = false;
        emit TokenRemovedFromWhitelist(token, msg.sender);
    }

    function addWhitelistedTokens(address[] calldata tokens) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            if (token == address(0)) revert ExecutorValidation.ZeroAddress();
            if (token.code.length == 0) revert NotAContract();
            whitelistedTokens[token] = true;
            emit TokenWhitelisted(token, msg.sender);
        }
    }

    function emergencyWithdrawToken(address token, address to) external onlyOwner {
        if (token == address(0)) {
            uint256 bal = address(this).balance;
            (bool sent,) = to.call{value: bal}("");
            require(sent, "withdraw ETH failed");
        } else {
            IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));
        }
    }
}
