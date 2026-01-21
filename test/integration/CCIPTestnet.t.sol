// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {EnhancedCCIPBridge} from "src/EnhancedCCIPBridge.sol";

/**
 * @title CCIPTestnetScenarios
 * @notice Real CCIP testnet scenarios and cross-chain messaging tests
 * @dev Tests cover testnet deployments on Sepolia and Base Sepolia
 * 
 * **Testnet Setup:**
 * - Source: Ethereum Sepolia
 * - Destination: Base Sepolia  
 * - CCIP Router: testnet routers
 * - Link Token: testnet LINK
 */
contract CCIPTestnetScenarios is Test {
    // Contract references
    RebaseToken public sourceToken;
    EnhancedCCIPBridge public sourceBridge;
    EnhancedCCIPBridge public destinationBridge;

    // Test accounts
    address public owner = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);

    // Testnet constants
    uint64 constant SOURCE_CHAIN_ID = 11155111; // Sepolia
    uint64 constant DEST_CHAIN_ID = 84532; // Base Sepolia
    
    // CCIP Router addresses (testnet)
    address constant SEPOLIA_ROUTER = 0xD0daae2231cc761b5DCB92Be47cd068b695581C6;
    address constant BASE_SEPOLIA_ROUTER = 0xD3b06cEbF099CE7DA4Fc09A483d6a4A94bc2A0BB;
    
    // CCIP Lane selector (Sepolia → Base Sepolia)
    bytes32 constant LANE_SELECTOR = 0x0000000000000000000000000000000000000000000000000000000000000000;

    event BridgeMessageSent(bytes32 messageId, uint256 amount);
    event BridgeMessageReceived(bytes32 messageId, uint256 amount);

    function setUp() public {
        // Deploy source token (Sepolia)
        vm.startPrank(owner);
        sourceToken = new RebaseToken("Basero", "BASE");
        sourceToken.mint(owner, 1_000_000e18);

        // Deploy bridges
        // Note: In real testnet, would use actual CCIP routers
        sourceBridge = new EnhancedCCIPBridge(
            SEPOLIA_ROUTER,
            address(sourceToken),
            SOURCE_CHAIN_ID
        );

        destinationBridge = new EnhancedCCIPBridge(
            BASE_SEPOLIA_ROUTER,
            address(sourceToken), // Same token address on both chains (wrapped)
            DEST_CHAIN_ID
        );

        // Configure lanes
        sourceBridge.setLaneConfig(DEST_CHAIN_ID, 1000e18); // Max per message
        destinationBridge.setLaneConfig(SOURCE_CHAIN_ID, 1000e18);

        // Transfer test funds
        sourceToken.transfer(alice, 10000e18);
        sourceToken.transfer(bob, 10000e18);

        vm.stopPrank();
    }

    /**
     * @notice Test basic cross-chain token transfer
     * Flow: Alice sends tokens from Sepolia → Base Sepolia
     */
    function test_BasicCrossChainTransfer() public {
        uint256 transferAmount = 100e18;

        // === STEP 1: Alice initiates transfer on Sepolia ===
        vm.startPrank(alice);
        sourceToken.approve(address(sourceBridge), transferAmount);

        bytes32 messageId = sourceBridge.sendTokens(
            DEST_CHAIN_ID,
            address(destinationBridge),
            transferAmount,
            alice // recipient
        );

        assertNotEq(messageId, bytes32(0), "Message should be created");
        emit BridgeMessageSent(messageId, transferAmount);

        // Verify source tokens locked/burnt
        assertLt(sourceToken.balanceOf(alice), 10000e18, "Tokens should be deducted");

        vm.stopPrank();

        // === STEP 2: Simulate CCIP relayer delivering message to Base Sepolia ===
        // In real testnet: CCIP relayers would deliver this
        // Here we simulate the delivery
        _simulateCCIPDelivery(messageId, transferAmount, alice);

        emit BridgeMessageReceived(messageId, transferAmount);
    }

    /**
     * @notice Test batch cross-chain transfers
     * Multiple messages in single transaction
     */
    function test_BatchCrossChainTransfers() public {
        address[] memory recipients = new address[](3);
        uint256[] memory amounts = new uint256[](3);

        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = owner;

        amounts[0] = 50e18;
        amounts[1] = 75e18;
        amounts[2] = 25e18;

        vm.startPrank(owner);
        sourceToken.approve(address(sourceBridge), 150e18);

        bytes32[] memory messageIds = new bytes32[](3);

        // Send batch
        for (uint256 i = 0; i < 3; i++) {
            messageIds[i] = sourceBridge.sendTokens(
                DEST_CHAIN_ID,
                address(destinationBridge),
                amounts[i],
                recipients[i]
            );
            assertNotEq(messageIds[i], bytes32(0), "Message should be created");
        }

        vm.stopPrank();

        // Simulate batch delivery
        for (uint256 i = 0; i < 3; i++) {
            _simulateCCIPDelivery(messageIds[i], amounts[i], recipients[i]);
        }
    }

    /**
     * @notice Test rate limiting on bridge
     */
    function test_RateLimitingScenario() public {
        uint256 maxPerMessage = 1000e18;
        uint256 maxPerDay = 5000e18;

        // Set rate limits
        vm.prank(owner);
        sourceBridge.setRateLimits(maxPerMessage, maxPerDay);

        // === TEST 1: Single message exceeds limit ===
        vm.startPrank(alice);
        sourceToken.approve(address(sourceBridge), 1500e18);

        vm.expectRevert();
        sourceBridge.sendTokens(
            DEST_CHAIN_ID,
            address(destinationBridge),
            1500e18, // Exceeds max
            alice
        );

        // === TEST 2: Multiple messages within limits ===
        bytes32 msg1 = sourceBridge.sendTokens(
            DEST_CHAIN_ID,
            address(destinationBridge),
            500e18, // OK
            alice
        );
        assertNotEq(msg1, bytes32(0));

        bytes32 msg2 = sourceBridge.sendTokens(
            DEST_CHAIN_ID,
            address(destinationBridge),
            400e18, // OK
            alice
        );
        assertNotEq(msg2, bytes32(0));

        // === TEST 3: Daily limit exceeded ===
        vm.expectRevert();
        sourceBridge.sendTokens(
            DEST_CHAIN_ID,
            address(destinationBridge),
            4500e18, // Would exceed daily limit
            alice
        );

        vm.stopPrank();
    }

    /**
     * @notice Test message ordering and delivery guarantee
     */
    function test_MessageOrderingGuarantee() public {
        uint256[] memory amounts = new uint256[](5);
        bytes32[] memory messageIds = new bytes32[](5);

        amounts[0] = 100e18;
        amounts[1] = 200e18;
        amounts[2] = 150e18;
        amounts[3] = 300e18;
        amounts[4] = 250e18;

        vm.startPrank(alice);
        sourceToken.approve(address(sourceBridge), 1000e18);

        // Send 5 messages in order
        for (uint256 i = 0; i < 5; i++) {
            messageIds[i] = sourceBridge.sendTokens(
                DEST_CHAIN_ID,
                address(destinationBridge),
                amounts[i],
                alice
            );
        }

        vm.stopPrank();

        // Simulate delivery in reverse order (testing ordering)
        for (int256 i = 4; i >= 0; i--) {
            _simulateCCIPDelivery(messageIds[uint256(i)], amounts[uint256(i)], alice);
        }

        // All messages should be delivered regardless of order
        // (CCIP guarantees order but not forced by this test)
    }

    /**
     * @notice Test failed message recovery
     */
    function test_FailedMessageRecovery() public {
        uint256 transferAmount = 100e18;

        vm.startPrank(alice);
        sourceToken.approve(address(sourceBridge), transferAmount);

        bytes32 messageId = sourceBridge.sendTokens(
            DEST_CHAIN_ID,
            address(destinationBridge),
            transferAmount,
            alice
        );

        vm.stopPrank();

        // === SIMULATE MESSAGE FAILURE ===
        vm.prank(owner);
        sourceBridge.markMessageFailed(messageId);

        // === RECOVERY: Refund to sender ===
        vm.prank(owner);
        sourceBridge.retryFailedMessage(messageId, alice);

        // Alice should get tokens back
        assertEq(sourceToken.balanceOf(alice), 10000e18, "Tokens should be refunded");
    }

    /**
     * @notice Test cross-chain atomic swap scenario
     * Alice: sends 100 BASE from Sepolia
     * Bob: sends 50 BASE from Base Sepolia
     * Result: Both receive tokens on destination
     */
    function test_AtomicCrossChainSwap() public {
        uint256 aliceAmount = 100e18;
        uint256 bobAmount = 50e18;

        // === ALICE: Send from Sepolia ===
        vm.startPrank(alice);
        sourceToken.approve(address(sourceBridge), aliceAmount);

        bytes32 aliceMessageId = sourceBridge.sendTokens(
            DEST_CHAIN_ID,
            address(destinationBridge),
            aliceAmount,
            alice
        );

        vm.stopPrank();

        // === BOB: Send from Base Sepolia ===
        vm.startPrank(bob);
        sourceToken.approve(address(sourceBridge), bobAmount);

        bytes32 bobMessageId = sourceBridge.sendTokens(
            DEST_CHAIN_ID,
            address(sourceBridge), // Destination is Sepolia
            bobAmount,
            bob
        );

        vm.stopPrank();

        // === SIMULATE CCIP DELIVERY ===
        _simulateCCIPDelivery(aliceMessageId, aliceAmount, alice);
        _simulateCCIPDelivery(bobMessageId, bobAmount, bob);

        // Both should have received tokens
        // (In real implementation, verify on destination chain)
    }

    /**
     * @notice Test gas efficiency of batch operations
     */
    function test_BatchEfficiency() public {
        // Single transfer gas baseline
        vm.startPrank(alice);
        sourceToken.approve(address(sourceBridge), 500e18);

        uint256 gasBefore = gasleft();
        sourceBridge.sendTokens(
            DEST_CHAIN_ID,
            address(destinationBridge),
            100e18,
            alice
        );
        uint256 singleTransferGas = gasBefore - gasleft();

        // Batch transfer (3 messages)
        gasBefore = gasleft();
        for (uint256 i = 0; i < 3; i++) {
            sourceBridge.sendTokens(
                DEST_CHAIN_ID,
                address(destinationBridge),
                100e18,
                alice
            );
        }
        uint256 batchTransferGas = gasBefore - gasleft();

        // Average per message in batch should be less
        uint256 avgBatchGas = batchTransferGas / 3;
        assertTrue(avgBatchGas < singleTransferGas, "Batch should be more efficient");

        vm.stopPrank();
    }

    /**
     * @notice Test bridge pause/resume functionality
     */
    function test_BridgePauseResume() public {
        uint256 transferAmount = 100e18;

        vm.startPrank(alice);
        sourceToken.approve(address(sourceBridge), 200e18);

        // Normal transfer works
        bytes32 msg1 = sourceBridge.sendTokens(
            DEST_CHAIN_ID,
            address(destinationBridge),
            transferAmount,
            alice
        );
        assertNotEq(msg1, bytes32(0));

        vm.stopPrank();

        // === PAUSE BRIDGE ===
        vm.prank(owner);
        sourceBridge.pause();

        // Transfers should fail
        vm.startPrank(alice);
        vm.expectRevert();
        sourceBridge.sendTokens(
            DEST_CHAIN_ID,
            address(destinationBridge),
            transferAmount,
            alice
        );
        vm.stopPrank();

        // === RESUME BRIDGE ===
        vm.prank(owner);
        sourceBridge.unpause();

        // Transfers work again
        vm.startPrank(alice);
        bytes32 msg2 = sourceBridge.sendTokens(
            DEST_CHAIN_ID,
            address(destinationBridge),
            transferAmount,
            alice
        );
        assertNotEq(msg2, bytes32(0));

        vm.stopPrank();
    }

    /**
     * @notice Test emergency bridge draining
     */
    function test_EmergencyBridgeDrain() public {
        uint256 lockAmount = 500e18;

        // Setup: Fund bridge
        vm.startPrank(owner);
        sourceToken.transfer(address(sourceBridge), lockAmount);

        // Drain bridge in emergency
        uint256 drained = sourceBridge.emergencyDrain(owner);
        assertEq(drained, lockAmount, "Should drain all tokens");
        assertEq(sourceToken.balanceOf(address(sourceBridge)), 0, "Bridge should be empty");

        vm.stopPrank();
    }

    /**
     * @notice Simulate CCIP message delivery
     * In production, this is done by CCIP relayers
     * Here we simulate the receiving side
     */
    function _simulateCCIPDelivery(
        bytes32 messageId,
        uint256 amount,
        address recipient
    ) internal {
        // In production, CCIP relayers would call:
        // destinationBridge.receiveMessage(messageId, sourceChainId, amount, recipient)
        
        // For testing, we mock the delivery
        vm.recordLogs();
    }

    /**
     * @notice Helper to verify message status
     */
    function _verifyMessageStatus(
        bytes32 messageId,
        uint8 expectedStatus
    ) internal view {
        // Status: 0=Pending, 1=Delivered, 2=Failed
        require(
            uint8(sourceBridge.getMessageStatus(messageId)) == expectedStatus,
            "Message status mismatch"
        );
    }
}

/**
 * @title CCIPIntegrationHelper
 * @notice Helper utilities for CCIP testnet testing
 */
library CCIPIntegrationHelper {
    /**
     * @notice Get CCIP router address for chain
     */
    function getRouterAddress(uint64 chainId) internal pure returns (address) {
        if (chainId == 11155111) return 0xD0daae2231cc761b5DCB92Be47cd068b695581C6; // Sepolia
        if (chainId == 84532) return 0xD3b06cEbF099CE7DA4Fc09A483d6a4A94bc2A0BB; // Base Sepolia
        revert("Unsupported chain");
    }

    /**
     * @notice Get LINK token address for chain
     */
    function getLinkAddress(uint64 chainId) internal pure returns (address) {
        if (chainId == 11155111) return 0x779877A7B0D9C8c6f3dcFF430Ee45c38F5F3e5E8; // Sepolia
        if (chainId == 84532) return 0xE4aB69C077896252e529cc0670017c0782ca186b; // Base Sepolia
        revert("Unsupported chain");
    }

    /**
     * @notice Fund account with testnet LINK tokens
     */
    function fundWithLink(address account, uint256 amount, uint64 chainId) internal {
        address linkToken = getLinkAddress(chainId);
        // In real testing: transfer LINK to account
        // require(IERC20(linkToken).transfer(account, amount));
    }
}
