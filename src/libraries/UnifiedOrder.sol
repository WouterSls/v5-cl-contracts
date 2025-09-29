// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ISignatureTransfer} from "../../lib/permit2/src/interfaces/ISignatureTransfer.sol";
import {IPermit2} from "../../lib/permit2/src/interfaces/IPermit2.sol";
import {ExecutorValidation} from "../libraries/ExecutorValidation.sol";

contract ExampleMarket {
    IPermit2 public immutable permit2;

    // ORDER_TYPEHASH must match frontend EIP-712 witness hashing
    bytes32 internal constant ORDER_TYPEHASH = keccak256(
        "Order(address maker,address inputToken,uint256 inputAmount,address outputToken,uint256 minAmountOut,uint256 expiry,uint256 nonce)"
    );

    // witnessTypeString — part of the EIP-712 type string that Permit2 expects.
    // NOTE: TokenPermissions must be appended per EIP-712 struct ordering (alphabetical).
    string public constant WITNESS_TYPE_STRING =
        "Order witness)Order(address maker,address inputToken,uint256 inputAmount,address outputToken,uint256 minAmountOut,uint256 expiry,uint256 nonce)TokenPermissions(address token,uint256 amount)";

    constructor(address _permit2) {
        permit2 = IPermit2(_permit2);
    }

    function executeTrade(ExecutorValidation.Trade calldata trade) external {
        ExecutorValidation.Order calldata o = trade.orderHash;

        // Basic sanity checks before consuming permit
        require(o.expiry >= block.timestamp, "order expired");

        // compute witness hash the same way frontend did
        bytes32 witness = keccak256(
            abi.encode(
                ORDER_TYPEHASH,
                o.maker,
                o.inputToken,
                o.inputAmount,
                o.outputToken,
                o.minAmountOut,
                o.expiry,
                o.nonce
            )
        );

        // Optional additional checks to make sure permit fields align with the order:
        require(trade.permitHash.permitted.token == o.inputToken, "token mismatch");
        require(trade.permitHash.permitted.amount >= o.inputAmount, "permit amount too small");
        // (you can also require permit.deadline >= block.timestamp etc.)

        ISignatureTransfer.SignatureTransferDetails memory transferDetails  = ISignatureTransfer.SignatureTransferDetails({
            to: trade.orderHash.maker, // should be trader for gas efficiency
            requestedAmount: trade.orderHash.inputAmount
        });

        // Perform the Permit2 witness transfer. This validates the signature and moves tokens from owner -> transferDetails.to
        permit2.permitWitnessTransferFrom(
            trade.permitHash,
            transferDetails,
            o.maker,            // owner: should equal the signer of the permit
            witness,
            WITNESS_TYPE_STRING,
            trade.permitSignature
        );

        // At this point tokens (inputAmount) have been received by transferDetails.to (likely address(this))
        // Now perform swap logic: e.g. call internal exchange, routing, check minAmountOut, send outputToken to recipient, etc.
        // ... perform swap and checks ...
    }
}
