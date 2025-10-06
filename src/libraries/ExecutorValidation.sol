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
        bool isMultiHop;
        bytes encodedPath;
    }

    error ZeroAddress();
    error ZeroAmount();
    error TokenMismatch();
    error OrderExpired();
    error NonceAlreadyUsed();
    error InvalidProtocol();
    error InvalidRouteData();
    error InvalidTradeType();
    error UnauthorizedExecutor();
    error InvalidPathStart();
    error InvalidPathEnd();
    error PathTooLong();
    error UntrustedIntermediateToken(address token);

    function validateInputsAndBusinessLogic(
        Trade calldata trade,
        RouteData calldata routeData,
        mapping(address => mapping(uint256 => bool)) storage usedNonces,
        address executor
    ) internal view {
        if (trade.order.authorizedExecutor != address(0)) {
            if (executor != trade.order.authorizedExecutor) {
                revert UnauthorizedExecutor();
            }
        }

        if (trade.order.maker == address(0)) revert ZeroAddress();
        if (trade.order.inputToken == address(0)) revert ZeroAddress();
        if (trade.order.outputToken == address(0)) revert ZeroAddress();
        if (trade.permit.permitted.token == address(0)) revert ZeroAddress();

        if (trade.order.inputAmount == 0) revert ZeroAmount();
        if (trade.order.minAmountOut == 0) revert ZeroAmount();
        if (trade.permit.permitted.amount == 0) revert ZeroAmount();

        if (trade.order.inputToken != trade.permit.permitted.token) revert TokenMismatch();
        //if (signedOrder.inputAmount != signedPermitData.transferDetails.requestedAmount) revert PermitAmountMismatch();
        //if (signedPermitData.transferDetails.requestedAmount > signedPermitData.permit.permitted.amount) revert PermitAmountMismatch();

        if (block.timestamp > trade.order.expiry) revert OrderExpired();
        if (usedNonces[trade.order.maker][trade.order.nonce]) revert NonceAlreadyUsed();

        if (uint8(routeData.protocol) > uint8(ITrader.Protocol.AERODROME)) {
            revert InvalidProtocol();
        }

        // Route data validation
        if (routeData.isMultiHop && routeData.encodedPath.length == 0) revert InvalidRouteData();
        if (!routeData.isMultiHop && routeData.fee.length < 1) revert InvalidRouteData();

        if (routeData.isMultiHop) {
            if (routeData.encodedPath.length < 43) revert InvalidRouteData();
        } else {
            // Validate fee tier for non-multihop (single pool) swaps
            uint24 feeTier = routeData.fee[0];
            if (feeTier != 100 && feeTier != 500 && feeTier != 3000 && feeTier != 10000) {
                revert InvalidRouteData();
            }
        }
    }

    function validateRouteStructure(
        Order calldata order,
        RouteData calldata routeData,
        mapping(address => bool) storage whitelistedTokens
    ) internal view {
        if (routeData.path.length < 2) revert InvalidRouteData();
        if (routeData.path.length > 4) revert PathTooLong();

        if (routeData.path[0] != order.inputToken) revert InvalidPathStart();
        if (routeData.path[routeData.path.length - 1] != order.outputToken) {
            revert InvalidPathEnd();
        }

        for (uint256 i = 1; i < routeData.path.length - 1; i++) {
            if (!whitelistedTokens[routeData.path[i]]) {
                revert UntrustedIntermediateToken(routeData.path[i]);
            }
        }
    }

    function validateTrader(RouteData calldata routeData, ITrader.TraderInfo memory traderInfo) internal view {}

    function determineTradeType(Trade calldata trade, RouteData calldata routeData) internal pure returns (TradeType) {
        address inputToken = routeData.path[0];
        address outputToken = routeData.path[routeData.path.length - 1];

        if (inputToken != trade.order.inputToken) revert InvalidRouteData();
        if (outputToken != trade.order.outputToken) revert InvalidRouteData();

        if (inputToken == address(0) && outputToken != address(0)) {
            return TradeType.ETH_INPUT_TOKEN_OUTPUT;
        } else if (inputToken != address(0) && outputToken != address(0)) {
            return TradeType.TOKEN_INPUT_TOKEN_OUTPUT;
        } else if (inputToken != address(0) && outputToken == address(0)) {
            return TradeType.TOKEN_INPUT_ETH_OUTPUT;
        } else {
            revert InvalidTradeType();
        }
    }
}
