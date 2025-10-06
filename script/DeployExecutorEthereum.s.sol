// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Executor} from "../src/Executor.sol";

/**
 * @title DeployExecutorEthereum
 * @notice Deployment script for Ethereum Mainnet (Chain ID: 1)
 * @dev Run with: forge script script/DeployExecutorEthereum.s.sol --rpc-url $ETH_RPC_URL --broadcast --verify
 */
contract DeployExecutorEthereum is Script {
    address constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // Ethereum Mainnet token addresses
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant USDS = 0xdC035d45D973E3Ec169D938868753234de7e3f92;
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;

    function run() external returns (Executor) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("=== Deploying Executor on Ethereum Mainnet ===");
        console.log("Deployer:", deployer);
        console.log();

        // Setup whitelist with Ethereum Mainnet tokens
        address[] memory whitelist = new address[](8);
        whitelist[0] = WETH;
        whitelist[1] = USDC;
        whitelist[2] = USDT;
        whitelist[3] = DAI;
        whitelist[4] = WBTC;
        whitelist[5] = USDS;
        whitelist[6] = WSTETH;
        whitelist[7] = UNI;

        vm.startBroadcast(pk);

        // Deploy Executor
        Executor executor = new Executor(PERMIT2_ADDRESS, deployer, whitelist);

        vm.stopBroadcast();

        console.log("=== Deployment Complete ===");
        console.log("Executor Address:", address(executor));
        console.log("Owner:", executor.owner());
        console.log("Permit2:", PERMIT2_ADDRESS);
        console.log();

        console.log("=== Whitelisted Tokens ===");
        console.log("WETH:", WETH, executor.whitelistedTokens(WETH));
        console.log("USDC:", USDC, executor.whitelistedTokens(USDC));
        console.log("USDT:", USDT, executor.whitelistedTokens(USDT));
        console.log("DAI:", DAI, executor.whitelistedTokens(DAI));
        console.log("WBTC:", WBTC, executor.whitelistedTokens(WBTC));
        console.log("USDS:", USDS, executor.whitelistedTokens(USDS));
        console.log("wstETH:", WSTETH, executor.whitelistedTokens(WSTETH));
        console.log("UNI:", UNI, executor.whitelistedTokens(UNI));
        console.log();

        return executor;
    }
}
