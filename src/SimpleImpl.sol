// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// This is account contract holds the trader functionality
// The entry point contract delegates the call to this implementation
// Do we sign a type 4 transaction and then send transactions of type 4 to the entry point? or is every user operation of type 4
contract SimpleImpl {
  // storage at the EOA address will be used — design storage carefully!

  // called by EntryPoint to validate the UserOperation
  function validateUserOp(bytes calldata userOp, bytes32 userOpHash, uint256 missing) external returns (uint256) {
    // 1) recover signer from userOp.signature
    // 2) check signer == expected owner (often address(this) == the EOA addr)
    // 3) check nonce, replay protection, paymaster conditions...
    // return validation gas/payment hint
  }

  // called by EntryPoint to execute the operation
  function execute(address target, uint256 value, bytes calldata data) external {
    /**
    require(msg.sender == ENTRYPOINT); // protect
    */
   // Can we call executor contract here? or we implement executor logic on this contract?
    (bool ok, ) = target.call{value: value}(data);

    require(ok);
  }
}
