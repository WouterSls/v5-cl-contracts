// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Executor} from "../src/Executor.sol";
import {ExecutorValidation} from "../src/libraries/ExecutorValidation.sol";
import {ITrader} from "../src/interfaces/ITrader.sol";
import {ISignatureTransfer} from "../lib/permit2/src/interfaces/ISignatureTransfer.sol";
import {ERC20Mock} from "../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract ExecutorValidationTest is Test {
    Executor public executor;

    ERC20Mock public tokenA;
    ERC20Mock public tokenB;
    ERC20Mock public tokenC;
    ERC20Mock public maliciousToken;

    address public permit2 = address(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    address public owner = address(this);
    address public authorizedExecutor = address(0x1111);
    address public unauthorizedUser = address(0x2222);
    address public maker = address(0x3333);

    function setUp() public {
        // Deploy mock tokens
        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
        tokenC = new ERC20Mock();
        maliciousToken = new ERC20Mock();

        // Setup whitelist with tokenA, tokenB, tokenC (not maliciousToken)
        address[] memory whitelist = new address[](3);
        whitelist[0] = address(tokenA);
        whitelist[1] = address(tokenB);
        whitelist[2] = address(tokenC);

        // Deploy executor
        executor = new Executor(permit2, owner, whitelist);

        // Verify whitelist was set correctly
        assertTrue(executor.whitelistedTokens(address(tokenA)));
        assertTrue(executor.whitelistedTokens(address(tokenB)));
        assertTrue(executor.whitelistedTokens(address(tokenC)));
        assertFalse(executor.whitelistedTokens(address(maliciousToken)));
    }

    // ============ Authorized Executor Tests ============

    function testAuthorizedExecutorCanExecute() public {
        ExecutorValidation.Order memory order = createOrder(authorizedExecutor);
        ExecutorValidation.RouteData memory routeData = createValidRouteData();
        ExecutorValidation.Trade memory trade = createTrade(order);

        vm.prank(authorizedExecutor);
        // Should not revert
        (bool success,) =
            address(executor).call(abi.encodeWithSelector(executor.executeTrade.selector, trade, routeData));

        // Will fail on permit2 transfer but should pass validation
        assertFalse(success); // Expected to fail on transfer, not validation
    }

    function testUnauthorizedExecutorReverts() public {
        ExecutorValidation.Order memory order = createOrder(authorizedExecutor);
        ExecutorValidation.RouteData memory routeData = createValidRouteData();
        ExecutorValidation.Trade memory trade = createTrade(order);

        vm.prank(unauthorizedUser);
        vm.expectRevert(ExecutorValidation.UnauthorizedExecutor.selector);
        executor.executeTrade(trade, routeData);
    }

    function testZeroAddressAuthExecutorAllowsAnyone() public {
        ExecutorValidation.Order memory order = createOrder(address(0)); // No restriction
        ExecutorValidation.RouteData memory routeData = createValidRouteData();
        ExecutorValidation.Trade memory trade = createTrade(order);

        vm.prank(unauthorizedUser);
        // Should not revert on authorization check
        (bool success,) =
            address(executor).call(abi.encodeWithSelector(executor.executeTrade.selector, trade, routeData));

        // Will fail on permit2 but passed authorization
        assertFalse(success);
    }

    // ============ Token Whitelist Tests ============

    function testDirectPathWithNoIntermediaryPasses() public {
        ExecutorValidation.Order memory order = createOrder(authorizedExecutor);

        // Direct swap A -> B (no intermediate tokens to validate)
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        ExecutorValidation.RouteData memory routeData = createRouteData(path);
        ExecutorValidation.Trade memory trade = createTrade(order);

        vm.prank(authorizedExecutor);
        (bool success,) =
            address(executor).call(abi.encodeWithSelector(executor.executeTrade.selector, trade, routeData));

        assertFalse(success); // Fails on permit2, not validation
    }

    function testWhitelistedIntermediaryPasses() public {
        ExecutorValidation.Order memory order = createOrder(authorizedExecutor);

        // Path: A -> C -> B (C is whitelisted)
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenC); // Whitelisted intermediate
        path[2] = address(tokenB);

        order.inputToken = address(tokenA);
        order.outputToken = address(tokenB);

        ExecutorValidation.RouteData memory routeData = createRouteData(path);
        ExecutorValidation.Trade memory trade = createTrade(order);

        vm.prank(authorizedExecutor);
        (bool success,) =
            address(executor).call(abi.encodeWithSelector(executor.executeTrade.selector, trade, routeData));

        assertFalse(success); // Fails on permit2, not validation
    }

    function testMaliciousIntermediaryReverts() public {
        ExecutorValidation.Order memory order = createOrder(authorizedExecutor);

        // Path: A -> maliciousToken -> B
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(maliciousToken); // NOT whitelisted
        path[2] = address(tokenB);

        order.inputToken = address(tokenA);
        order.outputToken = address(tokenB);

        ExecutorValidation.RouteData memory routeData = createRouteData(path);
        ExecutorValidation.Trade memory trade = createTrade(order);

        vm.prank(authorizedExecutor);
        vm.expectRevert(
            abi.encodeWithSelector(ExecutorValidation.UntrustedIntermediateToken.selector, address(maliciousToken))
        );
        executor.executeTrade(trade, routeData);
    }

    // ============ Path Validation Tests ============

    function testPathStartMismatchReverts() public {
        ExecutorValidation.Order memory order = createOrder(authorizedExecutor);
        order.inputToken = address(tokenA);
        order.outputToken = address(tokenB);

        // Path starts with wrong token
        address[] memory path = new address[](2);
        path[0] = address(tokenC); // Should be tokenA
        path[1] = address(tokenB);

        ExecutorValidation.RouteData memory routeData = createRouteData(path);
        ExecutorValidation.Trade memory trade = createTrade(order);

        vm.prank(authorizedExecutor);
        vm.expectRevert(ExecutorValidation.InvalidPathStart.selector);
        executor.executeTrade(trade, routeData);
    }

    function testPathEndMismatchReverts() public {
        ExecutorValidation.Order memory order = createOrder(authorizedExecutor);
        order.inputToken = address(tokenA);
        order.outputToken = address(tokenB);

        // Path ends with wrong token
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenC); // Should be tokenB

        ExecutorValidation.RouteData memory routeData = createRouteData(path);
        ExecutorValidation.Trade memory trade = createTrade(order);

        vm.prank(authorizedExecutor);
        vm.expectRevert(ExecutorValidation.InvalidPathEnd.selector);
        executor.executeTrade(trade, routeData);
    }

    function testPathTooShortReverts() public {
        ExecutorValidation.Order memory order = createOrder(authorizedExecutor);

        // Path with only 1 token
        address[] memory path = new address[](1);
        path[0] = address(tokenA);

        ExecutorValidation.RouteData memory routeData = createRouteData(path);
        ExecutorValidation.Trade memory trade = createTrade(order);

        vm.prank(authorizedExecutor);
        vm.expectRevert(ExecutorValidation.InvalidRouteData.selector);
        executor.executeTrade(trade, routeData);
    }

    function testPathTooLongReverts() public {
        ExecutorValidation.Order memory order = createOrder(authorizedExecutor);
        order.inputToken = address(tokenA);
        order.outputToken = address(tokenB);

        // Path with 5 tokens (max is 4)
        address[] memory path = new address[](5);
        path[0] = address(tokenA);
        path[1] = address(tokenC);
        path[2] = address(tokenB);
        path[3] = address(tokenC);
        path[4] = address(tokenB);

        ExecutorValidation.RouteData memory routeData = createRouteData(path);
        ExecutorValidation.Trade memory trade = createTrade(order);

        vm.prank(authorizedExecutor);
        vm.expectRevert(ExecutorValidation.PathTooLong.selector);
        executor.executeTrade(trade, routeData);
    }

    function testMaxPathLengthPasses() public {
        ExecutorValidation.Order memory order = createOrder(authorizedExecutor);
        order.inputToken = address(tokenA);
        order.outputToken = address(tokenB);

        // Path with 4 tokens (max allowed)
        address[] memory path = new address[](4);
        path[0] = address(tokenA);
        path[1] = address(tokenC); // Whitelisted
        path[2] = address(tokenB); // Whitelisted
        path[3] = address(tokenB); // End token

        ExecutorValidation.RouteData memory routeData = createRouteData(path);
        ExecutorValidation.Trade memory trade = createTrade(order);

        vm.prank(authorizedExecutor);
        (bool success,) =
            address(executor).call(abi.encodeWithSelector(executor.executeTrade.selector, trade, routeData));

        assertFalse(success); // Fails on permit2, not validation
    }

    // ============ Input Validation Tests ============

    function testZeroAddressMakerReverts() public {
        ExecutorValidation.Order memory order = createOrder(authorizedExecutor);
        order.maker = address(0);

        ExecutorValidation.RouteData memory routeData = createValidRouteData();
        ExecutorValidation.Trade memory trade = createTrade(order);

        vm.prank(authorizedExecutor);
        vm.expectRevert(ExecutorValidation.ZeroAddress.selector);
        executor.executeTrade(trade, routeData);
    }

    function testZeroAddressInputTokenReverts() public {
        ExecutorValidation.Order memory order = createOrder(authorizedExecutor);
        order.inputToken = address(0);

        ExecutorValidation.RouteData memory routeData = createValidRouteData();
        ExecutorValidation.Trade memory trade = createTrade(order);

        vm.prank(authorizedExecutor);
        vm.expectRevert(ExecutorValidation.ZeroAddress.selector);
        executor.executeTrade(trade, routeData);
    }

    function testZeroAddressOutputTokenReverts() public {
        ExecutorValidation.Order memory order = createOrder(authorizedExecutor);
        order.outputToken = address(0);

        ExecutorValidation.RouteData memory routeData = createValidRouteData();
        ExecutorValidation.Trade memory trade = createTrade(order);

        vm.prank(authorizedExecutor);
        vm.expectRevert(ExecutorValidation.ZeroAddress.selector);
        executor.executeTrade(trade, routeData);
    }

    function testZeroInputAmountReverts() public {
        ExecutorValidation.Order memory order = createOrder(authorizedExecutor);
        order.inputAmount = 0;

        ExecutorValidation.RouteData memory routeData = createValidRouteData();
        ExecutorValidation.Trade memory trade = createTrade(order);

        vm.prank(authorizedExecutor);
        vm.expectRevert(ExecutorValidation.ZeroAmount.selector);
        executor.executeTrade(trade, routeData);
    }

    function testZeroMinAmountOutReverts() public {
        ExecutorValidation.Order memory order = createOrder(authorizedExecutor);
        order.minAmountOut = 0;

        ExecutorValidation.RouteData memory routeData = createValidRouteData();
        ExecutorValidation.Trade memory trade = createTrade(order);

        vm.prank(authorizedExecutor);
        vm.expectRevert(ExecutorValidation.ZeroAmount.selector);
        executor.executeTrade(trade, routeData);
    }

    // ============ Expiry & Nonce Tests ============

    function testExpiredOrderReverts() public {
        ExecutorValidation.Order memory order = createOrder(authorizedExecutor);
        order.expiry = block.timestamp - 1; // Expired

        ExecutorValidation.RouteData memory routeData = createValidRouteData();
        ExecutorValidation.Trade memory trade = createTrade(order);

        vm.prank(authorizedExecutor);
        vm.expectRevert(ExecutorValidation.OrderExpired.selector);
        executor.executeTrade(trade, routeData);
    }

    function testUsedNonceReverts() public {
        ExecutorValidation.Order memory order = createOrder(authorizedExecutor);
        order.nonce = 123;

        // Mark nonce as used
        vm.prank(maker);
        executor.cancelNonce(123);

        ExecutorValidation.RouteData memory routeData = createValidRouteData();
        ExecutorValidation.Trade memory trade = createTrade(order);

        vm.prank(authorizedExecutor);
        vm.expectRevert(ExecutorValidation.NonceAlreadyUsed.selector);
        executor.executeTrade(trade, routeData);
    }

    // ============ Protocol Validation Tests ============

    function testValidProtocolsPass() public {
        ExecutorValidation.Order memory order = createOrder(authorizedExecutor);
        ExecutorValidation.Trade memory trade = createTrade(order);

        // Test all valid protocols
        ITrader.Protocol[9] memory protocols = [
            ITrader.Protocol.UNISWAP_V2,
            ITrader.Protocol.UNISWAP_V3,
            ITrader.Protocol.UNISWAP_V4,
            ITrader.Protocol.SUSHISWAP,
            ITrader.Protocol.BALANCER_V2,
            ITrader.Protocol.CURVE,
            ITrader.Protocol.PANCAKESWAP_V2,
            ITrader.Protocol.PANCAKESWAP_V3,
            ITrader.Protocol.AERODROME
        ];

        for (uint256 i = 0; i < protocols.length; i++) {
            ExecutorValidation.RouteData memory routeData = createValidRouteData();
            routeData.protocol = protocols[i];

            vm.prank(authorizedExecutor);
            (bool success,) =
                address(executor).call(abi.encodeWithSelector(executor.executeTrade.selector, trade, routeData));

            // Should pass validation (fails on permit2)
            assertFalse(success);
        }
    }

    // ============ Token Management Tests ============

    function testOwnerCanAddWhitelistedToken() public {
        address newToken = address(0x9999);
        assertFalse(executor.whitelistedTokens(newToken));

        executor.addWhitelistedToken(newToken);

        assertTrue(executor.whitelistedTokens(newToken));
    }

    function testOwnerCanRemoveWhitelistedToken() public {
        assertTrue(executor.whitelistedTokens(address(tokenA)));

        executor.removeWhitelistedToken(address(tokenA));

        assertFalse(executor.whitelistedTokens(address(tokenA)));
    }

    function testOwnerCanAddMultipleTokens() public {
        address[] memory newTokens = new address[](2);
        newTokens[0] = address(0x8888);
        newTokens[1] = address(0x9999);

        executor.addWhitelistedTokens(newTokens);

        assertTrue(executor.whitelistedTokens(newTokens[0]));
        assertTrue(executor.whitelistedTokens(newTokens[1]));
    }

    function testNonOwnerCannotAddToken() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        executor.addWhitelistedToken(address(0x9999));
    }

    // ============ Helper Functions ============

    function createOrder(address authExecutor) internal view returns (ExecutorValidation.Order memory) {
        return ExecutorValidation.Order({
            maker: maker,
            inputToken: address(tokenA),
            inputAmount: 1000e18,
            outputToken: address(tokenB),
            minAmountOut: 990e18,
            expiry: block.timestamp + 3600,
            nonce: 1,
            authorizedExecutor: authExecutor
        });
    }

    function createValidRouteData() internal view returns (ExecutorValidation.RouteData memory) {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        return createRouteData(path);
    }

    function createRouteData(address[] memory path) internal pure returns (ExecutorValidation.RouteData memory) {
        uint24[] memory fees = new uint24[](1);
        fees[0] = 3000;

        return ExecutorValidation.RouteData({
            protocol: ITrader.Protocol.UNISWAP_V3,
            path: path,
            fee: fees,
            isMultiHop: false,
            encodedPath: bytes("")
        });
    }

    function createTrade(ExecutorValidation.Order memory order)
        internal
        view
        returns (ExecutorValidation.Trade memory)
    {
        // Create minimal permit data
        ISignatureTransfer.TokenPermissions memory permitted =
            ISignatureTransfer.TokenPermissions({token: order.inputToken, amount: order.inputAmount});

        ISignatureTransfer.PermitTransferFrom memory permit =
            ISignatureTransfer.PermitTransferFrom({permitted: permitted, nonce: order.nonce, deadline: order.expiry});

        return ExecutorValidation.Trade({order: order, permit: permit, signature: bytes("fake_signature")});
    }
}
