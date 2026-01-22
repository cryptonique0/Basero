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

    /**
     * @notice Emergency stop for receiving bridged tokens
     * @dev Pauses all incoming CCIP message reception
     *
     * REQUIREMENTS:
     * - Can only be called by owner
     * - Contract must not already be paused
     *
     * EFFECTS:
     * - Sets paused state to true
     * - All _ccipReceive() calls will revert with EnforcedPause()
     * - Blocks all token minting from bridges
     * - Does not affect existing balances
     *
     * USE CASES:
     * 1. Source chain sender compromised (stop receiving malicious mints)
     * 2. CCIP infrastructure issue detected
     * 3. Rebase token contract bug discovered
     * 4. Rate limiting exploited (pause while investigating)
     * 5. Coordinated pause across all chains for protocol upgrade
     *
     * Example Emergency Response:
     * ```
     * // 1. Alert: Unusual minting activity detected
     * // 2. Pause receiver immediately:
     * receiver.pauseBridging()
     * // 3. Investigate: Check source chain, CCIP logs, minting events
     * // 4. Fix: Deploy new sender or patch vulnerability
     * // 5. Resume: unpauseBridging() after validation
     * ```
     */
    function pauseBridging() external onlyOwner {
        _pause();
        emit BridgingPaused(msg.sender);
    }

    /**
     * @notice Resume receiving bridged tokens after pause
     * @dev Unpauses CCIP message reception to restore normal operations
     *
     * REQUIREMENTS:
     * - Can only be called by owner
     * - Contract must be paused
     *
     * EFFECTS:
     * - Sets paused state to false
     * - Re-enables _ccipReceive() to process incoming messages
     * - Restores token minting from bridges
     * - Daily limits reset normally at midnight UTC (not affected by pause)
     *
     * SAFETY CHECKLIST BEFORE UNPAUSING:
     * 1. ✅ Confirm issue is fully resolved
     * 2. ✅ Verify sender contracts on all source chains are secure
     * 3. ✅ Check rebase token contract for any issues
     * 4. ✅ Review allowlisted chains and senders
     * 5. ✅ Confirm rate limits are appropriate
     * 6. ✅ Test bridge with small amount on testnet
     * 7. ✅ Monitor initial messages closely after resume
     *
     * Example:
     * ```
     * // After fixing sender vulnerability:
     * // 1. Deploy new sender on Ethereum
     * // 2. Update allowlist:
     * receiver.allowlistSender(EthereumSelector, newSender)
     * // 3. Verify deployment:
     * require(receiver.allowlistedSenders(EthereumSelector) == newSender)
     * // 4. Resume:
     * receiver.unpauseBridging()
     * // 5. Monitor events for normal activity
     * ```
     */
    function unpauseBridging() external onlyOwner {
        _unpause();
        emit BridgingUnpaused(msg.sender);
    }

    /**
     * @notice Configure per-message and daily receive limits for a source chain
     * @dev Two-tier rate limiting: per-bridge cap and daily cumulative limit
     *
     * @param _sourceChainSelector CCIP chain selector for source chain
     * @param bridgedCap Maximum tokens per single message (18 decimals)
     * @param dailyLimit Maximum tokens per day from this chain (18 decimals)
     *
     * REQUIREMENTS:
     * - Can only be called by owner (governance)
     * - No validation on cap values (can be 0 to disable, or type(uint256).max for unlimited)
     *
     * EFFECTS:
     * - Updates chainBridgedCap[chainSelector] = bridgedCap
     * - Updates chainDailyLimit[chainSelector] = dailyLimit
     * - Emits ChainCapsUpdated event
     * - Does not reset existing daily usage
     * - Applies immediately to next message
     *
     * RATE LIMITING MECHANICS:
     * Per-bridge cap: Prevents single large malicious mint
     * Daily limit: Prevents cumulative attack over multiple messages
     *
     * Daily Reset Formula:
     * ```
     * uint256 currentDay = block.timestamp / 1 days;  // Days since epoch
     * if (lastReceiveDay[chain] != currentDay) {
     *     dailyReceived[chain] = 0;  // Reset at midnight UTC
     * }
     * ```
     *
     * EXAMPLE CAP SCENARIOS:
     *
     * Conservative (new chain, low trust):
     * ```
     * receiver.setChainCaps(
     *     newChainSelector,
     *     1_000 * 1e18,      // Max 1,000 tokens per message
     *     10_000 * 1e18      // Max 10,000 tokens per day
     * )
     * ```
     *
     * Mature chain (high volume, trusted):
     * ```
     * receiver.setChainCaps(
     *     EthereumSelector,
     *     100_000 * 1e18,    // Max 100k tokens per message
     *     5_000_000 * 1e18   // Max 5M tokens per day
     * )
     * ```
     *
     * Emergency (restrict during incident):
     * ```
     * receiver.setChainCaps(
     *     suspiciousChain,
     *     100 * 1e18,        // Tiny per-message
     *     1_000 * 1e18       // Tiny daily
     * )
     * ```
     *
     * No limits (trusted internal chain):
     * ```
     * receiver.setChainCaps(
     *     trustedChain,
     *     type(uint256).max, // Unlimited per message
     *     type(uint256).max  // Unlimited daily
     * )
     * ```
     *
     * GOVERNANCE USE CASES:
     * 1. Initial setup: Set conservative limits
     * 2. Scale up: Increase as protocol matures
     * 3. Emergency: Reduce if attack detected
     * 4. New chain: Start low, increase with proven security
     */
    function setChainCaps(uint64 _sourceChainSelector, uint256 bridgedCap, uint256 dailyLimit) external onlyOwner {
        chainBridgedCap[_sourceChainSelector] = bridgedCap;
        chainDailyLimit[_sourceChainSelector] = dailyLimit;
        emit ChainCapsUpdated(_sourceChainSelector, bridgedCap, dailyLimit);
    }

    /**
     * @notice Handle received CCIP messages and mint tokens on destination chain
     * @dev Core bridge function - validates message and mints tokens with bridged interest rate
     *
     * @param any2EvmMessage CCIP message containing sender, amount, and interest rate
     *        - messageId: Unique CCIP message identifier
     *        - sourceChainSelector: Source chain (Ethereum, Arbitrum, etc.)
     *        - sender: ABI-encoded sender contract address on source chain
     *        - data: ABI-encoded (recipient, amount, interestRate)
     *
     * REQUIREMENTS:
     * - Automatically called by CCIP router (not by users)
     * - Contract must not be paused
     * - Source chain must be allowlisted
     * - Sender must match allowlisted sender for that chain
     * - Amount must not exceed per-bridge cap (if set)
     * - Amount must not exceed remaining daily limit (if set)
     * - Receiver must have MINTER_ROLE on rebase token
     *
     * EFFECTS:
     * - Decodes message to extract (recipient, amount, interestRate)
     * - Resets daily counter if new day (midnight UTC)
     * - Mints amount to recipient with their bridged interest rate
     * - Updates daily amount counter for source chain
     * - Emits MessageReceived event
     *
     * COMPLETE RECEIVE FLOW (Alice bridges 950 tokens from Ethereum → Arbitrum):
     *
     * Step 1: CCIP delivers message to this contract:
     * ```
     * messageId: 0x123...
     * sourceChainSelector: 5009297550715157269 (Ethereum)
     * sender: 0xABC... (encoded sender on Ethereum)
     * data: (0xAlice, 950e18, 8%) (recipient, amount, rate)
     * ```
     *
     * Step 2: Validate not paused
     * ```
     * if (paused()) revert SourceChainNotAllowlisted(...)
     * // Reverts if pauseBridging() was called
     * ```
     *
     * Step 3: Validate source chain
     * ```
     * require(allowlistedSourceChains[5009297550715157269] == true)
     * // Reverts if Ethereum not enabled
     * ```
     *
     * Step 4: Decode and validate sender
     * ```
     * address sender = abi.decode(message.sender, (address)) // 0xABC...
     * require(sender == allowlistedSenders[Ethereum])
     * // Reverts if sender not authorized
     * ```
     *
     * Step 5: Decode message data
     * ```
     * (recipient, amount, rate) = abi.decode(data, (address, uint256, uint256))
     * // recipient: 0xAlice
     * // amount: 950e18
     * // rate: 800 (8% = 800 bps)
     * ```
     *
     * Step 6: Check per-bridge cap
     * ```
     * bridgedCap = chainBridgedCap[Ethereum] // 10,000e18
     * require(950e18 <= 10,000e18) ✅
     * // Reverts if amount > cap
     * ```
     *
     * Step 7: Reset daily counter if new day
     * ```
     * currentDay = block.timestamp / 86400 // Days since epoch
     * if (chainLastReset[Ethereum] != currentDay) {
     *     chainLastReset[Ethereum] = currentDay
     *     chainDailyAmount[Ethereum] = 0  // Reset at midnight UTC
     * }
     * ```
     *
     * Step 8: Check daily limit
     * ```
     * dailyLimit = chainDailyLimit[Ethereum] // 500,000e18
     * currentDaily = chainDailyAmount[Ethereum] // 50,000e18 (so far today)
     * require(50,000 + 950 <= 500,000) ✅
     * // Reverts if would exceed daily limit
     * remaining = 500,000 - 50,000 = 450,000 available
     * ```
     *
     * Step 9: Mint tokens with bridged interest rate
     * ```
     * rebaseToken.mint(0xAlice, 950e18, 8%)
     * // Alice receives 950 tokens at 8% APY (same as Ethereum)
     * // Interest accrues at 8% on Arbitrum starting from receive time
     * ```
     *
     * Step 10: Update daily accounting
     * ```
     * chainDailyAmount[Ethereum] = 50,000 + 950 = 50,950
     * // Remaining today: 500,000 - 50,950 = 449,050
     * ```
     *
     * Step 11: Emit event
     * ```
     * emit MessageReceived(
     *     messageId: 0x123...,
     *     sourceChain: Ethereum,
     *     sender: 0xABC...,
     *     recipient: 0xAlice,
     *     amount: 950e18
     * )
     * ```
     *
     * RESULT:
     * - Alice has 950 tokens on Arbitrum at 8% APY
     * - Same locked rate as her original Ethereum tokens
     * - Can use tokens on Arbitrum immediately
     * - Interest accrues at 8% on Arbitrum
     *
     * ERROR CONDITIONS:
     *
     * 1. Paused (emergency stop):
     * ```
     * pauseBridging() called → revert SourceChainNotAllowlisted
     * Use: Stop all receives during incident
     * ```
     *
     * 2. Chain not allowlisted:
     * ```
     * allowlistedSourceChains[chain] == false → revert
     * Use: Reject messages from disabled or unknown chains
     * ```
     *
     * 3. Sender not authorized:
     * ```
     * sender != allowlistedSenders[chain] → revert SenderNotAllowlisted
     * Use: Prevent malicious senders from minting
     * ```
     *
     * 4. Per-bridge cap exceeded:
     * ```
     * amount > chainBridgedCap[chain] → revert BridgeCapExceeded
     * Example: Trying to receive 15,000 when cap is 10,000
     * Use: Prevent single large malicious mint
     * ```
     *
     * 5. Daily limit exceeded:
     * ```
     * daily + amount > chainDailyLimit[chain] → revert BridgeDailyLimitExceeded
     * Example: Received 499,500 today, trying to receive 1,000 (limit 500,000)
     * Use: Prevent cumulative attack over multiple messages
     * Returns: remaining = dailyLimit - currentDaily (500 tokens left)
     * ```
     *
     * GAS COSTS:
     * - CCIP delivery: ~150-250k gas (paid by CCIP infrastructure, not user)
     * - User pays on SOURCE chain for CCIP fees (LINK + gas)
     * - Destination receive is free for user
     *
     * SECURITY NOTES:
     * - NonReentrant prevents reentrancy during mint
     * - Interest rate from source chain is trusted (sender validated)
     * - Daily limit resets at midnight UTC (deterministic)
     * - Caps can be 0 (disabled) or type(uint256).max (unlimited)
     * - Multiple allowlisted sources can send to one receiver
     * - One sender per source chain (1:1 mapping)
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
     * @notice Get the CCIP router address for this destination chain
     * @dev Returns immutable router set at deployment
     *
     * @return address CCIP router contract address
     *
     * ROUTER ADDRESSES (Mainnets):
     * - Ethereum: 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D
     * - Arbitrum One: 0x141fa059441E0ca23ce184B6A78bafD2A517DdE8
     * - Optimism: 0x3206695CaE29952f4b0c22a169725a865bc8Ce0f
     * - Base: 0x673AA85efd75080031d44fcA061575d1dA427A28
     * - Polygon: 0x3C3D92629A02a8D95D5CB9650fe49C3544f69B43
     *
     * USE CASES:
     * 1. Verify deployment: Confirm correct router for chain
     * 2. Frontend: Display router to users for transparency
     * 3. Debugging: Check router matches expected address
     * 4. Audit: Verify router is official Chainlink contract
     */
    function getRouter() external view returns (address) {
        return address(i_ccipRouter);
    }
}
