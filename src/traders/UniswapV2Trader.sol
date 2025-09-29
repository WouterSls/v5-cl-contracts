// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITrader} from "../interfaces/ITrader.sol";
import {IUniswapV2Router02} from "../interfaces/IUniswapV2Router.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ExecutorValidation} from "../libraries/ExecutorValidation.sol";

contract UniswapV2Trader {
    address immutable EXECUTOR_ADDRESS;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Mainnet router

    error NotCalledByExecutorError();
    error UnknownTradeTypeError();

    constructor(address _EXECUTOR_ADDRESS) {
        EXECUTOR_ADDRESS = _EXECUTOR_ADDRESS;
    }

    modifier onlyExecutor() {
        if (msg.sender != EXECUTOR_ADDRESS) revert NotCalledByExecutorError();
        _;
    }

    function trade(ITrader.TradeParameters calldata params) external onlyExecutor {
        address to = EXECUTOR_ADDRESS;
        uint256 deadline = params.expiry;
        
        uint256 amountIn = params.amountIn;

        if (params.tradeType == ExecutorValidation.TradeType.ETH_INPUT_TOKEN_OUTPUT) {
            uint[] memory amounts = IUniswapV2Router02(UNISWAP_V2_ROUTER).swapExactETHForTokens{value: params.amountIn}(
                params.amountOutMin,
                params.routeData.path,
                to,
                deadline
            );
        } else if (params.tradeType == ExecutorValidation.TradeType.TOKEN_INPUT_ETH_OUTPUT) {
            IERC20(params.tokenIn).approve(UNISWAP_V2_ROUTER, params.amountIn);
            uint[] memory amounts = IUniswapV2Router02(UNISWAP_V2_ROUTER).swapExactTokensForETH(
                params.amountIn,
                params.amountOutMin,
                params.routeData.path,
                to,
                deadline
            );
        } else if (params.tradeType == ExecutorValidation.TradeType.TOKEN_INPUT_TOKEN_OUTPUT) {
            IERC20(params.tokenIn).approve(UNISWAP_V2_ROUTER, params.amountIn);
            uint[] memory amounts = IUniswapV2Router02(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
                params.amountIn,
                params.amountOutMin,
                params.routeData.path,
                to,
                deadline
            );
        } else {
            revert UnknownTradeTypeError();
        }
    }
}