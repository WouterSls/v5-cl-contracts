// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ISignatureTransfer} from "../lib/permit2/src/interfaces/ISignatureTransfer.sol";

import {ITrader} from "./interfaces/ITrader.sol";

import {ExecutorValidation} from "./libraries/ExecutorValidation.sol";
import {ExecutorOwner} from "./base/ExecutorOwner.sol";

/**
 * @title Executor
 * @notice Executes signed off-chain orders with validation libraries
 * @dev Clean separation of concerns with modular validation
 */
contract Executor is ReentrancyGuard, ExecutorOwner {
    using SafeERC20 for IERC20;

    uint16 internal constant FEE_DENOMINATOR = 10_000;

    address public immutable PERMIT2;

    event ExecutorTipped(address indexed recipient, uint256 amount);
    event TradeExecuted(
        address indexed maker,
        address indexed inputToken,
        address indexed outputToken,
        string traderStrat,
        uint256 amountIn,
        uint256 amountOut,
        uint256 amountTipped
    );

    error InvalidTrader();
    error CallFailed();
    error InvalidRouter();
    error InsufficientOutput();
    error InvalidToken();
    error UnauthorizedETHSender();

    constructor(address _permit2, address initialOwner, address[] memory initialWhitelistedTokens)
        ExecutorOwner(initialOwner)
    {
        PERMIT2 = _permit2;

        for (uint256 i = 0; i < initialWhitelistedTokens.length; i++) {
            whitelistedTokens[initialWhitelistedTokens[i]] = true;
        }
    }

    /**
     * @notice Execute a signed off-chain trade using modular validation
     * @param trade the trade to execute
     * @param routeData Route information for trade execution
     */
    function executeTrade(ExecutorValidation.Trade calldata trade, ExecutorValidation.RouteData calldata routeData)
        external
        nonReentrant
    {
        ExecutorValidation.validateInputsAndBusinessLogic(trade, msg.sender);
        ExecutorValidation.validateRouteData(trade.order, routeData, whitelistedTokens);

        ITrader.TraderInfo memory traderInfo = traderRegistry.getTrader(routeData.protocol);
        ExecutorValidation.validateTrader(routeData, traderInfo);

        address trader = msg.sender;
        _transferPermittedWitnessToTrader(trade, trader);

        /**
         *
         * ExecutorValidation.TradeType tradeType = ExecutorValidation.determineTradeType(routeData);
         * ITrader.TradeParameters memory tradeParameters = ITrader.TradeParameters({
         *         amountIn: trade.order.inputAmount,
         *         amountOutMin: trade.order.minAmountOut,
         *         expiry: trade.order.expiry,
         *         tradeType: tradeType,
         *         routeData: routeData
         *     });
         *
         *     uint256 amountOut = ITrader(traderInfo.implementation).trade(tradeParameters);
         *
         *     if (amountOut < trade.order.minAmountOut) revert InsufficientOutput();
         *
         *     uint256 remainingAmount = _tipExecutor(trade.orderHash.outputToken, amountOut, tradeType);
         *     uint256 tippedAmount = amountOut - remainingAmount;
         *
         *     _transferToMaker(trade.orderHash.maker, trade.orderHash.outputToken, remainingAmount, tradeType);
         *
         *     emit TradeExecuted(
         *         trade.orderHash.maker, traderInfo.implementation, trade.orderHash.inputAmount, remainingAmount,tippedAmount
         *     );
         */
    }

    function _transferPermittedWitnessToTrader(ExecutorValidation.Trade calldata trade, address trader) internal {
        ISignatureTransfer.SignatureTransferDetails memory transferDetails =
            ISignatureTransfer.SignatureTransferDetails({to: trader, requestedAmount: trade.order.inputAmount});

        bytes32 witness = keccak256(
            abi.encode(
                ExecutorValidation.ORDER_TYPEHASH,
                trade.order.maker,
                trade.order.inputToken,
                trade.order.inputAmount,
                trade.order.outputToken,
                trade.order.minAmountOut,
                trade.order.expiry,
                trade.order.nonce,
                trade.order.authorizedExecutor
            )
        );

        ISignatureTransfer(PERMIT2).permitWitnessTransferFrom(
            trade.permit,
            transferDetails,
            trade.order.maker,
            witness,
            ExecutorValidation.WITNESS_TYPE_STRING,
            trade.signature
        );
    }

    function _tipExecutor(address token, uint256 amountOut, ExecutorValidation.TradeType tradeType)
        internal
        returns (uint256)
    {
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

    function _transferToMaker(address maker, address token, uint256 amount, ExecutorValidation.TradeType tradeType)
        internal
    {
        if (tradeType == ExecutorValidation.TradeType.TOKEN_INPUT_ETH_OUTPUT) {
            (bool sent,) = maker.call{value: amount}("");
            require(sent, "tip ETH failed");
        } else {
            IERC20(token).safeTransfer(maker, amount);
        }
    }

    /**
     * @notice Accepts ETH from trader implementations for native ETH swaps
     * @dev Required for TOKEN_INPUT_ETH_OUTPUT trades where traders send ETH back
     */
    receive() external payable {}
}
