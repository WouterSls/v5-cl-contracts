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
        Order orderHash;
        bytes orderSignature;
        ISignatureTransfer.PermitTransferFrom permitHash; 
        bytes permitSignature;
    }

    struct Order {
        address maker;
        address inputToken;
        uint256 inputAmount;
        address outputToken;
        uint256 minAmountOut;
        uint256 expiry;
        uint256 nonce;
    }

    bytes32 internal constant ORDER_TYPEHASH = keccak256(
        "Order(address maker,address inputToken,uint256 inputAmount,address outputToken,uint256 minAmountOut,uint256 expiry,uint256 nonce)"
    );

    struct RouteData {
        ITrader.Protocol protocol;
        address[] path;
        uint24 fee;
        bool isMultiHop;
        bytes encodedPath;
    }

    error InvalidRouteData();
    error InvalidTradeType();

    function validateInputsAndBusinessLogic(
        Trade calldata trade,
        RouteData calldata routeData,
        mapping(address => mapping(uint256 => bool)) storage usedNonces
    ) internal view {
    }

    function validateSignatures(
        Trade calldata trade,
        bytes32 domainSeparator
    ) internal view {
    }

    function validateTrader(
        RouteData calldata routeData,
        ITrader.TraderInfo memory traderInfo
    ) internal view {
    }

    function determineTradeType(Trade calldata trade, RouteData calldata routeData) internal pure returns (TradeType) {
        address inputToken = routeData.path[0];
        address outputToken = routeData.path[routeData.path.length - 1];

        if (inputToken != trade.orderHash.inputToken) revert InvalidRouteData();
        if (outputToken != trade.orderHash.outputToken) revert InvalidRouteData();
    
        if (inputToken == address(0) && outputToken != address(0)) {
            return TradeType.ETH_INPUT_TOKEN_OUTPUT; 
        } else if (inputToken != address(0) && outputToken != address(0)){
            return TradeType.TOKEN_INPUT_TOKEN_OUTPUT;
        } else if (inputToken != address(0) && outputToken == address(0)) {
            return TradeType.TOKEN_INPUT_ETH_OUTPUT;
        } else {
            revert InvalidTradeType();
        }
    }
}