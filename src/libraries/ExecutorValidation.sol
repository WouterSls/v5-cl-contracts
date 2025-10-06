// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITrader} from "../interfaces/ITrader.sol";
import {ISignatureTransfer} from "../../lib/permit2/src/interfaces/ISignatureTransfer.sol";

library ExecutorValidation {
    enum TradeType {
        ETH_INPUT_TOKEN_OUTPUT,
        TOKEN_INPUT_ETH_OUTPUT,
        TOKEN_INPUT_TOKEN_OUTPUT
    }

    struct Trade {
        Order order;
        ISignatureTransfer.PermitTransferFrom permit;
        bytes signature;
    }

    struct Order {
        address maker;
        address inputToken;
        uint256 inputAmount;
        address outputToken;
        uint256 minAmountOut;
        uint256 expiry;
        uint256 nonce;
        address authorizedExecutor;
    }

    bytes32 internal constant ORDER_TYPEHASH = keccak256(
        "Order(address maker,address inputToken,uint256 inputAmount,address outputToken,uint256 minAmountOut,uint256 expiry,uint256 nonce,address authorizedExecutor)"
    );

    string public constant WITNESS_TYPE_STRING =
        "Order witness)Order(address maker,address inputToken,uint256 inputAmount,address outputToken,uint256 minAmountOut,uint256 expiry,uint256 nonce,address authorizedExecutor)TokenPermissions(address token,uint256 amount)";

    struct RouteData {
        ITrader.Protocol protocol;
        address[] path;
        uint24[] fee;
    }

    // Generic validation errors
    error ZeroAddress();
    error ZeroAmount();
    error OrderExpired();
    error NativeETHTradeNotSupported();

    // Order validation errors with context
    error OrderPermitTokenMismatch();
    error OrderPermitNonceMismatch();
    error OrderPermitAmountMismatch();
    error OrderPermitDeadlineMismatch();
    error UnauthorizedExecutor();

    // Route validation errors
    error PathTooShort();
    error PathTooLong();
    error RouteInputTokenMismatch();
    error RouteOutputTokenMismatch();
    error SameInputOutputToken();
    error UntrustedIntermediateToken(address token);

    // Protocol-specific errors
    error InvalidProtocol();
    error V2ProtocolShouldNotHaveFees();
    error V3PathFeeLengthMismatch();
    error InvalidFeeTier(uint24 providedFee);

    // Trader validation errors
    error InactiveTrader();
    error InvalidTraderImplementation();
    error TraderNotContract();
    error ProtocolMismatch();
    error InvalidTraderVersion();

    function validateInputsAndBusinessLogic(Trade calldata trade, address executor) internal view {
        if (block.timestamp > trade.order.expiry) revert OrderExpired();

        if (trade.order.inputAmount == 0) revert ZeroAmount();
        if (trade.order.minAmountOut == 0) revert ZeroAmount();
        if (trade.permit.permitted.amount == 0) revert ZeroAmount();

        if (trade.order.maker == address(0)) revert ZeroAddress();
        if (trade.permit.permitted.token == address(0)) revert ZeroAddress();

        // Native ETH not supported for now - can be enabled later for ETH trades
        // When enabling: check for WETH wrapper handling and update determineTradeType usage
        if (trade.order.inputToken == address(0)) revert ZeroAddress();
        if (trade.order.outputToken == address(0)) revert ZeroAddress();

        if (trade.order.inputToken != trade.permit.permitted.token) revert OrderPermitTokenMismatch();
        if (trade.order.inputAmount != trade.permit.permitted.amount) revert OrderPermitAmountMismatch();
        if (trade.order.nonce != trade.permit.nonce) revert OrderPermitNonceMismatch();
        if (trade.order.expiry != trade.permit.deadline) revert OrderPermitDeadlineMismatch();

        if (trade.order.authorizedExecutor != address(0)) {
            if (executor != trade.order.authorizedExecutor) revert UnauthorizedExecutor();
        }
    }

    function validateRouteData(
        Order calldata order,
        RouteData calldata routeData,
        mapping(address => bool) storage whitelistedTokens
    ) internal view {
        if (routeData.path.length < 2) revert PathTooShort();
        if (routeData.path.length > 4) revert PathTooLong();
        if (uint8(routeData.protocol) > uint8(ITrader.Protocol.AERODROME)) revert InvalidProtocol();

        address inputToken = routeData.path[0];
        address outputToken = routeData.path[routeData.path.length - 1];

        if (inputToken != order.inputToken) revert RouteInputTokenMismatch();
        if (outputToken != order.outputToken) revert RouteOutputTokenMismatch();
        if (inputToken == outputToken) revert SameInputOutputToken();

        // Native ETH not supported for now - can be enabled later for ETH trades
        // When enabling: remove these checks and ensure WETH wrapping in traders
        for (uint256 i = 0; i < routeData.path.length; i++) {
            if (routeData.path[i] == address(0)) revert NativeETHTradeNotSupported();
        }

        // Validate intermediate tokens are whitelisted (most expensive check last)
        for (uint256 i = 1; i < routeData.path.length - 1; i++) {
            if (!whitelistedTokens[routeData.path[i]]) {
                revert UntrustedIntermediateToken(routeData.path[i]);
            }
        }

        // Uniswap V2 validation
        if (routeData.protocol == ITrader.Protocol.UNISWAP_V2) {
            if (routeData.fee.length != 0) revert V2ProtocolShouldNotHaveFees();
        }

        // Uniswap V3 validation
        if (routeData.protocol == ITrader.Protocol.UNISWAP_V3) {
            if (routeData.path.length != routeData.fee.length + 1) revert V3PathFeeLengthMismatch();

            for (uint256 i = 0; i < routeData.fee.length; i++) {
                uint24 feeTier = routeData.fee[i];
                if (feeTier != 100 && feeTier != 500 && feeTier != 3000 && feeTier != 10000) {
                    revert InvalidFeeTier(feeTier);
                }
            }
        }
    }

    function validateTrader(RouteData calldata routeData, ITrader.TraderInfo memory traderInfo) internal view {
        if (!traderInfo.active) revert InactiveTrader();
        if (traderInfo.implementation == address(0)) revert InvalidTraderImplementation();
        if (traderInfo.implementation.code.length == 0) revert TraderNotContract();
        if (traderInfo.protocol != routeData.protocol) revert ProtocolMismatch();
        if (traderInfo.version == 0) revert InvalidTraderVersion();
    }

    function determineTradeType(RouteData calldata routeData) internal pure returns (TradeType) {
        address inputToken = routeData.path[0];
        address outputToken = routeData.path[routeData.path.length - 1];

        // Note: Native ETH currently not supported, but this function remains for future use
        bool isInputETH = (inputToken == address(0));
        bool isOutputETH = (outputToken == address(0));

        if (isInputETH && isOutputETH) revert SameInputOutputToken();

        if (isInputETH && !isOutputETH) return TradeType.ETH_INPUT_TOKEN_OUTPUT;
        if (!isInputETH && isOutputETH) return TradeType.TOKEN_INPUT_ETH_OUTPUT;
        if (!isInputETH && !isOutputETH) return TradeType.TOKEN_INPUT_TOKEN_OUTPUT;

        revert NativeETHTradeNotSupported();
    }
}
