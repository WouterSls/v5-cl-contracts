// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import {ExecutorValidation} from "../libraries/ExecutorValidation.sol";

interface ITrader {
    enum Protocol {
        UNISWAP_V2,
        UNISWAP_V3,
        UNISWAP_V4,
        SUSHISWAP,
        BALANCER_V2,
        CURVE,
        PANCAKESWAP_V2,
        PANCAKESWAP_V3,
        AERODROME
    }

    struct TraderInfo {
        Protocol protocol;
        address implementation;
        bool active;
        uint256 version;
        string name;
    }

    struct TradeParameters {
        address tokenIn;
        address tokenOut;
        uint256 amountOutMin;
        uint256 expiry;
        ExecutorValidation.TradeType tradeType;
        ExecutorValidation.RouteData routeData;
    }

    function trade(TradeParameters calldata params) external returns (uint256);
}