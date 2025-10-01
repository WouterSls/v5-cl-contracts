// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Executor} from "../src/Executor.sol";
import {ERC20Mock} from "../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
//import {DeployPermit2 as DeployPermit2Script} from "../lib/permit2/script/DeployPermit2.s.sol";
//import {DeployPermit2 as DeployPermit2Helper} from "../lib/permit2/test/utils/DeployPermit2.sol";

contract DeployExecutorLocal is Script {
    //address constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant PERMIT2_ADDRESS = 0x04Bf6dd19092d8DC89dE2499a037958296D20E49;

    function run() external returns (Executor) {
        uint256 pk = vm.envUint("LOCAL_DEPLOYER_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        // Deploy Executor with Permit2 address
        Executor executor = new Executor(PERMIT2_ADDRESS, deployer);

        // Deploy mock tokens
        ERC20Mock tokenA = new ERC20Mock();
        ERC20Mock tokenB = new ERC20Mock();

        vm.stopBroadcast();

        console.log("DEPLOYER ADDRESS:");
        console.log(deployer);
        console.log();

        console.log("OWNER:");
        console.log(executor.owner());
        console.log();

        console.log("TOKEN A ADDRESS:");
        console.log(address(tokenA));
        console.log();

        console.log("TOKEN B ADDRESS:");
        console.log(address(tokenB));
        console.log();

        console.log("PERMIT2 ADDRESS:");
        console.log(PERMIT2_ADDRESS);
        console.log();

        console.log("EXECUTOR ADDRESS:");
        console.log(address(executor));
        console.log();





        return executor;
    }
}
