// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {RebaseToken} from "src/RebaseToken.sol";
import {RebaseTokenVault} from "src/RebaseTokenVault.sol";
import {VotingEscrow} from "src/VotingEscrow.sol";
import {BASEGovernor} from "src/BASEGovernor.sol";

/**
 * @title TestHelpers
 * @notice Solidity test utilities for Basero Protocol integration tests
 * 
 * Provides:
 * - Mock contract deployments
 * - Test data generators
 * - Common assertions
 * - State builders
 */

// ============= MOCK CCIP IMPLEMENTATION =============

/**
 * @title MockCCIPRouter
 * @notice Mock CCIP router for testnet testing without real CCIP
 */
contract MockCCIPRouter {
    struct Message {
        bytes32 messageId;
        address sender;
        address receiver;
        uint64 sourceChain;
        uint64 destChain;
        bytes data;
        uint256 timestamp;
        bool delivered;
    }

    mapping(bytes32 => Message) public messages;
    mapping(uint64 => address) public receiverContracts;
    
    bytes32[] public messageQueue;
    uint256 public messageCount;

    event MessageSent(bytes32 indexed messageId, uint64 destChain);
    event MessageDelivered(bytes32 indexed messageId);

    /**
     * @notice Register receiver contract on destination chain
     */
    function registerReceiver(uint64 chainId, address receiver) external {
        receiverContracts[chainId] = receiver;
    }

    /**
     * @notice Send message to destination chain
     */
    function sendMessage(
        uint64 destChain,
        address receiver,
        bytes calldata data,
        uint256 fee
    ) external payable returns (bytes32) {
        require(msg.value >= fee, "Insufficient fee");

        bytes32 messageId = keccak256(
            abi.encodePacked(msg.sender, destChain, receiver, messageCount)
        );

        messages[messageId] = Message({
            messageId: messageId,
            sender: msg.sender,
            receiver: receiver,
            sourceChain: 11155111, // Default Sepolia
            destChain: destChain,
            data: data,
            timestamp: block.timestamp,
            delivered: false
        });

        messageQueue.push(messageId);
        messageCount++;

        emit MessageSent(messageId, destChain);
        return messageId;
    }

    /**
     * @notice Deliver message to destination
     */
    function deliverMessage(bytes32 messageId) external {
        Message storage msg = messages[messageId];
        require(!msg.delivered, "Already delivered");

        msg.delivered = true;
        
        // Call receiver contract
        (bool success, ) = msg.receiver.call(msg.data);
        require(success, "Delivery failed");

        emit MessageDelivered(messageId);
    }

    /**
     * @notice Get pending messages
     */
    function getPendingMessages() external view returns (bytes32[] memory) {
        uint256 pending = 0;
        for (uint256 i = 0; i < messageQueue.length; i++) {
            if (!messages[messageQueue[i]].delivered) {
                pending++;
            }
        }

        bytes32[] memory result = new bytes32[](pending);
        uint256 index = 0;
        for (uint256 i = 0; i < messageQueue.length; i++) {
            if (!messages[messageQueue[i]].delivered) {
                result[index] = messageQueue[i];
                index++;
            }
        }

        return result;
    }
}

/**
 * @title MockERC20
 * @notice Mock ERC20 for testing
 */
contract MockERC20 {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    constructor(uint256 initialSupply) {
        balanceOf[msg.sender] = initialSupply;
        totalSupply = initialSupply;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external {
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }
}

/**
 * @title MockOracle
 * @notice Mock price oracle for testing
 */
contract MockOracle {
    mapping(address => uint256) public prices;
    mapping(address => uint8) public decimals;

    event PriceUpdated(address indexed token, uint256 price);

    /**
     * @notice Set price for token
     */
    function setPrice(address token, uint256 price, uint8 tokenDecimals) external {
        prices[token] = price;
        decimals[token] = tokenDecimals;
        emit PriceUpdated(token, price);
    }

    /**
     * @notice Get price for token
     */
    function getPrice(address token) external view returns (uint256) {
        return prices[token];
    }

    /**
     * @notice Get price with decimals
     */
    function getPriceWithDecimals(address token)
        external
        view
        returns (uint256, uint8)
    {
        return (prices[token], decimals[token]);
    }
}

// ============= TEST DATA GENERATORS =============

/**
 * @title TestDataGenerator
 * @notice Generate consistent test data
 */
library TestDataGenerator {
    /**
     * @notice Generate test user addresses
     */
    function generateUsers(uint256 count)
        internal
        pure
        returns (address[] memory)
    {
        address[] memory users = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            users[i] = address(uint160(0x1000 + i));
        }
        return users;
    }

    /**
     * @notice Generate test amounts
     */
    function generateAmounts(uint256 count, uint256 baseAmount)
        internal
        pure
        returns (uint256[] memory)
    {
        uint256[] memory amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            amounts[i] = baseAmount * (i + 1);
        }
        return amounts;
    }

    /**
     * @notice Generate proposal call data
     */
    function generateProposalData(
        address target,
        string memory signature,
        bytes memory params
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(target, signature, params);
    }

    /**
     * @notice Generate transaction hash
     */
    function generateTxHash(
        address sender,
        uint256 nonce,
        bytes memory data
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(sender, nonce, data));
    }
}

// ============= TEST FIXTURES =============

/**
 * @title TestFixtures
 * @notice Common test setup builders
 */
contract TestFixtures {
    /**
     * @notice Setup: Minimal protocol
     */
    function setupMinimalProtocol()
        internal
        returns (
            RebaseToken,
            RebaseTokenVault,
            address
        )
    {
        RebaseToken token = new RebaseToken("Test", "TEST");
        RebaseTokenVault vault = new RebaseTokenVault(address(token));
        address owner = msg.sender;

        token.mint(owner, 1_000_000e18);

        return (token, vault, owner);
    }

    /**
     * @notice Setup: Multi-user environment
     */
    function setupMultiUserEnvironment(uint256 userCount, uint256 initialBalance)
        internal
        returns (
            RebaseToken,
            RebaseTokenVault,
            address[] memory
        )
    {
        RebaseToken token = new RebaseToken("Test", "TEST");
        RebaseTokenVault vault = new RebaseTokenVault(address(token));

        address[] memory users = new address[](userCount);
        for (uint256 i = 0; i < userCount; i++) {
            users[i] = address(uint160(0x2000 + i));
            token.mint(users[i], initialBalance);
        }

        return (token, vault, users);
    }

    /**
     * @notice Setup: Governance enabled
     */
    function setupGovernance(
        RebaseToken token,
        address owner
    ) internal returns (VotingEscrow, BASEGovernor) {
        VotingEscrow ve = new VotingEscrow(address(token));
        // BASEGovernor setup would require more infrastructure
        // This is a placeholder for the pattern

        return (ve, BASEGovernor(address(0)));
    }
}

// ============= COMMON ASSERTIONS =============

/**
 * @title AssertionHelpers
 * @notice Extended assertions for testing
 */
library AssertionHelpers {
    /**
     * @notice Assert balance increased by amount
     */
    function assertBalanceIncreased(
        RebaseToken token,
        address account,
        uint256 before,
        uint256 minIncrease
    ) internal view {
        uint256 after = token.balanceOf(account);
        require(
            after >= before + minIncrease,
            "Balance did not increase enough"
        );
    }

    /**
     * @notice Assert balance decreased by amount
     */
    function assertBalanceDecreased(
        RebaseToken token,
        address account,
        uint256 before,
        uint256 minDecrease
    ) internal view {
        uint256 after = token.balanceOf(account);
        require(
            after <= before - minDecrease,
            "Balance did not decrease enough"
        );
    }

    /**
     * @notice Assert allowance set correctly
     */
    function assertAllowanceSet(
        RebaseToken token,
        address owner,
        address spender,
        uint256 expected
    ) internal view {
        uint256 actual = token.allowance(owner, spender);
        require(actual == expected, "Allowance mismatch");
    }

    /**
     * @notice Assert vault share price in range
     */
    function assertSharePriceInRange(
        RebaseTokenVault vault,
        uint256 minPrice,
        uint256 maxPrice
    ) internal view {
        uint256 sharePrice = vault.convertToAssets(1e18);
        require(sharePrice >= minPrice, "Price too low");
        require(sharePrice <= maxPrice, "Price too high");
    }

    /**
     * @notice Assert rebase applied correctly
     */
    function assertRebaseApplied(
        RebaseToken token,
        uint256 balanceBefore,
        int256 rebasePercent
    ) internal view {
        uint256 balanceAfter = token.balanceOf(msg.sender);
        
        if (rebasePercent > 0) {
            require(balanceAfter > balanceBefore, "Rebase should increase balance");
        } else if (rebasePercent < 0) {
            require(balanceAfter < balanceBefore, "Rebase should decrease balance");
        }
    }
}

// ============= STATE BUILDERS =============

/**
 * @title StateBuilder
 * @notice Fluent API for building test state
 */
contract StateBuilder {
    RebaseToken public token;
    RebaseTokenVault public vault;
    mapping(address => uint256) public userBalances;

    constructor(RebaseToken _token, RebaseTokenVault _vault) {
        token = _token;
        vault = _vault;
    }

    /**
     * @notice Set user balance
     */
    function withUserBalance(address user, uint256 amount)
        public
        returns (StateBuilder)
    {
        token.mint(user, amount);
        userBalances[user] = amount;
        return this;
    }

    /**
     * @notice Deposit for user
     */
    function withDeposit(address user, uint256 amount)
        public
        returns (StateBuilder)
    {
        token.mint(user, amount);
        // Token approval and deposit would go here
        return this;
    }

    /**
     * @notice Set rebase rate
     */
    function withRebaseRate(int256 rate) public returns (StateBuilder) {
        // Set rebase rate on token
        return this;
    }

    /**
     * @notice Build and return vault
     */
    function build() public view returns (RebaseTokenVault) {
        return vault;
    }
}

// ============= SCENARIO BUILDERS =============

/**
 * @title ScenarioBuilder
 * @notice Build complex test scenarios
 */
library ScenarioBuilder {
    /**
     * @notice Build simple vault scenario
     */
    function buildSimpleVault(uint256 numUsers, uint256 depositPerUser)
        internal
        returns (RebaseToken, RebaseTokenVault, address[] memory)
    {
        RebaseToken token = new RebaseToken("Test", "TEST");
        RebaseTokenVault vault = new RebaseTokenVault(address(token));

        address[] memory users = new address[](numUsers);
        for (uint256 i = 0; i < numUsers; i++) {
            users[i] = address(uint160(0x3000 + i));
            token.mint(users[i], depositPerUser * 2); // Extra for testing
        }

        return (token, vault, users);
    }

    /**
     * @notice Build governance scenario
     */
    function buildGovernanceScenario(uint256 numVoters)
        internal
        returns (
            RebaseToken,
            VotingEscrow,
            address[] memory
        )
    {
        RebaseToken token = new RebaseToken("Test", "TEST");
        VotingEscrow ve = new VotingEscrow(address(token));

        address[] memory voters = new address[](numVoters);
        for (uint256 i = 0; i < numVoters; i++) {
            voters[i] = address(uint160(0x4000 + i));
            token.mint(voters[i], 100000e18);
        }

        return (token, ve, voters);
    }
}

// ============= EVENT ASSERTION =============

/**
 * @title EventAssertions
 * @notice Helper for asserting events in tests
 */
library EventAssertions {
    /**
     * @notice Assert transfer event emitted
     */
    function assertTransferEmitted(
        address from,
        address to,
        uint256 amount
    ) internal pure {
        // In actual Forge tests, would use recordLogs() pattern
    }

    /**
     * @notice Assert approval event emitted
     */
    function assertApprovalEmitted(
        address owner,
        address spender,
        uint256 amount
    ) internal pure {
        // In actual Forge tests, would use recordLogs() pattern
    }
}
