// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITrader} from "../interfaces/ITrader.sol";
import {ISwapRouter} from "../../lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract UniswapV3Trader is ITrader {
    address immutable executorAddress;
    address immutable uniswapV3RouterAddress;
    ISwapRouter immutable uniV3Router;

    string public constant NAME = "UNISWAP V3 Trader";

    error NotCalledByExecutorError();
    error UnknownTradeTypeError();

    constructor(address _executorAddress, address _uniswapV3RouterAddress) {
        executorAddress = _executorAddress;
        uniswapV3RouterAddress = _uniswapV3RouterAddress;
        uniV3Router = ISwapRouter(_uniswapV3RouterAddress);
    }

    modifier onlyExecutor() {
        if (msg.sender != executorAddress) revert NotCalledByExecutorError();
        _;
    }

    function trade(ITrader.TradeParameters calldata params) external onlyExecutor returns (uint256) {
        bool isMultiHop = (params.routeData.path.length > 2);
        address recipient = executorAddress;
        uint256 deadline = params.expiry;
        uint256 amountIn = params.amountIn;
        uint256 amountOutMin = params.amountOutMin;

        if (!isMultiHop) {
            ISwapRouter.ExactInputSingleParams memory exactInputSingle = ISwapRouter.ExactInputSingleParams({
                tokenIn: params.routeData.path[0],
                tokenOut: params.routeData.path[1],
                fee: params.routeData.fee[0],
                recipient: recipient,
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            });
            return uniV3Router.exactInputSingle(exactInputSingle);
        } else {
            bytes memory encodedPath = _createEncodedPath(params.routeData.path, params.routeData.fee);
            ISwapRouter.ExactInputParams memory exactInput = ISwapRouter.ExactInputParams({
                path: encodedPath,
                recipient: recipient,
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin
            });
            return uniV3Router.exactInput(exactInput);
        }
    }

    function _createEncodedPath(address[] memory path, uint24[] memory fees) internal pure returns (bytes memory) {
        bytes memory encodedPath;

        for (uint256 i = 0; i < fees.length; i++) {
            encodedPath = abi.encodePacked(encodedPath, path[i], fees[i]);
        }
        encodedPath = abi.encodePacked(encodedPath, path[path.length - 1]);

        return encodedPath;
    }
}
