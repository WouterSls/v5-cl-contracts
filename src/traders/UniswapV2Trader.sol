// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITrader} from "../interfaces/ITrader.sol";
import {IUniswapV2Router02} from "../../lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ExecutorValidation} from "../libraries/ExecutorValidation.sol";

contract UniswapV2Trader is ITrader {
    address immutable executorAddress;
    address immutable uniswapV2RouterAddress;
    IUniswapV2Router02 immutable uniV2Router;

    string public constant NAME = "UNISWAP V2 Trader";

    error NotCalledByExecutorError();
    error UnknownTradeTypeError();

    constructor(address _executorAddress, address _uniswapV2RouterAddress) {
        executorAddress = _executorAddress;
        uniswapV2RouterAddress = _uniswapV2RouterAddress;
        uniV2Router = IUniswapV2Router02(_uniswapV2RouterAddress);
    }

    modifier onlyExecutor() {
        if (msg.sender != executorAddress) revert NotCalledByExecutorError();
        _;
    }

    function trade(ITrader.TradeParameters calldata params) external onlyExecutor returns (uint256) {
        address to = executorAddress;
        uint256 deadline = params.expiry;
        address[] calldata path = params.routeData.path;
        uint256 amountOutMin = params.amountOutMin;
        uint256 amountIn = params.amountIn;

        uint256 amountOut = 0;
        if (params.tradeType == ExecutorValidation.TradeType.ETH_INPUT_TOKEN_OUTPUT) {
            uint256[] memory amounts =
                uniV2Router.swapExactETHForTokens{value: params.amountIn}(amountOutMin, path, to, deadline);
            amountOut = amounts[amounts.length - 1];
        } else if (params.tradeType == ExecutorValidation.TradeType.TOKEN_INPUT_ETH_OUTPUT) {
            IERC20(params.routeData.path[0]).approve(uniswapV2RouterAddress, params.amountIn);
            uint256[] memory amounts = uniV2Router.swapExactTokensForETH(amountIn, amountOutMin, path, to, deadline);
            amountOut = amounts[amounts.length - 1];
        } else if (params.tradeType == ExecutorValidation.TradeType.TOKEN_INPUT_TOKEN_OUTPUT) {
            IERC20(params.routeData.path[0]).approve(uniswapV2RouterAddress, params.amountIn);
            uint256[] memory amounts = uniV2Router.swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline);
            amountOut = amounts[amounts.length - 1];
        } else {
            revert UnknownTradeTypeError();
        }
        return amountOut;
    }
}
