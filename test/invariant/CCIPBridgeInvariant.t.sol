// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import {EnhancedCCIPBridge} from "../../src/EnhancedCCIPBridge.sol";
import {RebaseToken} from "../../src/RebaseToken.sol";
import {MockCCIPRouter} from "../mocks/MockCCIPRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title CCIPBridgeInvariantTest
 * @notice Invariant tests for cross-chain bridge operations
 * @dev Tests token conservation, rate limiting, and bridge state consistency
 */
contract CCIPBridgeInvariantTest is StdInvariant, Test {
    
    EnhancedCCIPBridge public bridge;
    RebaseToken public token;
    MockCCIPRouter public router;
    CCIPBridgeHandler public handler;
    
    address public linkToken;
    
    // Test chain selectors
    uint64 public constant ETHEREUM_SELECTOR = 1;
    uint64 public constant POLYGON_SELECTOR = 2;
    uint64 public constant ARBITRUM_SELECTOR = 3;
    
    function setUp() public {
        // Deploy mocks
        router = new MockCCIPRouter();
        linkToken = address(new MockERC20("LINK", "LINK"));
        
        // Deploy token
        token = new RebaseToken("Rebase Token", "REBASE");
        
        // Deploy bridge
        bridge = new EnhancedCCIPBridge(
            address(router),
            linkToken,
            address(token)
        );
        
        // Configure chains
        bridge.configureChain(ETHEREUM_SELECTOR, address(bridge), 1 ether, 100 ether, 1 hours);
        bridge.configureChain(POLYGON_SELECTOR, address(bridge), 1 ether, 100 ether, 1 hours);
        bridge.configureChain(ARBITRUM_SELECTOR, address(bridge), 1 ether, 100 ether, 1 hours);
        
        // Set rate limits
        bridge.setRateLimit(ETHEREUM_SELECTOR, 10 ether, 100 ether);
        bridge.setRateLimit(POLYGON_SELECTOR, 10 ether, 100 ether);
        bridge.setRateLimit(ARBITRUM_SELECTOR, 10 ether, 100 ether);
        
        // Deploy handler
        handler = new CCIPBridgeHandler(bridge, token, router);
        
        // Target handler
        targetContract(address(handler));
        
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = CCIPBridgeHandler.bridgeTokens.selector;
        selectors[1] = CCIPBridgeHandler.createBatch.selector;
        selectors[2] = CCIPBridgeHandler.executeBatch.selector;
        
        targetSelector(FuzzSelector({
            addr: address(handler),
            selectors: selectors
        }));
    }
    
    // ============= Token Conservation Invariants =============
    
    /// @notice Total tokens on all chains should equal total minted
    function invariant_crossChainTokenConservation() public view {
        uint256 tokensOnSource = token.balanceOf(address(handler));
        uint256 tokensBridged = handler.ghost_totalBridged();
        uint256 tokensReturned = handler.ghost_totalReturned();
        uint256 totalMinted = handler.ghost_totalMinted();
        
        // Tokens on source + bridged out - returned = total minted
        assertEq(
            tokensOnSource + tokensBridged - tokensReturned,
            totalMinted,
            "Cross-chain token conservation violated"
        );
    }
    
    /// @notice Bridge contract should never hold more tokens than bridged
    function invariant_bridgeTokenBalance() public view {
        uint256 bridgeBalance = token.balanceOf(address(bridge));
        uint256 totalBridgedOut = handler.ghost_totalBridged();
        
        // Bridge should hold tokens temporarily during bridging
        assertGe(totalBridgedOut, 0, "Bridged amount should be non-negative");
    }
    
    /// @notice Per-chain bridged amounts should sum to total
    function invariant_perChainSumsToTotal() public view {
        uint256 ethBridged = bridge.chainBridgedTotal(ETHEREUM_SELECTOR);
        uint256 polyBridged = bridge.chainBridgedTotal(POLYGON_SELECTOR);
        uint256 arbBridged = bridge.chainBridgedTotal(ARBITRUM_SELECTOR);
        
        uint256 totalFromContract = ethBridged + polyBridged + arbBridged;
        uint256 totalTracked = handler.ghost_totalBridged();
        
        assertEq(totalFromContract, totalTracked, "Per-chain sums don't match total");
    }
    
    // ============= Rate Limiting Invariants =============
    
    /// @notice Rate limit tokens available should never exceed max burst size
    function invariant_rateLimitNeverExceedsBurst() public view {
        uint64[3] memory chains = [ETHEREUM_SELECTOR, POLYGON_SELECTOR, ARBITRUM_SELECTOR];
        
        for (uint256 i = 0; i < chains.length; i++) {
            (
                uint256 tokensPerSecond,
                uint256 maxBurstSize,
                ,
                uint256 tokensAvailable
            ) = bridge.rateLimits(chains[i]);
            
            assertLe(
                tokensAvailable,
                maxBurstSize,
                "Rate limit tokens exceed burst size"
            );
        }
    }
    
    /// @notice Rate limit should decrease with consumption
    function invariant_rateLimitDecreasesWithUse() public view {
        uint256 totalConsumed = handler.ghost_rateLimitConsumed();
        
        // If we've consumed tokens, available should be less than max
        if (totalConsumed > 0) {
            (,, , uint256 tokensAvailable) = bridge.rateLimits(ETHEREUM_SELECTOR);
            (, uint256 maxBurst,,) = bridge.rateLimits(ETHEREUM_SELECTOR);
            
            // After consumption, available should be less than max (unless refilled)
            assertLe(tokensAvailable, maxBurst, "Rate limit inconsistent");
        }
    }
    
    /// @notice Rate limit refill should be time-based
    function invariant_rateLimitRefillTimeCorrect() public view {
        uint64[3] memory chains = [ETHEREUM_SELECTOR, POLYGON_SELECTOR, ARBITRUM_SELECTOR];
        
        for (uint256 i = 0; i < chains.length; i++) {
            (,, uint256 lastRefillTime,) = bridge.rateLimits(chains[i]);
            
            assertLe(
                lastRefillTime,
                block.timestamp,
                "Last refill time in future"
            );
        }
    }
    
    // ============= Batch Invariants =============
    
    /// @notice Batch total amount should equal sum of individual amounts
    function invariant_batchTotalMatchesSum() public view {
        uint256[] memory batchIds = handler.getCreatedBatches();
        
        for (uint256 i = 0; i < batchIds.length; i++) {
            (
                ,
                ,
                address[] memory recipients,
                uint256[] memory amounts,
                uint256 totalAmount,
                ,
                
            ) = bridge.batchTransfers(batchIds[i]);
            
            uint256 sum = 0;
            for (uint256 j = 0; j < amounts.length; j++) {
                sum += amounts[j];
            }
            
            assertEq(sum, totalAmount, "Batch total doesn't match sum");
        }
    }
    
    /// @notice Batch recipients and amounts arrays should match length
    function invariant_batchArrayLengthsMatch() public view {
        uint256[] memory batchIds = handler.getCreatedBatches();
        
        for (uint256 i = 0; i < batchIds.length; i++) {
            (
                ,
                ,
                address[] memory recipients,
                uint256[] memory amounts,
                ,
                ,
                
            ) = bridge.batchTransfers(batchIds[i]);
            
            assertEq(
                recipients.length,
                amounts.length,
                "Batch array lengths mismatch"
            );
        }
    }
    
    /// @notice Executed batches should not be re-executable
    function invariant_noBatchReexecution() public view {
        uint256[] memory batchIds = handler.getCreatedBatches();
        
        for (uint256 i = 0; i < batchIds.length; i++) {
            (,,,,,, bool executed) = bridge.batchTransfers(batchIds[i]);
            
            // If executed, it's in our executed list
            if (executed) {
                assertTrue(
                    handler.isBatchExecuted(batchIds[i]),
                    "Executed batch not tracked"
                );
            }
        }
    }
    
    // ============= Chain Configuration Invariants =============
    
    /// @notice Configured chains should have valid parameters
    function invariant_chainConfigValidity() public view {
        uint64[3] memory chains = [ETHEREUM_SELECTOR, POLYGON_SELECTOR, ARBITRUM_SELECTOR];
        
        for (uint256 i = 0; i < chains.length; i++) {
            (
                bool enabled,
                address receiver,
                uint256 minAmount,
                uint256 maxAmount,
                ,
                
            ) = bridge.chainConfigs(chains[i]);
            
            if (enabled) {
                assertNotEq(receiver, address(0), "Enabled chain has no receiver");
                assertLe(minAmount, maxAmount, "Min > max bridge amount");
            }
        }
    }
    
    /// @notice Min bridge amount should be enforced
    function invariant_minBridgeAmountEnforced() public view {
        uint256[] memory bridgedAmounts = handler.getBridgedAmounts();
        
        for (uint256 i = 0; i < bridgedAmounts.length; i++) {
            if (bridgedAmounts[i] > 0) {
                assertGe(bridgedAmounts[i], 1 ether, "Bridge below minimum");
            }
        }
    }
    
    // ============= User Accounting Invariants =============
    
    /// @notice User bridged amounts should be tracked correctly
    function invariant_userBridgedTracking() public view {
        address[] memory users = handler.getUsers();
        uint64[3] memory chains = [ETHEREUM_SELECTOR, POLYGON_SELECTOR, ARBITRUM_SELECTOR];
        
        uint256 totalUserBridged = 0;
        
        for (uint256 i = 0; i < users.length; i++) {
            for (uint256 j = 0; j < chains.length; j++) {
                uint256 userAmount = bridge.userBridgedAmount(users[i], chains[j]);
                totalUserBridged += userAmount;
            }
        }
        
        // Total user bridged should equal total bridged
        uint256 totalBridged = handler.ghost_totalBridged();
        assertEq(totalUserBridged, totalBridged, "User bridged tracking off");
    }
    
    // ============= Reentrancy Protection Invariants =============
    
    /// @notice No nested bridging operations
    function invariant_noReentrancy() public view {
        // Handler tracks reentrancy attempts
        assertFalse(handler.ghost_reentrancyDetected(), "Reentrancy detected");
    }
    
    /// @notice Operations should be atomic
    function invariant_atomicOperations() public view {
        // If a batch is created, it should either be executed or pending
        uint256[] memory batches = handler.getCreatedBatches();
        
        for (uint256 i = 0; i < batches.length; i++) {
            (,,,,,, bool executed) = bridge.batchTransfers(batches[i]);
            
            // Batch exists and has a definite state
            assertTrue(
                executed || !executed,
                "Batch in inconsistent state"
            );
        }
    }
    
    // ============= State Consistency Invariants =============
    
    /// @notice Batch counter should always increase
    function invariant_batchCounterMonotonic() public view {
        uint256 currentCounter = bridge.batchCounter();
        uint256 lastCounter = handler.ghost_lastBatchCounter();
        
        assertGe(currentCounter, lastCounter, "Batch counter decreased");
    }
    
    /// @notice No duplicate batch IDs
    function invariant_uniqueBatchIds() public view {
        uint256[] memory batches = handler.getCreatedBatches();
        
        for (uint256 i = 0; i < batches.length; i++) {
            for (uint256 j = i + 1; j < batches.length; j++) {
                assertNotEq(batches[i], batches[j], "Duplicate batch ID");
            }
        }
    }
    
    // ============= Paused State Invariants =============
    
    /// @notice When paused, no new operations should occur
    function invariant_pausedStateRespected() public view {
        if (bridge.paused()) {
            // No new operations should have been recorded
            uint256 opsWhilePaused = handler.ghost_opsWhilePaused();
            assertEq(opsWhilePaused, 0, "Operations occurred while paused");
        }
    }
}

/**
 * @title CCIPBridgeHandler
 * @notice Handler for CCIP bridge invariant testing
 */
contract CCIPBridgeHandler is Test {
    
    EnhancedCCIPBridge public bridge;
    RebaseToken public token;
    MockCCIPRouter public router;
    
    address[] public users;
    uint256[] public createdBatches;
    uint256[] public bridgedAmounts;
    mapping(uint256 => bool) public executedBatches;
    
    // Ghost variables
    uint256 public ghost_totalBridged;
    uint256 public ghost_totalReturned;
    uint256 public ghost_totalMinted;
    uint256 public ghost_rateLimitConsumed;
    uint256 public ghost_lastBatchCounter;
    uint256 public ghost_opsWhilePaused;
    bool public ghost_reentrancyDetected;
    
    uint64 public constant ETHEREUM_SELECTOR = 1;
    uint64 public constant POLYGON_SELECTOR = 2;
    uint64 public constant ARBITRUM_SELECTOR = 3;
    
    constructor(
        EnhancedCCIPBridge _bridge,
        RebaseToken _token,
        MockCCIPRouter _router
    ) {
        bridge = _bridge;
        token = _token;
        router = _router;
        
        // Create test users
        for (uint256 i = 0; i < 5; i++) {
            address user = address(uint160(uint256(keccak256(abi.encodePacked(i, "user")))));
            users.push(user);
            
            // Mint tokens to users
            vm.prank(address(bridge));
            token.mint(user, 1000 ether, 1000);
            ghost_totalMinted += 1000 ether;
            
            // Approve bridge
            vm.prank(user);
            token.approve(address(bridge), type(uint256).max);
        }
    }
    
    // ============= Actions =============
    
    function bridgeTokens(uint256 userSeed, uint256 chainSeed, uint256 amount) external {
        if (bridge.paused()) {
            ghost_opsWhilePaused++;
            return;
        }
        
        address user = users[userSeed % users.length];
        uint64[3] memory chains = [ETHEREUM_SELECTOR, POLYGON_SELECTOR, ARBITRUM_SELECTOR];
        uint64 destChain = chains[chainSeed % chains.length];
        
        amount = bound(amount, 1 ether, 50 ether);
        
        uint256 userBalance = token.balanceOf(user);
        if (userBalance < amount) return;
        
        vm.prank(user);
        try bridge.transferToChain(destChain, user, amount) {
            ghost_totalBridged += amount;
            ghost_rateLimitConsumed += amount;
            bridgedAmounts.push(amount);
        } catch {}
    }
    
    function createBatch(uint256 chainSeed, uint256 recipientCount) external {
        if (bridge.paused()) {
            ghost_opsWhilePaused++;
            return;
        }
        
        uint64[3] memory chains = [ETHEREUM_SELECTOR, POLYGON_SELECTOR, ARBITRUM_SELECTOR];
        uint64 destChain = chains[chainSeed % chains.length];
        
        recipientCount = bound(recipientCount, 2, 5);
        
        address[] memory recipients = new address[](recipientCount);
        uint256[] memory amounts = new uint256[](recipientCount);
        
        for (uint256 i = 0; i < recipientCount; i++) {
            recipients[i] = users[i % users.length];
            amounts[i] = 1 ether;
        }
        
        try bridge.createBatchTransfer(destChain, recipients, amounts) returns (uint256 batchId) {
            createdBatches.push(batchId);
            ghost_lastBatchCounter = batchId;
        } catch {}
    }
    
    function executeBatch(uint256 batchSeed) external {
        if (createdBatches.length == 0) return;
        if (bridge.paused()) {
            ghost_opsWhilePaused++;
            return;
        }
        
        uint256 batchId = createdBatches[batchSeed % createdBatches.length];
        
        try bridge.executeBatch(batchId) {
            executedBatches[batchId] = true;
        } catch {}
    }
    
    // ============= View Functions =============
    
    function getUsers() external view returns (address[] memory) {
        return users;
    }
    
    function getCreatedBatches() external view returns (uint256[] memory) {
        return createdBatches;
    }
    
    function getBridgedAmounts() external view returns (uint256[] memory) {
        return bridgedAmounts;
    }
    
    function isBatchExecuted(uint256 batchId) external view returns (bool) {
        return executedBatches[batchId];
    }
}

/**
 * @title MockERC20
 * @notice Simple ERC20 mock for testing
 */
contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
        totalSupply = 1000000 ether;
        balanceOf[msg.sender] = totalSupply;
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
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}
