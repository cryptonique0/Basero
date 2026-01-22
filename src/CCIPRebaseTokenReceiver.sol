// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {RebaseToken} from "./RebaseToken.sol";

/**
 * @title CCIPRebaseTokenReceiver
 * @author Basero Labs
 * @notice Destination chain contract for receiving bridged rebase tokens via Chainlink CCIP
 * @dev Handles CCIP message reception and token minting on destination chains
 *
 * ARCHITECTURE:
 * This contract is deployed on DESTINATION chains (where users receive bridged tokens).
 * It works with CCIPRebaseTokenSender on SOURCE chains.
 *
 * KEY FEATURES:
 * 1. Token Minting: Mints tokens on destination chain when CCIP message received
 * 2. Interest Rate Preservation: Mints tokens with same locked rate from source
 * 3. Rate Limiting: Per-chain receive caps and daily limits prevent abuse
 * 4. Allowlisting: Only approved source chains and senders accepted
 * 5. Pausability: Emergency stop mechanism for security incidents
 * 6. Reentrancy Protection: Guards against reentrancy attacks during minting
 * 7. CCIP Integration: Inherits from CCIPReceiver for message handling
 *
 * COMPLETE BRIDGE FLOW (User bridges from Ethereum → Arbitrum):
 * 1. User calls sendTokensCrossChain() on Ethereum sender
 * 2. Sender burns tokens on Ethereum, sends CCIP message
 * 3. CCIP infrastructure routes message to Arbitrum
 * 4. THIS CONTRACT receives message via _ccipReceive()
 * 5. Validate: source chain allowed, sender authorized
 * 6. Validate: amount within caps and daily limit
 * 7. Decode message: {recipient, amount, interestRate}
 * 8. Mint amount to recipient at their preserved interest rate
 * 9. Update daily limit accounting
 * 10. Emit MessageReceived event
 * 11. User now has tokens on Arbitrum at same rate as Ethereum
 *
 * MESSAGE STRUCTURE (from sender):
 * ```
 * any2EvmMessage.sender: abi.encode(senderContractAddress)
 * any2EvmMessage.data: abi.encode(userAddress, bridgedAmount, lockedInterestRate)
 * any2EvmMessage.sourceChainSelector: Ethereum chain selector
 * any2EvmMessage.messageId: Unique CCIP message identifier
 * ```
 *
 * RATE LIMITING EXAMPLE:
 * ```
 * Arbitrum receiver configuration:
 * - chainBridgedCap[EthereumSelector] = 10,000 tokens (max per message)
 * - chainDailyLimit[EthereumSelector] = 500,000 tokens (max per day)
 *
 * Message 1: Receive 5,000 tokens ✅ (within caps)
 * Message 2: Receive 8,000 tokens ✅ (total: 13,000 < 500k daily)
 * Message 3: Receive 15,000 tokens ❌ (exceeds 10k cap per message)
 * ... 60 more messages of 8,000 each ...
 * Message 63: Receive 8,000 ❌ (would exceed 500k daily limit)
 * Wait until midnight UTC, daily counter resets
 * Message 64: Receive 8,000 ✅ (new day, counter = 0)
 * ```
 *
 * INTEREST RATE PRESERVATION:
 * Alice on Ethereum has 1000 tokens at 8% APY (locked rate)
 * Alice bridges to Arbitrum:
 * 1. Ethereum sender encodes: {alice, 950, 8%} (after 5% fee)
 * 2. CCIP delivers message to Arbitrum receiver
 * 3. Arbitrum receiver mints 950 tokens to alice at 8% APY
 * Result: Alice has same locked rate on both chains
 *
 * SECURITY CONSIDERATIONS:
 * - Only allowlisted source chains can send (prevents fake chains)
 * - Only allowlisted senders can mint (prevents unauthorized mints)
 * - Rate limits prevent flash attacks and limit damage
 * - Pausable enables emergency stop
 * - ReentrancyGuard prevents reentrancy during mint
 * - Immutable token prevents rug pulls
 * - Owner-controlled caps allow dynamic risk management
 *
 * DEPLOYMENT CHECKLIST:
 * 1. Deploy receiver on destination chain (e.g., Arbitrum)
 * 2. Grant receiver contract MINTER_ROLE on rebase token
 * 3. Call allowlistSourceChain() for each source (e.g., Ethereum)
 * 4. Call allowlistSender() to authorize sender contracts
 * 5. Call setChainCaps() to configure receive limits
 * 6. Verify on sender: allowlistReceiver(Arbitrum, thisContract)
 * 7. Test with small bridge before enabling for users
 *
 * GAS COSTS:
 * - Message reception: ~150-250k gas (paid by CCIP, not user)
 * - Admin functions: ~50-100k gas
 * - View functions: minimal
 */
contract CCIPRebaseTokenReceiver is CCIPReceiver, Ownable, Pausable, ReentrancyGuard {
    RebaseToken public immutable rebaseToken;

    // Mapping to track allowed source chains
    mapping(uint64 => bool) public allowlistedSourceChains;

    // Mapping to track allowed sender contracts on source chains
    mapping(uint64 => address) public allowlistedSenders;

    // Per-chain bridged cap
    mapping(uint64 => uint256) public chainBridgedCap;

    // Per-chain daily limit and accounting
    mapping(uint64 => uint256) public chainDailyLimit;
    mapping(uint64 => uint256) public chainDailyAmount;
    mapping(uint64 => uint256) public chainLastReset;

    // Events
    event MessageReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address sender,
        address recipient,
        uint256 amount
    );
    event SourceChainAllowlisted(uint64 indexed chainSelector, bool allowed);
    event SenderAllowlisted(uint64 indexed chainSelector, address sender);
    event BridgingPaused(address indexed account);
    event BridgingUnpaused(address indexed account);
    event ChainCapsUpdated(uint64 indexed chainSelector, uint256 bridgedCap, uint256 dailyLimit);

    // Errors
    error SourceChainNotAllowlisted(uint64 sourceChainSelector);
    error SenderNotAllowlisted(address sender);
    error InvalidSenderAddress();
    error BridgeCapExceeded(uint256 received, uint256 cap);
    error BridgeDailyLimitExceeded(uint256 received, uint256 remaining);

    /**
     * @notice Initialize CCIP receiver with router and rebase token
     * @dev Sets up immutable references for CCIP routing and token minting
     *
     * @param _router Chainlink CCIP Router address for this destination chain
     *        - Arbitrum: 0x141fa059441E0ca23ce184B6A78bafD2A517DdE8
     *        - Optimism: 0x3206695CaE29952f4b0c22a169725a865bc8Ce0f
     *        - Base: 0x673AA85efd75080031d44fcA061575d1dA427A28
     *        - Polygon: 0x3C3D92629A02a8D95D5CB9650fe49C3544f69B43
     * @param _rebaseToken Address of RebaseToken deployed on this chain
     *        - Must grant this contract MINTER_ROLE to enable minting
     *
     * REQUIREMENTS:
     * - _router must be valid CCIP router for this chain
     * - _rebaseToken must be deployed RebaseToken contract
     * - Deployer becomes owner (inherited from Ownable)
     *
     * EFFECTS:
     * - Sets immutable router reference (cannot be changed)
     * - Sets immutable rebase token reference (cannot be changed)
     * - Initializes owner to msg.sender
     * - Contract starts unpaused (can receive immediately if configured)
     *
     * POST-DEPLOYMENT CHECKLIST:
     * 1. Grant MINTER_ROLE to this contract:
     *    rebaseToken.grantRole(MINTER_ROLE, receiver)
     * 2. Allowlist source chains:
     *    receiver.allowlistSourceChain(EthereumSelector, true)
     * 3. Allowlist sender contracts on each source:
     *    receiver.allowlistSender(EthereumSelector, senderOnEth)
     * 4. Set receive caps:
     *    receiver.setChainCaps(EthereumSelector, 10000e18, 500000e18)
     * 5. Coordinate with source: sender.allowlistReceiver(ArbSelector, receiver)
     * 6. Test bridge with small amount
     *
     * Example Deployment on Arbitrum:
     * ```
     * receiver = new CCIPRebaseTokenReceiver(
     *     0x141fa059441E0ca23ce184B6A78bafD2A517DdE8,  // Arbitrum CCIP router
     *     0xRebaseTokenOnArbitrum                      // RebaseToken
     * )
     * // Then configure:
     * rebaseToken.grantRole(MINTER_ROLE, receiver)
     * receiver.allowlistSourceChain(EthereumSelector, true)
     * receiver.allowlistSender(EthereumSelector, senderOnEth)
     * receiver.setChainCaps(EthereumSelector, 10000e18, 500000e18)
     * ```
     */
    constructor(address _router, address _rebaseToken) CCIPReceiver(_router) Ownable(msg.sender) {
        rebaseToken = RebaseToken(_rebaseToken);
    }

    /**
     * @notice Enable or disable receiving bridges from a specific source chain
     * @dev Controls which CCIP source chains can send tokens to this receiver
     *
     * @param _sourceChainSelector CCIP chain selector ID for source chain
     *        - Ethereum: 5009297550715157269
     *        - Arbitrum One: 4949039107694359620
     *        - Optimism: 3734403246176062136
     *        - Base: 15971525489660198786
     * @param allowed true to enable receiving, false to disable
     *
     * REQUIREMENTS:
     * - Can only be called by owner (governance or admin)
     * - No validation on chainSelector (any uint64 allowed)
     *
     * EFFECTS:
     * - Updates allowlistedSourceChains mapping
     * - Emits SourceChainAllowlisted event
     * - If false, all messages from this chain will revert
     * - If true, receiving allowed (still requires sender to be set)
     *
     * USE CASES:
     * 1. Initial setup: Enable supported source chains
     * 2. Emergency: Disable chain if sender or source has issues
     * 3. Expansion: Add new source chains as protocol grows
     * 4. Deprecation: Disable old chains being sunset
     *
     * Example:
     * ```
     * // Enable receiving from Ethereum
     * receiver.allowlistSourceChain(5009297550715157269, true)
     *
     * // Emergency: Disable in case of Ethereum sender compromise
     * receiver.allowlistSourceChain(5009297550715157269, false)
     * // All incoming CCIP messages from Ethereum will now revert
     * ```
     */
    function allowlistSourceChain(uint64 _sourceChainSelector, bool allowed) external onlyOwner {
        allowlistedSourceChains[_sourceChainSelector] = allowed;
        emit SourceChainAllowlisted(_sourceChainSelector, allowed);
    }

    /**
     * @notice Set the authorized sender contract address for a source chain
     * @dev Each source chain has exactly one sender (1:1 mapping)
     *
     * @param _sourceChainSelector CCIP chain selector for source chain
     * @param _sender Address of CCIPRebaseTokenSender on source chain
     *        - Must be the deployed sender contract address
     *        - Cannot be zero address (validation enforced)
     *
     * REQUIREMENTS:
     * - Can only be called by owner
     * - _sender must not be address(0) (reverts with InvalidSenderAddress)
     *
     * EFFECTS:
     * - Updates allowlistedSenders[chainSelector] = sender
     * - Emits SenderAllowlisted event
     * - All CCIP messages from this chain must originate from this sender
     * - Previous sender (if any) is overwritten
     *
     * SECURITY:
     * - Only set sender to trusted CCIPRebaseTokenSender contracts
     * - Malicious sender could mint unlimited tokens
     * - Verify sender contract code on source chain before allowlisting
     * - Consider multisig/timelock for production changes
     *
     * USE CASES:
     * 1. Initial setup: Set sender when configuring bridge
     * 2. Upgrade: Point to new sender if source contract upgraded
     * 3. Migration: Move to new sender for protocol changes
     *
     * Example:
     * ```
     * // Sender deployed on Ethereum at 0xDEF...
     * // Allowlist it on Arbitrum receiver:
     * receiver.allowlistSender(
     *     5009297550715157269,  // Ethereum selector
     *     0xDEF...              // Sender on Ethereum
     * )
     * // Now can receive bridges from Ethereum via this sender
     * ```
     */
    function allowlistSender(uint64 _sourceChainSelector, address _sender) external onlyOwner {
        if (_sender == address(0)) revert InvalidSenderAddress();
        allowlistedSenders[_sourceChainSelector] = _sender;
        emit SenderAllowlisted(_sourceChainSelector, _sender);
    }

    function pauseBridging() external onlyOwner {
        _pause();
        emit BridgingPaused(msg.sender);
    }

    function unpauseBridging() external onlyOwner {
        _unpause();
        emit BridgingUnpaused(msg.sender);
    }

    function setChainCaps(uint64 _sourceChainSelector, uint256 bridgedCap, uint256 dailyLimit) external onlyOwner {
        chainBridgedCap[_sourceChainSelector] = bridgedCap;
        chainDailyLimit[_sourceChainSelector] = dailyLimit;
        emit ChainCapsUpdated(_sourceChainSelector, bridgedCap, dailyLimit);
    }

    /**
     * @dev Handle received CCIP messages
     * @param any2EvmMessage CCIP message
     */
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override nonReentrant {
        // Validate that bridging is not paused
        if (paused()) revert SourceChainNotAllowlisted(any2EvmMessage.sourceChainSelector);

        // Validate source chain
        if (!allowlistedSourceChains[any2EvmMessage.sourceChainSelector]) {
            revert SourceChainNotAllowlisted(any2EvmMessage.sourceChainSelector);
        }

        // Decode sender
        address sender = abi.decode(any2EvmMessage.sender, (address));

        // Validate sender
        address allowlistedSender = allowlistedSenders[any2EvmMessage.sourceChainSelector];
        if (sender != allowlistedSender) {
            revert SenderNotAllowlisted(sender);
        }

        // Decode message data including interest rate
        (address recipient, uint256 amount, uint256 interestRate) = abi.decode(any2EvmMessage.data, (address, uint256, uint256));

        // Enforce per-chain bridged cap if set
        uint256 bridgedCap = chainBridgedCap[any2EvmMessage.sourceChainSelector];
        if (bridgedCap > 0 && amount > bridgedCap) {
            revert BridgeCapExceeded(amount, bridgedCap);
        }

        // Enforce daily limit if set
        uint256 dayBucket = block.timestamp / 1 days;
        if (chainLastReset[any2EvmMessage.sourceChainSelector] != dayBucket) {
            chainLastReset[any2EvmMessage.sourceChainSelector] = dayBucket;
            chainDailyAmount[any2EvmMessage.sourceChainSelector] = 0;
        }

        uint256 dailyLimit = chainDailyLimit[any2EvmMessage.sourceChainSelector];
        if (dailyLimit > 0 && chainDailyAmount[any2EvmMessage.sourceChainSelector] + amount > dailyLimit) {
            uint256 remaining = dailyLimit - chainDailyAmount[any2EvmMessage.sourceChainSelector];
            revert BridgeDailyLimitExceeded(amount, remaining);
        }

        // Mint tokens to recipient with their bridged interest rate
        rebaseToken.mint(recipient, amount, interestRate);

        // Update daily accounting
        chainDailyAmount[any2EvmMessage.sourceChainSelector] += amount;

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector,
            sender,
            recipient,
            amount
        );
    }

    /**
     * @dev Get router address
     */
    function getRouter() external view returns (address) {
        return address(i_ccipRouter);
    }
}
