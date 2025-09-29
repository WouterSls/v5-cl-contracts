// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {EIP712} from "../lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

import {ISignatureTransfer} from "../lib/permit2/src/interfaces/ISignatureTransfer.sol";

import {ITrader} from "./interfaces/ITrader.sol";
import {ITraderRegistry} from "./interfaces/ITraderRegistry.sol";

import {ExecutorValidation} from "./libraries/ExecutorValidation.sol";

/**
 * @title Executor
 * @notice Executes signed off-chain orders with validation libraries
 * @dev Clean separation of concerns with modular validation
 */
contract Executor is EIP712, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    string private constant NAME = "EVM Trading Engine";
    string private constant VERSION = "1";

    uint16 internal constant FEE_DENOMINATOR = 10_000;
    uint16 internal constant MAX_FEE_BPS = 1_000; // 10% cap

    //address private constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public immutable PERMIT2;

    ITraderRegistry public traderRegistry;
    uint256 public executorFee;

    mapping(address => mapping(uint256 => bool)) public usedNonce;

    event TraderRegistryUpdated(address indexed newRegistry, address indexed updater);
    event ExecutorFeeUpdated(uint256 newFeeBps, address indexed updater);
    event ExecutorTipped(address indexed recipient, uint256 amount);
    event TradeExecuted(address indexed maker, address indexed trader, uint256 amountIn, uint256 amountOut, uint256 amountTipped);

    error InvalidTrader();
    error CallFailed();
    error InvalidRouter();
    error InsufficientOutput();
    error InvalidFee();

    constructor(address _permit2, address initialOwner) EIP712(NAME, VERSION) Ownable(initialOwner) {
        PERMIT2 = _permit2;
    }

    /**
     * @notice Execute a signed off-chain trade using modular validation
     * @param trade the trade to execute
     * @param routeData Route information for trade execution
     */
    function executeTrade(
        ExecutorValidation.Trade calldata trade,
        ExecutorValidation.RouteData calldata routeData
    ) external nonReentrant {
        ExecutorValidation.validateInputsAndBusinessLogic(trade, routeData, usedNonce);
        ExecutorValidation.validateSignatures(trade, _domainSeparatorV4());
        ExecutorValidation.TradeType tradeType = ExecutorValidation.determineTradeType(trade, routeData);

        ITrader.TraderInfo memory traderInfo = traderRegistry.getTrader(routeData.protocol);
        ExecutorValidation.validateTrader(routeData, traderInfo);

        usedNonce[trade.orderHash.maker][trade.orderHash.nonce] = true;

        ITrader.TradeParameters memory tradeParameters = ITrader.TradeParameters({
            tokenIn: trade.orderHash.inputToken,
            amountIn: trade.orderHash.inputAmount,
            tokenOut: trade.orderHash.outputToken,
            amountOutMin: trade.orderHash.minAmountOut,
            expiry: trade.orderHash.expiry,
            tradeType: tradeType,
            routeData: routeData
        });

       _transferPermittedToTrader(trade, traderInfo.implementation);

        uint256 amountOut = ITrader(traderInfo.implementation).trade(tradeParameters);

        if (amountOut < trade.orderHash.minAmountOut) revert InsufficientOutput();

        uint256 remainingAmount = _tipExecutor(trade.orderHash.outputToken, amountOut, tradeType);
        uint256 tippedAmount = amountOut - remainingAmount;

        _transferToMaker(trade.orderHash.maker, trade.orderHash.outputToken, remainingAmount, tradeType);

        emit TradeExecuted(trade.orderHash.maker, traderInfo.implementation, trade.orderHash.inputAmount, remainingAmount, tippedAmount);
    }

    function cancelNonce(uint256 nonce) external {
        usedNonce[msg.sender][nonce] = true;
    }

    function updateTraderRegistry(address newRegistry) external onlyOwner {
        traderRegistry = ITraderRegistry(newRegistry);
        address updater = msg.sender;
        emit TraderRegistryUpdated(newRegistry, updater);
    }

    function updateExecutorFee(uint256 newFee) external onlyOwner {
        if (newFee >= MAX_FEE_BPS) revert InvalidFee();
        executorFee = newFee;
        emit ExecutorFeeUpdated(newFee, msg.sender);
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

    function _transferPermittedToTrader(ExecutorValidation.Trade calldata trade, address trader) internal {
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({
                token: trade.permitHash.permitted.token,
                amount: trade.permitHash.permitted.amount
            }),
            nonce: trade.permitHash.nonce,
            deadline: trade.permitHash.deadline
        });

        ISignatureTransfer.SignatureTransferDetails memory transferDetails  = ISignatureTransfer.SignatureTransferDetails({
            to: trader,
            requestedAmount: trade.orderHash.inputAmount
        });

        ISignatureTransfer(PERMIT2).permitTransferFrom(
            permit,
            transferDetails,
            trade.orderHash.maker, 
            trade.permitSignature
        );
    }

    function _tipExecutor(address token, uint256 amountOut,  ExecutorValidation.TradeType tradeType) internal returns (uint256) {
        if (executorFee == 0) return amountOut;

        uint256 feeAmount = (amountOut * executorFee) / FEE_DENOMINATOR;
        if (feeAmount == 0) return amountOut;

        address recipient = msg.sender;

        if (tradeType == ExecutorValidation.TradeType.TOKEN_INPUT_ETH_OUTPUT) {
            (bool sent,) = recipient.call{value: feeAmount}("");
            require(sent, "tip ETH failed");
        } else {
            IERC20(token).safeTransfer(recipient, feeAmount);
        }

        return amountOut - feeAmount;
    }

    function _transferToMaker(address maker, address token, uint256 amount, ExecutorValidation.TradeType tradeType) internal {
        if (tradeType == ExecutorValidation.TradeType.TOKEN_INPUT_ETH_OUTPUT) {
            (bool sent,) = maker.call{value: amount}("");
            require(sent, "tip ETH failed");
        } else {
            IERC20(token).safeTransfer(maker, amount);
        }
    }

    receive() external payable {}
}

