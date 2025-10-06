// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Executor} from "../src/Executor.sol";
import {ExecutorOwner} from "../src/base/ExecutorOwner.sol";
import {ExecutorValidation} from "../src/libraries/ExecutorValidation.sol";
import {ITrader} from "../src/interfaces/ITrader.sol";
import {ITraderRegistry} from "../src/interfaces/ITraderRegistry.sol";
import {ERC20Mock} from "../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

// Mock TraderRegistry for testing
contract MockTraderRegistry is ITraderRegistry {
    mapping(ITrader.Protocol => ITrader.TraderInfo) public traders;

    function setTrader(
        ITrader.Protocol protocol,
        address implementation,
        bool active,
        uint256 version,
        string memory name
    ) external {
        traders[protocol] = ITrader.TraderInfo({
            protocol: protocol,
            implementation: implementation,
            active: active,
            version: version,
            name: name
        });
    }

    function getTrader(ITrader.Protocol protocol) external view returns (ITrader.TraderInfo memory) {
        return traders[protocol];
    }
}

contract ExecutorOwnerTest is Test {
    Executor public executor;
    MockTraderRegistry public traderRegistry;
    MockTraderRegistry public newTraderRegistry;

    ERC20Mock public tokenA;
    ERC20Mock public tokenB;
    ERC20Mock public tokenC;

    address public permit2 = address(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    address public owner = address(this);
    address public nonOwner = address(0x1234);
    address public recipient = address(0x5678);

    event TraderRegistryUpdated(address indexed newRegistry, address indexed updater);
    event ExecutorFeeUpdated(uint256 newFeeBps, address indexed updater);
    event TokenWhitelisted(address indexed token, address indexed updater);
    event TokenRemovedFromWhitelist(address indexed token, address indexed updater);

    function setUp() public {
        // Deploy mock tokens
        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
        tokenC = new ERC20Mock();

        // Setup initial whitelist
        address[] memory whitelist = new address[](2);
        whitelist[0] = address(tokenA);
        whitelist[1] = address(tokenB);

        // Deploy executor
        executor = new Executor(permit2, owner, whitelist);

        // Deploy and configure mock trader registries
        traderRegistry = new MockTraderRegistry();
        newTraderRegistry = new MockTraderRegistry();

        executor.updateTraderRegistry(address(traderRegistry));

        // Verify initial state
        assertEq(address(executor.traderRegistry()), address(traderRegistry));
        assertEq(executor.executorFee(), 0);
        assertTrue(executor.whitelistedTokens(address(tokenA)));
        assertTrue(executor.whitelistedTokens(address(tokenB)));
        assertFalse(executor.whitelistedTokens(address(tokenC)));
    }

    // ============================================
    // TRADER REGISTRY TESTS
    // ============================================

    function testUpdateTraderRegistry() public {
        vm.expectEmit(true, true, false, true);
        emit TraderRegistryUpdated(address(newTraderRegistry), owner);

        executor.updateTraderRegistry(address(newTraderRegistry));

        assertEq(address(executor.traderRegistry()), address(newTraderRegistry));
    }

    function testUpdateTraderRegistryWithZeroAddressReverts() public {
        vm.expectRevert(ExecutorValidation.ZeroAddress.selector);
        executor.updateTraderRegistry(address(0));
    }

    function testUpdateTraderRegistryNonOwnerReverts() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        executor.updateTraderRegistry(address(newTraderRegistry));
    }

    function testUpdateTraderRegistryMultipleTimes() public {
        MockTraderRegistry registry1 = new MockTraderRegistry();
        MockTraderRegistry registry2 = new MockTraderRegistry();
        MockTraderRegistry registry3 = new MockTraderRegistry();

        executor.updateTraderRegistry(address(registry1));
        assertEq(address(executor.traderRegistry()), address(registry1));

        executor.updateTraderRegistry(address(registry2));
        assertEq(address(executor.traderRegistry()), address(registry2));

        executor.updateTraderRegistry(address(registry3));
        assertEq(address(executor.traderRegistry()), address(registry3));
    }

    function testFuzz_UpdateTraderRegistry(address registryAddress) public {
        vm.assume(registryAddress != address(0));

        executor.updateTraderRegistry(registryAddress);

        assertEq(address(executor.traderRegistry()), registryAddress);
    }

    // ============================================
    // EXECUTOR FEE TESTS
    // ============================================

    function testUpdateExecutorFee() public {
        uint256 newFee = 100; // 1%

        vm.expectEmit(false, true, false, true);
        emit ExecutorFeeUpdated(newFee, owner);

        executor.updateExecutorFee(newFee);

        assertEq(executor.executorFee(), newFee);
    }

    function testUpdateExecutorFeeToZero() public {
        executor.updateExecutorFee(500);
        assertEq(executor.executorFee(), 500);

        executor.updateExecutorFee(0);
        assertEq(executor.executorFee(), 0);
    }

    function testUpdateExecutorFeeToMaxAllowed() public {
        uint256 maxFee = 999; // Just below 10% (1000 bps)

        executor.updateExecutorFee(maxFee);

        assertEq(executor.executorFee(), maxFee);
    }

    function testUpdateExecutorFeeAboveMaxReverts() public {
        uint256 tooHighFee = 1000; // Exactly 10%

        vm.expectRevert(ExecutorOwner.InvalidFee.selector);
        executor.updateExecutorFee(tooHighFee);
    }

    function testUpdateExecutorFeeWayAboveMaxReverts() public {
        uint256 tooHighFee = 5000; // 50%

        vm.expectRevert(ExecutorOwner.InvalidFee.selector);
        executor.updateExecutorFee(tooHighFee);
    }

    function testUpdateExecutorFeeNonOwnerReverts() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        executor.updateExecutorFee(100);
    }

    function testUpdateExecutorFeeMultipleTimes() public {
        executor.updateExecutorFee(100);
        assertEq(executor.executorFee(), 100);

        executor.updateExecutorFee(200);
        assertEq(executor.executorFee(), 200);

        executor.updateExecutorFee(50);
        assertEq(executor.executorFee(), 50);

        executor.updateExecutorFee(0);
        assertEq(executor.executorFee(), 0);
    }

    function testFuzz_UpdateExecutorFeeValidRange(uint256 fee) public {
        vm.assume(fee < 1000); // Below 10%

        executor.updateExecutorFee(fee);

        assertEq(executor.executorFee(), fee);
    }

    function testFuzz_UpdateExecutorFeeInvalidRange(uint256 fee) public {
        vm.assume(fee >= 1000);

        vm.expectRevert(ExecutorOwner.InvalidFee.selector);
        executor.updateExecutorFee(fee);
    }

    // ============================================
    // ADD WHITELISTED TOKEN TESTS
    // ============================================

    function testAddWhitelistedToken() public {
        assertFalse(executor.whitelistedTokens(address(tokenC)));

        vm.expectEmit(true, true, false, true);
        emit TokenWhitelisted(address(tokenC), owner);

        executor.addWhitelistedToken(address(tokenC));

        assertTrue(executor.whitelistedTokens(address(tokenC)));
    }

    function testAddWhitelistedTokenAlreadyWhitelisted() public {
        assertTrue(executor.whitelistedTokens(address(tokenA)));

        // Should not revert, just overwrite
        executor.addWhitelistedToken(address(tokenA));

        assertTrue(executor.whitelistedTokens(address(tokenA)));
    }

    function testAddWhitelistedTokenZeroAddressReverts() public {
        vm.expectRevert(ExecutorValidation.ZeroAddress.selector);
        executor.addWhitelistedToken(address(0));
    }

    function testAddWhitelistedTokenEOAReverts() public {
        address eoa = address(0x9999);

        vm.expectRevert(ExecutorOwner.NotAContract.selector);
        executor.addWhitelistedToken(eoa);
    }

    function testAddWhitelistedTokenNonOwnerReverts() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        executor.addWhitelistedToken(address(tokenC));
    }

    function testAddWhitelistedTokenContract() public {
        ERC20Mock newToken = new ERC20Mock();

        assertFalse(executor.whitelistedTokens(address(newToken)));

        executor.addWhitelistedToken(address(newToken));

        assertTrue(executor.whitelistedTokens(address(newToken)));
    }

    // ============================================
    // REMOVE WHITELISTED TOKEN TESTS
    // ============================================

    function testRemoveWhitelistedToken() public {
        assertTrue(executor.whitelistedTokens(address(tokenA)));

        vm.expectEmit(true, true, false, true);
        emit TokenRemovedFromWhitelist(address(tokenA), owner);

        executor.removeWhitelistedToken(address(tokenA));

        assertFalse(executor.whitelistedTokens(address(tokenA)));
    }

    function testRemoveWhitelistedTokenNotWhitelisted() public {
        assertFalse(executor.whitelistedTokens(address(tokenC)));

        // Should not revert, just set to false
        executor.removeWhitelistedToken(address(tokenC));

        assertFalse(executor.whitelistedTokens(address(tokenC)));
    }

    function testRemoveWhitelistedTokenNonOwnerReverts() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        executor.removeWhitelistedToken(address(tokenA));
    }

    function testRemoveAndReAddToken() public {
        assertTrue(executor.whitelistedTokens(address(tokenA)));

        executor.removeWhitelistedToken(address(tokenA));
        assertFalse(executor.whitelistedTokens(address(tokenA)));

        executor.addWhitelistedToken(address(tokenA));
        assertTrue(executor.whitelistedTokens(address(tokenA)));
    }

    // ============================================
    // ADD MULTIPLE WHITELISTED TOKENS TESTS
    // ============================================

    function testAddWhitelistedTokensMultiple() public {
        ERC20Mock token1 = new ERC20Mock();
        ERC20Mock token2 = new ERC20Mock();
        ERC20Mock token3 = new ERC20Mock();

        address[] memory tokens = new address[](3);
        tokens[0] = address(token1);
        tokens[1] = address(token2);
        tokens[2] = address(token3);

        assertFalse(executor.whitelistedTokens(address(token1)));
        assertFalse(executor.whitelistedTokens(address(token2)));
        assertFalse(executor.whitelistedTokens(address(token3)));

        executor.addWhitelistedTokens(tokens);

        assertTrue(executor.whitelistedTokens(address(token1)));
        assertTrue(executor.whitelistedTokens(address(token2)));
        assertTrue(executor.whitelistedTokens(address(token3)));
    }

    function testAddWhitelistedTokensEmptyArray() public {
        address[] memory tokens = new address[](0);

        // Should not revert
        executor.addWhitelistedTokens(tokens);
    }

    function testAddWhitelistedTokensSingleToken() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenC);

        assertFalse(executor.whitelistedTokens(address(tokenC)));

        executor.addWhitelistedTokens(tokens);

        assertTrue(executor.whitelistedTokens(address(tokenC)));
    }

    function testAddWhitelistedTokensWithZeroAddressReverts() public {
        ERC20Mock validToken = new ERC20Mock();

        address[] memory tokens = new address[](2);
        tokens[0] = address(validToken);
        tokens[1] = address(0); // Zero address

        vm.expectRevert(ExecutorValidation.ZeroAddress.selector);
        executor.addWhitelistedTokens(tokens);
    }

    function testAddWhitelistedTokensWithEOAReverts() public {
        ERC20Mock validToken = new ERC20Mock();
        address eoa = address(0x8888);

        address[] memory tokens = new address[](2);
        tokens[0] = address(validToken);
        tokens[1] = eoa; // EOA

        vm.expectRevert(ExecutorOwner.NotAContract.selector);
        executor.addWhitelistedTokens(tokens);
    }

    function testAddWhitelistedTokensNonOwnerReverts() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenC);

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        executor.addWhitelistedTokens(tokens);
    }

    function testAddWhitelistedTokensWithDuplicates() public {
        ERC20Mock token1 = new ERC20Mock();

        address[] memory tokens = new address[](3);
        tokens[0] = address(token1);
        tokens[1] = address(token1); // Duplicate
        tokens[2] = address(token1); // Duplicate

        // Should not revert, just overwrite multiple times
        executor.addWhitelistedTokens(tokens);

        assertTrue(executor.whitelistedTokens(address(token1)));
    }

    function testFuzz_AddWhitelistedTokensArraySize(uint8 size) public {
        vm.assume(size > 0 && size <= 20); // Reasonable bounds

        address[] memory tokens = new address[](size);
        for (uint256 i = 0; i < size; i++) {
            ERC20Mock token = new ERC20Mock();
            tokens[i] = address(token);
        }

        executor.addWhitelistedTokens(tokens);

        for (uint256 i = 0; i < size; i++) {
            assertTrue(executor.whitelistedTokens(tokens[i]));
        }
    }

    // ============================================
    // EMERGENCY WITHDRAW TOKEN TESTS
    // ============================================

    function testEmergencyWithdrawToken() public {
        uint256 amount = 1000e18;
        tokenA.mint(address(executor), amount);

        assertEq(tokenA.balanceOf(address(executor)), amount);
        assertEq(tokenA.balanceOf(recipient), 0);

        executor.emergencyWithdrawToken(address(tokenA), recipient);

        assertEq(tokenA.balanceOf(address(executor)), 0);
        assertEq(tokenA.balanceOf(recipient), amount);
    }

    function testEmergencyWithdrawETH() public {
        uint256 amount = 5 ether;
        vm.deal(address(executor), amount);

        assertEq(address(executor).balance, amount);
        assertEq(recipient.balance, 0);

        executor.emergencyWithdrawToken(address(0), recipient);

        assertEq(address(executor).balance, 0);
        assertEq(recipient.balance, amount);
    }

    function testEmergencyWithdrawTokenZeroBalance() public {
        assertEq(tokenA.balanceOf(address(executor)), 0);

        // Should not revert
        executor.emergencyWithdrawToken(address(tokenA), recipient);

        assertEq(tokenA.balanceOf(address(executor)), 0);
        assertEq(tokenA.balanceOf(recipient), 0);
    }

    function testEmergencyWithdrawETHZeroBalance() public {
        assertEq(address(executor).balance, 0);

        // Should not revert
        executor.emergencyWithdrawToken(address(0), recipient);

        assertEq(address(executor).balance, 0);
        assertEq(recipient.balance, 0);
    }

    function testEmergencyWithdrawTokenNonOwnerReverts() public {
        uint256 amount = 1000e18;
        tokenA.mint(address(executor), amount);

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        executor.emergencyWithdrawToken(address(tokenA), recipient);
    }

    function testEmergencyWithdrawMultipleTokens() public {
        uint256 amountA = 1000e18;
        uint256 amountB = 2000e18;
        uint256 amountETH = 3 ether;

        tokenA.mint(address(executor), amountA);
        tokenB.mint(address(executor), amountB);
        vm.deal(address(executor), amountETH);

        executor.emergencyWithdrawToken(address(tokenA), recipient);
        executor.emergencyWithdrawToken(address(tokenB), recipient);
        executor.emergencyWithdrawToken(address(0), recipient);

        assertEq(tokenA.balanceOf(recipient), amountA);
        assertEq(tokenB.balanceOf(recipient), amountB);
        assertEq(recipient.balance, amountETH);
    }

    function testFuzz_EmergencyWithdrawTokenAmount(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint128).max);

        tokenA.mint(address(executor), amount);

        executor.emergencyWithdrawToken(address(tokenA), recipient);

        assertEq(tokenA.balanceOf(recipient), amount);
    }

    function testFuzz_EmergencyWithdrawETHAmount(uint96 amount) public {
        vm.assume(amount > 0);

        vm.deal(address(executor), amount);

        executor.emergencyWithdrawToken(address(0), recipient);

        assertEq(recipient.balance, amount);
    }

    // ============================================
    // OWNERSHIP TESTS
    // ============================================

    function testOwnershipInitializedCorrectly() public view {
        assertEq(executor.owner(), owner);
    }

    function testTransferOwnership() public {
        address newOwner = address(0x9999);

        executor.transferOwnership(newOwner);

        assertEq(executor.owner(), newOwner);
    }

    function testTransferOwnershipNonOwnerReverts() public {
        address newOwner = address(0x9999);

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        executor.transferOwnership(newOwner);
    }

    function testNewOwnerCanPerformAdminActions() public {
        address newOwner = address(0x9999);

        executor.transferOwnership(newOwner);

        // New owner can update fee
        vm.prank(newOwner);
        executor.updateExecutorFee(100);
        assertEq(executor.executorFee(), 100);

        // New owner can add token
        vm.prank(newOwner);
        executor.addWhitelistedToken(address(tokenC));
        assertTrue(executor.whitelistedTokens(address(tokenC)));
    }

    function testOldOwnerCannotPerformAdminActionsAfterTransfer() public {
        address newOwner = address(0x9999);

        executor.transferOwnership(newOwner);

        // Old owner cannot update fee
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        executor.updateExecutorFee(100);

        // Old owner cannot add token
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        executor.addWhitelistedToken(address(tokenC));
    }

    // ============================================
    // INTEGRATION TESTS
    // ============================================

    function testCompleteAdminWorkflow() public {
        // Setup new registry
        MockTraderRegistry registry = new MockTraderRegistry();
        executor.updateTraderRegistry(address(registry));
        assertEq(address(executor.traderRegistry()), address(registry));

        // Set fee
        executor.updateExecutorFee(250); // 2.5%
        assertEq(executor.executorFee(), 250);

        // Add multiple tokens
        ERC20Mock token1 = new ERC20Mock();
        ERC20Mock token2 = new ERC20Mock();
        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);
        executor.addWhitelistedTokens(tokens);
        assertTrue(executor.whitelistedTokens(address(token1)));
        assertTrue(executor.whitelistedTokens(address(token2)));

        // Remove one token
        executor.removeWhitelistedToken(address(tokenA));
        assertFalse(executor.whitelistedTokens(address(tokenA)));

        // Emergency withdraw
        uint256 amount = 1000e18;
        token1.mint(address(executor), amount);
        executor.emergencyWithdrawToken(address(token1), recipient);
        assertEq(token1.balanceOf(recipient), amount);
    }

    function testRolesSeparation() public {
        // Owner can perform all admin actions
        executor.updateExecutorFee(100);
        executor.addWhitelistedToken(address(tokenC));
        executor.removeWhitelistedToken(address(tokenA));

        // Non-owner cannot perform any admin action
        vm.startPrank(nonOwner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        executor.updateExecutorFee(200);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        executor.addWhitelistedToken(address(tokenC));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        executor.removeWhitelistedToken(address(tokenB));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        executor.updateTraderRegistry(address(newTraderRegistry));

        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenC);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        executor.addWhitelistedTokens(tokens);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        executor.emergencyWithdrawToken(address(tokenA), nonOwner);

        vm.stopPrank();
    }

    // ============================================
    // EDGE CASE TESTS
    // ============================================

    function testMultipleQuickUpdates() public {
        // Rapid fee updates
        for (uint256 i = 0; i < 10; i++) {
            executor.updateExecutorFee(i * 50);
        }
        assertEq(executor.executorFee(), 450);

        // Rapid token additions/removals
        for (uint256 i = 0; i < 5; i++) {
            executor.addWhitelistedToken(address(tokenC));
            executor.removeWhitelistedToken(address(tokenC));
        }
        assertFalse(executor.whitelistedTokens(address(tokenC)));
    }

    function testBoundaryFeeValues() public {
        // Test 0
        executor.updateExecutorFee(0);
        assertEq(executor.executorFee(), 0);

        // Test 1
        executor.updateExecutorFee(1);
        assertEq(executor.executorFee(), 1);

        // Test max allowed - 1
        executor.updateExecutorFee(999);
        assertEq(executor.executorFee(), 999);

        // Test max allowed (should revert)
        vm.expectRevert(ExecutorOwner.InvalidFee.selector);
        executor.updateExecutorFee(1000);
    }

    function testLargeWhitelistBatch() public {
        uint256 batchSize = 50;
        address[] memory tokens = new address[](batchSize);

        for (uint256 i = 0; i < batchSize; i++) {
            ERC20Mock token = new ERC20Mock();
            tokens[i] = address(token);
        }

        executor.addWhitelistedTokens(tokens);

        for (uint256 i = 0; i < batchSize; i++) {
            assertTrue(executor.whitelistedTokens(tokens[i]));
        }
    }
}
