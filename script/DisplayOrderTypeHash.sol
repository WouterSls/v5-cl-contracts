// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Executor} from "../src/Executor.sol";
import {ERC20Mock} from "../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
//import {DeployPermit2 as DeployPermit2Script} from "../lib/permit2/script/DeployPermit2.s.sol";
import {DeployPermit2 as DeployPermit2Helper} from "../lib/permit2/test/utils/DeployPermit2.sol";

contract DeployExecutorLocal is Script {
    function run() external returns (Executor) {
        // Deploy Permit2
        //Permit2 permit2 = new DeployPermit2Script().run();
        //address permit2Address = address(permit2);

        address permit2Address = new DeployPermit2Helper().deployPermit2();

        uint256 pk = vm.envUint("LOCAL_DEPLOYER_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        // Deploy Executor with Permit2 address
        Executor executor = new Executor(permit2Address, deployer);

        // Deploy mock tokens
        ERC20Mock tokenA = new ERC20Mock();
        ERC20Mock tokenB = new ERC20Mock();

        vm.stopBroadcast();

        return executor;
    }
}
