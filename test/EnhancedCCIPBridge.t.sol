// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {EnhancedCCIPBridge} from "../src/EnhancedCCIPBridge.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

// Mock CCIP Router
contract MockCCIPRouter {
    function ccipSend(uint64 destinationChainSelector, Client.EVM2AnyMessage calldata message)
        external
        returns (bytes32)
    {
        return keccak256(abi.encode(destinationChainSelector, message));
    }

    function getFee(uint64 destinationChainSelector, Client.EVM2AnyMessage calldata message)
        external
        pure
        returns (uint256)
    {
        return 1 * 10**18; // 1 LINK
    }
}

// Mock LINK token
contract MockLINK {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/**
 * @title EnhancedCCIPBridgeTest
 * @dev Comprehensive test suite for enhanced CCIP bridge
 */
contract EnhancedCCIPBridgeTest is Test {
    EnhancedCCIPBridge public bridge;
    RebaseToken public token;
    MockCCIPRouter public router;
    MockLINK public linkToken;

    address public owner;
    address public alice;
    address public bob;
    address public feeRecipient;

    // Chain selectors
    uint64 constant ETHEREUM_SELECTOR = 1;
    uint64 constant POLYGON_SELECTOR = 2;
    uint64 constant SCROLL_SELECTOR = 3;
    uint64 constant ZKSYNC_SELECTOR = 4;
    uint64 constant ARBITRUM_SELECTOR = 5;

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        feeRecipient = makeAddr("feeRecipient");

        // Deploy mock dependencies
        router = new MockCCIPRouter();
        linkToken = new MockLINK();

        // Deploy token
        token = new RebaseToken("Rebase Token", "RBT");

        // Deploy bridge
        bridge = new EnhancedCCIPBridge(address(router), address(linkToken), address(token));

        // Fund with LINK
        linkToken.mint(address(bridge), 1000 * 10**18);

        // Configure chains
        bridge.configureChain(POLYGON_SELECTOR, address(0x111), 1 ether, 1000 ether, 1 days);
        bridge.configureChain(SCROLL_SELECTOR, address(0x222), 0.5 ether, 500 ether, 1 days);
        bridge.configureChain(ZKSYNC_SELECTOR, address(0x333), 2 ether, 2000 ether, 1 days);
        bridge.configureChain(ARBITRUM_SELECTOR, address(0x444), 0.1 ether, 10000 ether, 1 days);
    }

    // ============= Chain Configuration Tests =============

    function test_ConfigureChain() public {
        uint64 chainSelector = 42;
        address receiver = address(0x999);

        bridge.configureChain(chainSelector, receiver, 1 ether, 100 ether, 1 hours);

        (bool enabled, address configReceiver, uint256 minAmount, uint256 maxAmount, uint256 batchWindow) =
            bridge.getChainConfig(chainSelector);

        assertTrue(enabled);
        assertEq(configReceiver, receiver);
        assertEq(minAmount, 1 ether);
        assertEq(maxAmount, 100 ether);
        assertEq(batchWindow, 1 hours);
    }

    function test_DisableChain() public {
        bridge.disableChain(POLYGON_SELECTOR);

        (bool enabled, , , , ) = bridge.getChainConfig(POLYGON_SELECTOR);
        assertFalse(enabled);
    }

    function test_ConfigureChain_InvalidReceiver() public {
        vm.expectRevert(EnhancedCCIPBridge.InvalidReceiverAddress.selector);
        bridge.configureChain(99, address(0), 1 ether, 100 ether, 1 hours);
    }

    function test_ConfigureChain_InvalidAmounts() public {
        vm.expectRevert(EnhancedCCIPBridge.BridgeAmountOutOfBounds.selector);
        bridge.configureChain(99, address(0x999), 100 ether, 1 ether, 1 hours);
    }

    // ============= Rate Limiting Tests =============

    function test_SetRateLimit() public {
        bridge.setRateLimit(POLYGON_SELECTOR, 1000 * 10**18, 10000 * 10**18);

        (uint256 tokensPerSecond, uint256 maxBurst, uint256 available, ) =
            bridge.getRateLimitStatus(POLYGON_SELECTOR);

        assertEq(tokensPerSecond, 1000 * 10**18);
        assertEq(maxBurst, 10000 * 10**18);
        assertEq(available, 10000 * 10**18);
    }

    function test_RateLimit_Refill() public {
        bridge.setRateLimit(POLYGON_SELECTOR, 1000 * 10**18, 10000 * 10**18);

        // Wait time
        vm.warp(block.timestamp + 10); // 10 seconds

        (, , uint256 available, ) = bridge.getRateLimitStatus(POLYGON_SELECTOR);

        // Should have 10,000 (max burst) + 10 seconds * 1000 = still 10,000 (capped)
        assertEq(available, 10000 * 10**18);
    }

    function test_RateLimit_Consumption() public {
        bridge.setRateLimit(POLYGON_SELECTOR, 100, 1000);

        // Consume some tokens
        bridge.bridgeTokens(POLYGON_SELECTOR, bob, 1 ether);

        // Should have consumed tokens
        (, , uint256 available, ) = bridge.getRateLimitStatus(POLYGON_SELECTOR);
        assertLt(available, 1000);
    }

    // ============= Batch Transfer Tests =============

    function test_CreateBatchTransfer() public {
        address[] memory recipients = new address[](3);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = feeRecipient;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10 ether;
        amounts[1] = 20 ether;
        amounts[2] = 30 ether;

        uint256 batchId = bridge.createBatchTransfer(POLYGON_SELECTOR, recipients, amounts);

        assertEq(batchId, 0);

        (uint256 id, uint64 chain, uint256 total, uint256 count, , bool executed) =
            bridge.getBatchDetails(batchId);

        assertEq(id, 0);
        assertEq(chain, POLYGON_SELECTOR);
        assertEq(total, 60 ether);
        assertEq(count, 3);
        assertFalse(executed);
    }

    function test_CreateBatchTransfer_EmptyArray() public {
        address[] memory recipients = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.expectRevert(EnhancedCCIPBridge.EmptyBatchTransfer.selector);
        bridge.createBatchTransfer(POLYGON_SELECTOR, recipients, amounts);
    }

    function test_CreateBatchTransfer_MismatchedLengths() public {
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10 ether;
        amounts[1] = 20 ether;
        amounts[2] = 30 ether;

        vm.expectRevert(EnhancedCCIPBridge.BatchAmountMismatch.selector);
        bridge.createBatchTransfer(POLYGON_SELECTOR, recipients, amounts);
    }

    function test_CreateBatchTransfer_AmountOutOfBounds() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 2000 ether; // Exceeds max of 1000 ether

        vm.expectRevert(EnhancedCCIPBridge.BridgeAmountOutOfBounds.selector);
        bridge.createBatchTransfer(POLYGON_SELECTOR, recipients, amounts);
    }

    function test_CreateBatchTransfer_DisabledChain() public {
        bridge.disableChain(POLYGON_SELECTOR);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;

        vm.expectRevert(EnhancedCCIPBridge.ChainNotConfigured.selector);
        bridge.createBatchTransfer(POLYGON_SELECTOR, recipients, amounts);
    }

    function test_ExecuteBatch() public {
        // Create batch
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10 ether;
        amounts[1] = 20 ether;

        uint256 batchId = bridge.createBatchTransfer(POLYGON_SELECTOR, recipients, amounts);

        // Execute batch
        bytes32 messageId = bridge.executeBatch(batchId);
        assertNotEq(messageId, bytes32(0));

        (, , , , , bool executed) = bridge.getBatchDetails(batchId);
        assertTrue(executed);
    }

    function test_ExecuteBatch_AlreadyExecuted() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;

        uint256 batchId = bridge.createBatchTransfer(POLYGON_SELECTOR, recipients, amounts);

        bridge.executeBatch(batchId);

        // Try to execute again
        vm.expectRevert(EnhancedCCIPBridge.BatchAlreadyExecuted.selector);
        bridge.executeBatch(batchId);
    }

    function test_ExecuteBatch_InsufficientLink() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;

        uint256 batchId = bridge.createBatchTransfer(POLYGON_SELECTOR, recipients, amounts);

        // Drain LINK
        bridge.withdrawLink(linkToken.balanceOf(address(bridge)));

        vm.expectRevert(EnhancedCCIPBridge.InsufficientLinkBalance.selector);
        bridge.executeBatch(batchId);
    }

    function test_GetBatchTransfers() public {
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10 ether;
        amounts[1] = 20 ether;

        uint256 batchId = bridge.createBatchTransfer(POLYGON_SELECTOR, recipients, amounts);

        (address[] memory retrievedRecipients, uint256[] memory retrievedAmounts) =
            bridge.getBatchTransfers(batchId);

        assertEq(retrievedRecipients.length, 2);
        assertEq(retrievedRecipients[0], alice);
        assertEq(retrievedRecipients[1], bob);
        assertEq(retrievedAmounts[0], 10 ether);
        assertEq(retrievedAmounts[1], 20 ether);
    }

    // ============= Single Transfer Tests =============

    function test_BridgeTokens() public {
        bytes32 messageId = bridge.bridgeTokens(POLYGON_SELECTOR, alice, 10 ether);
        assertNotEq(messageId, bytes32(0));
    }

    function test_BridgeTokens_AmountTooLow() public {
        vm.expectRevert(EnhancedCCIPBridge.BridgeAmountOutOfBounds.selector);
        bridge.bridgeTokens(POLYGON_SELECTOR, alice, 0.5 ether); // Min is 1 ether
    }

    function test_BridgeTokens_AmountTooHigh() public {
        vm.expectRevert(EnhancedCCIPBridge.BridgeAmountOutOfBounds.selector);
        bridge.bridgeTokens(POLYGON_SELECTOR, alice, 1001 ether); // Max is 1000 ether
    }

    function test_BridgeTokens_ChainDisabled() public {
        bridge.disableChain(POLYGON_SELECTOR);

        vm.expectRevert(EnhancedCCIPBridge.ChainNotConfigured.selector);
        bridge.bridgeTokens(POLYGON_SELECTOR, alice, 10 ether);
    }

    function test_BridgeTokens_InsufficientLink() public {
        bridge.withdrawLink(linkToken.balanceOf(address(bridge)));

        vm.expectRevert(EnhancedCCIPBridge.InsufficientLinkBalance.selector);
        bridge.bridgeTokens(POLYGON_SELECTOR, alice, 10 ether);
    }

    // ============= Composability Tests =============

    function test_SetComposableRoute() public {
        bytes32 routeId = keccak256("route1");
        address targetContract = address(0x777);
        bytes memory callData = abi.encodeWithSignature("swap(uint256)", 100);

        bridge.setComposableRoute(routeId, POLYGON_SELECTOR, targetContract, callData, true);

        // Verify route was set (via execution test)
    }

    function test_ExecuteComposableCall() public {
        bytes32 routeId = keccak256("route1");
        address targetContract = address(0x777);
        bytes memory callData = abi.encodeWithSignature("swap(uint256)", 100);

        bridge.setComposableRoute(routeId, POLYGON_SELECTOR, targetContract, callData, true);

        bytes32 messageId = bridge.executeComposableCall(routeId, 10 ether);
        assertNotEq(messageId, bytes32(0));
    }

    function test_ExecuteComposableCall_RouteNotSet() public {
        bytes32 routeId = keccak256("nonexistent");

        vm.expectRevert(EnhancedCCIPBridge.ComposableRouteNotSet.selector);
        bridge.executeComposableCall(routeId, 10 ether);
    }

    // ============= Multi-Chain Tests =============

    function test_MultiChainBridging() public {
        // Bridge to multiple chains in sequence
        bytes32 msg1 = bridge.bridgeTokens(POLYGON_SELECTOR, alice, 10 ether);
        bytes32 msg2 = bridge.bridgeTokens(SCROLL_SELECTOR, bob, 5 ether);
        bytes32 msg3 = bridge.bridgeTokens(ZKSYNC_SELECTOR, feeRecipient, 15 ether);

        assertNotEq(msg1, bytes32(0));
        assertNotEq(msg2, bytes32(0));
        assertNotEq(msg3, bytes32(0));
        assertNotEq(msg1, msg2);
        assertNotEq(msg2, msg3);
    }

    function test_MultiBatchPerChain() public {
        address[] memory recipients1 = new address[](1);
        recipients1[0] = alice;

        uint256[] memory amounts1 = new uint256[](1);
        amounts1[0] = 10 ether;

        address[] memory recipients2 = new address[](1);
        recipients2[0] = bob;

        uint256[] memory amounts2 = new uint256[](1);
        amounts2[0] = 20 ether;

        uint256 batch1 = bridge.createBatchTransfer(POLYGON_SELECTOR, recipients1, amounts1);
        uint256 batch2 = bridge.createBatchTransfer(POLYGON_SELECTOR, recipients2, amounts2);

        assertEq(batch1, 0);
        assertEq(batch2, 1);

        uint256[] memory chainBatches = bridge.getChainBatches(POLYGON_SELECTOR);
        assertEq(chainBatches.length, 2);
        assertEq(chainBatches[0], 0);
        assertEq(chainBatches[1], 1);
    }

    // ============= Pause/Unpause Tests =============

    function test_PauseBridging() public {
        bridge.pauseBridging();

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;

        vm.expectRevert();
        bridge.createBatchTransfer(POLYGON_SELECTOR, recipients, amounts);
    }

    function test_UnpauseBridging() public {
        bridge.pauseBridging();
        bridge.unpauseBridging();

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;

        uint256 batchId = bridge.createBatchTransfer(POLYGON_SELECTOR, recipients, amounts);
        assertEq(batchId, 0);
    }

    // ============= Admin Tests =============

    function test_WithdrawLink() public {
        uint256 balanceBefore = linkToken.balanceOf(owner);
        uint256 withdrawAmount = 10 * 10**18;

        bridge.withdrawLink(withdrawAmount);

        uint256 balanceAfter = linkToken.balanceOf(owner);
        assertEq(balanceAfter - balanceBefore, withdrawAmount);
    }

    function test_OnlyOwner_ConfigureChain() public {
        vm.prank(alice);
        vm.expectRevert();
        bridge.configureChain(42, address(0x999), 1 ether, 100 ether, 1 hours);
    }

    function test_OnlyOwner_SetRateLimit() public {
        vm.prank(alice);
        vm.expectRevert();
        bridge.setRateLimit(POLYGON_SELECTOR, 1000 * 10**18, 10000 * 10**18);
    }

    // ============= Edge Cases & Fuzz =============

    function test_CreateBatchTransfer_LargeArray(uint8 recipientCount) public {
        recipientCount = uint8(bound(recipientCount, 1, 50));

        address[] memory recipients = new address[](recipientCount);
        uint256[] memory amounts = new uint256[](recipientCount);

        for (uint256 i = 0; i < recipientCount; i++) {
            recipients[i] = makeAddr(string(abi.encodePacked("user", i)));
            amounts[i] = 10 ether;
        }

        uint256 batchId = bridge.createBatchTransfer(POLYGON_SELECTOR, recipients, amounts);

        (uint256 id, , uint256 total, uint256 count, , ) = bridge.getBatchDetails(batchId);

        assertEq(id, 0);
        assertEq(total, uint256(recipientCount) * 10 ether);
        assertEq(count, recipientCount);
    }

    function test_BridgeTokens_Fuzz(uint256 amount) public {
        amount = bound(amount, 1 ether, 1000 ether);

        bytes32 messageId = bridge.bridgeTokens(POLYGON_SELECTOR, alice, amount);
        assertNotEq(messageId, bytes32(0));
    }

    function test_MultiChainBridging_AllChains() public {
        bridge.bridgeTokens(POLYGON_SELECTOR, alice, 10 ether);
        bridge.bridgeTokens(SCROLL_SELECTOR, bob, 5 ether);
        bridge.bridgeTokens(ZKSYNC_SELECTOR, feeRecipient, 15 ether);
        bridge.bridgeTokens(ARBITRUM_SELECTOR, alice, 100 ether);
    }
}
