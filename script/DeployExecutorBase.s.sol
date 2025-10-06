// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Executor} from "../src/Executor.sol";

/**
 * @title DeployExecutorBase
 * @notice Deployment script for Base network (Chain ID: 8453)
 * @dev Run with: forge script script/DeployExecutorBase.s.sol --rpc-url $BASE_RPC_URL --broadcast --verify
 */
contract DeployExecutorBase is Script {
    address constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // Base token addresses
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant USDBC = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA; // Bridged USDC
    address constant DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
    address constant AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
    address constant VIRTUAL = 0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b;

    function run() external returns (Executor) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("=== Deploying Executor on Base ===");
        console.log("Deployer:", deployer);
        console.log();

        // Setup whitelist with Base tokens
        address[] memory whitelist = new address[](6);
        whitelist[0] = WETH;
        whitelist[1] = USDC;
        whitelist[2] = USDBC;
        whitelist[3] = DAI;
        whitelist[4] = AERO;
        whitelist[5] = VIRTUAL;

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
        console.log("USDbC:", USDBC, executor.whitelistedTokens(USDBC));
        console.log("DAI:", DAI, executor.whitelistedTokens(DAI));
        console.log("AERO:", AERO, executor.whitelistedTokens(AERO));
        console.log("VIRTUAL:", VIRTUAL, executor.whitelistedTokens(VIRTUAL));
        console.log();

        return executor;
    }
}
