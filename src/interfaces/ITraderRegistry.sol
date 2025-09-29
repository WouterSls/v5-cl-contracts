// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import {ITrader} from "./ITrader.sol";

interface ITraderRegistry {
    function getTrader(ITrader.Protocol protocol) external returns (ITrader.TraderInfo calldata traderInfo);
}