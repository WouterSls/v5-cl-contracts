// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {UniswapV2Trader} from "../src/traders/UniswapV2Trader.sol";

/**
 * @title DeployExecutorBase
 * @notice Deployment script for Base network (Chain ID: 8453)
 * @dev Run with: forge script script/DeployExecutorBase.s.sol --rpc-url $BASE_RPC_URL --broadcast --verify
 */
contract DeployUniswapV2TraderEthereum is Script {
    address constant EXECUTOR_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Mainnet router

    function run() external returns (UniswapV2Trader) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("=== Deploying Executor on Base ===");
        console.log("Deployer:", deployer);
        console.log();

        vm.startBroadcast(pk);

        // Deploy Trader
        UniswapV2Trader trader = new UniswapV2Trader(EXECUTOR_ADDRESS, UNISWAP_V2_ROUTER);

        vm.stopBroadcast();

        console.log("=== Deployment Complete ===");
        console.log("Uniswap V2 Trader Address:", address(trader));
        console.log();

        return trader;
    }
}
