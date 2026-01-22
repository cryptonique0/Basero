// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {RebaseToken} from "./RebaseToken.sol";

/**
 * @title CCIPRebaseTokenSender
 * @author Basero Labs
 * @notice Source chain contract for bridging rebase tokens cross-chain via Chainlink CCIP
 * @dev Handles token burning on source chain and CCIP message transmission with rate limiting
 *
 * ARCHITECTURE:
 * This contract is deployed on the SOURCE chain (where users initiate bridges).
 * It works with CCIPRebaseTokenReceiver on DESTINATION chains.
 *
 * KEY FEATURES:
 * 1. Token Burning: Burns tokens on source chain (supply decreases locally)
 * 2. CCIP Messaging: Sends mint instructions to destination chain receiver
 * 3. Rate Limiting: Per-chain send caps and daily limits prevent abuse
 * 4. Protocol Fees: Configurable per-chain fees collected in rebase tokens
 * 5. Interest Rate Bridging: User's locked interest rate travels with tokens
 * 6. Pausability: Emergency stop mechanism for security incidents
 * 7. Allowlisting: Only approved destination chains and receivers allowed
 *
 * WORKFLOW (User bridges 100 tokens from Ethereum → Arbitrum):
 * 1. User calls sendTokensCrossChain(ArbitrumSelector, userAddress, 100)
 * 2. Contract validates: chain allowed, receiver set, caps not exceeded
 * 3. Calculate protocol fee: 5% = 5 tokens (configurable per chain)
 * 4. Burn 100 tokens from user on Ethereum (total supply -100)
 * 5. Get user's locked interest rate (e.g., 8% APY)
 * 6. Construct CCIP message: {receiver, 95 tokens, 8% rate}
 * 7. Pay LINK fees to CCIP router (~$0.50-$2 depending on destination)
 * 8. CCIP router sends message to Arbitrum receiver
 * 9. Mint 5 tokens to feeRecipient on Ethereum (net burn: -95)
 * 10. Update daily limit accounting (prevent >dailyLimit in 24h)
 * 11. Emit MessageSent event with messageId for tracking
 * 12. Destination receiver mints 95 tokens to user on Arbitrum
 *
 * RATE LIMITING MECHANICS:
 * - Per-Send Cap: Maximum tokens per single transaction (e.g., 1000)
 * - Daily Limit: Maximum tokens bridged to chain per 24h (e.g., 100,000)
 * - Daily counter resets at midnight UTC (block.timestamp / 1 days)
 * - Prevents whale manipulation and limits damage from security incidents
 *
 * PROTOCOL FEE EXAMPLE:
 * Chain: Arbitrum, Fee: 500 bps (5%), User bridges: 1000 tokens
 * protocolFee = (1000 × 500) / 10,000 = 50 tokens
 * bridgedAmount = 1000 - 50 = 950 tokens
 * Burn 1000 from user, mint 50 to feeRecipient, send 950 to destination
 * Net supply change on source: -950 tokens
 *
 * SECURITY CONSIDERATIONS:
 * - Owner-controlled allowlisting prevents unauthorized destinations
 * - Rate limits prevent flash loan attacks and limit damage
 * - Pausable interface enables emergency stop
 * - LINK token required for CCIP fees (must be funded)
 * - Interest rate preserved cross-chain (prevents gaming)
 * - Immutable router and token prevent rug pulls
 *
 * GAS COSTS:
 * - sendTokensCrossChain: ~200-300k gas + CCIP fees ($0.50-$2 in LINK)
 * - Admin functions: ~50-100k gas
 * - View functions: minimal
 */
contract CCIPRebaseTokenSender is Ownable, Pausable {
    IRouterClient private immutable i_router;
    IERC20 private immutable i_linkToken;
    RebaseToken public immutable rebaseToken;

    // Mapping to track allowed destination chains
    mapping(uint64 => bool) public allowlistedDestinationChains;

    // Mapping to track allowed receiver contracts on destination chains
    mapping(uint64 => address) public allowlistedReceivers;

    // Per-chain protocol fee in basis points
    mapping(uint64 => uint256) public chainFeeBps;

    // Per-chain single send cap
    mapping(uint64 => uint256) public chainSendCap;

    // Per-chain daily limit and accounting
    mapping(uint64 => uint256) public chainDailyLimit;
    mapping(uint64 => uint256) public chainDailyAmount;
    mapping(uint64 => uint256) public chainLastReset;

    address public feeRecipient;

    // Events
    event MessageSent(bytes32 indexed messageId, uint64 indexed destinationChainSelector, address receiver, uint256 amount, uint256 fees);
    event DestinationChainAllowlisted(uint64 indexed chainSelector, bool allowed);
    event ReceiverAllowlisted(uint64 indexed chainSelector, address receiver);
    event ChainFeeUpdated(uint64 indexed chainSelector, uint256 feeBps);
    event FeeRecipientUpdated(address indexed recipient);
    event ChainCapsUpdated(uint64 indexed chainSelector, uint256 perSendCap, uint256 dailyLimit);

    // Errors
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);
    error DestinationChainNotAllowlisted(uint64 destinationChainSelector);
    error ReceiverNotAllowlisted(uint64 destinationChainSelector);
    error InvalidReceiverAddress();
    error FeeRecipientNotSet();
    error SendAmountExceedsCap(uint256 requested, uint256 cap);
    error DailyLimitExceeded(uint256 requested, uint256 remaining);
    error InvalidFeeBps();

    /**
     * @notice Initialize CCIP sender with router, LINK, and rebase token
     * @dev Sets up immutable references and initializes owner as fee recipient
     *
     * @param _router Chainlink CCIP Router address for this chain
     *        - Ethereum mainnet: 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D
     *        - Arbitrum: 0x141fa059441E0ca23ce184B6A78bafD2A517DdE8
     * @param _linkToken LINK token address for paying CCIP fees
     *        - Must be funded regularly to pay for cross-chain messages
     * @param _rebaseToken Address of RebaseToken contract to bridge
     *        - Must grant this contract BURNER_ROLE and MINTER_ROLE
     *
     * REQUIREMENTS:
     * - All addresses must be non-zero (no validation here, will revert on use)
     * - Deployer becomes owner (inherited from Ownable)
     * - feeRecipient initialized to deployer (can be changed later)
     *
     * EFFECTS:
     * - Sets immutable router reference (cannot be changed)
     * - Sets immutable LINK token reference (cannot be changed)
     * - Sets immutable rebase token reference (cannot be changed)
     * - Initializes feeRecipient to msg.sender
     * - Contract starts unpaused (can bridge immediately if configured)
     *
     * POST-DEPLOYMENT CHECKLIST:
     * 1. Call allowlistDestinationChain() for each supported destination
     * 2. Call allowlistReceiver() for receiver contract on each chain
     * 3. Call setChainFeeBps() to configure protocol fees
     * 4. Call setChainCaps() to set per-send and daily limits
     * 5. Fund contract with LINK tokens for CCIP fees
     * 6. Ensure rebaseToken has granted BURNER_ROLE and MINTER_ROLE
     *
     * Example Deployment:
     * ```
     * sender = new CCIPRebaseTokenSender(
     *     0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D,  // Ethereum CCIP router
     *     0x514910771AF9Ca656af840dff83E8264EcF986CA,  // LINK on Ethereum
     *     0xRebaseTokenAddress                         // RebaseToken
     * )
     * // Then configure chains:
     * sender.allowlistDestinationChain(ArbitrumSelector, true)
     * sender.allowlistReceiver(ArbitrumSelector, 0xReceiverOnArbitrum)
     * sender.setChainFeeBps(ArbitrumSelector, 500) // 5% fee
     * sender.setChainCaps(ArbitrumSelector, 1000e18, 100000e18) // caps
     * ```
     */
    constructor(address _router, address _linkToken, address _rebaseToken) Ownable(msg.sender) {
        i_router = IRouterClient(_router);
        i_linkToken = IERC20(_linkToken);
        rebaseToken = RebaseToken(_rebaseToken);
        feeRecipient = msg.sender;
    }

    /**
     * @notice Enable or disable bridging to a specific destination chain
     * @dev Controls which CCIP destination chains users can bridge tokens to
     *
     * @param _destinationChainSelector CCIP chain selector ID for destination
     *        - Arbitrum One: 4949039107694359620
     *        - Optimism: 3734403246176062136
     *        - Base: 15971525489660198786
     *        - Polygon: 4051577828743386545
     * @param allowed true to enable bridging, false to disable
     *
     * REQUIREMENTS:
     * - Can only be called by owner (governance or admin)
     * - No validation on chainSelector (any uint64 allowed)
     *
     * EFFECTS:
     * - Updates allowlistedDestinationChains mapping
     * - Emits DestinationChainAllowlisted event
     * - If false, all bridge attempts to this chain will revert
     * - If true, bridging allowed (still requires receiver to be set)
     *
     * USE CASES:
     * 1. Initial setup: Enable supported destination chains
     * 2. Emergency: Disable chain if CCIP or receiver has issues
     * 3. Expansion: Add new chains as CCIP support grows
     * 4. Deprecation: Disable old chains being sunset
     *
     * Example:
     * ```
     * // Enable Arbitrum bridging
     * sender.allowlistDestinationChain(4949039107694359620, true)
     *
     * // Disable in emergency
     * sender.allowlistDestinationChain(4949039107694359620, false)
     * // All sendTokensCrossChain to Arbitrum will now revert
     * ```
     */
    function allowlistDestinationChain(uint64 _destinationChainSelector, bool allowed) external onlyOwner {
        allowlistedDestinationChains[_destinationChainSelector] = allowed;
        emit DestinationChainAllowlisted(_destinationChainSelector, allowed);
    }

    /**
     * @notice Set the authorized receiver contract address for a destination chain
     * @dev Each destination chain has exactly one receiver (1:1 mapping)
     *
     * @param _destinationChainSelector CCIP chain selector for destination
     * @param _receiver Address of CCIPRebaseTokenReceiver on destination chain
     *        - Must be the deployed receiver contract address
     *        - Cannot be zero address (validation enforced)
     *
     * REQUIREMENTS:
     * - Can only be called by owner
     * - _receiver must not be address(0) (reverts with InvalidReceiverAddress)
     *
     * EFFECTS:
     * - Updates allowlistedReceivers[chainSelector] = receiver
     * - Emits ReceiverAllowlisted event
     * - All CCIP messages to this chain will target this receiver
     * - Previous receiver (if any) is overwritten
     *
     * SECURITY:
     * - Only set receiver to trusted CCIPRebaseTokenReceiver contracts
     * - Malicious receiver could steal all bridged tokens
     * - Verify receiver contract code before allowlisting
     * - Consider timelock for production changes
     *
     * USE CASES:
     * 1. Initial setup: Set receiver when deploying to new chain
     * 2. Upgrade: Point to new receiver if logic updated
     * 3. Migration: Move to new receiver for protocol changes
     *
     * Example:
     * ```
     * // Deploy receiver on Arbitrum at 0xABC...
     * // Then allowlist it on source chain:
     * sender.allowlistReceiver(
     *     4949039107694359620,  // Arbitrum selector
     *     0xABC...              // Receiver on Arbitrum
     * )
     * // Now users can bridge to Arbitrum
     * ```
     */
    function allowlistReceiver(uint64 _destinationChainSelector, address _receiver) external onlyOwner {
        if (_receiver == address(0)) revert InvalidReceiverAddress();
        allowlistedReceivers[_destinationChainSelector] = _receiver;
        emit ReceiverAllowlisted(_destinationChainSelector, _receiver);
    }

    /**
     * @notice Emergency stop all cross-chain bridging operations
     * @dev Activates Pausable contract pause state
     *
     * REQUIREMENTS:
     * - Can only be called by owner
     * - Contract must not already be paused
     *
     * EFFECTS:
     * - Sets paused = true
     * - sendTokensCrossChain() will revert with EnforcedPause()
     * - All bridge operations blocked until unpauseBridging() called
     * - Does not affect admin functions (owner can still configure)
     *
     * USE CASES:
     * 1. Security incident on this chain or destination
     * 2. CCIP router malfunction or upgrade
     * 3. Receiver contract compromise discovered
     * 4. Oracle manipulation affecting interest rates
     * 5. Protocol-wide emergency requiring halt
     *
     * Example Emergency Response:
     * ```
     * // Security team discovers receiver exploit
     * sender.pauseBridging()  // Immediately stop all bridges
     * // Investigate and fix
     * sender.allowlistReceiver(chain, newSecureReceiver)  // Update
     * sender.unpauseBridging()  // Resume operations
     * ```
     */
    function pauseBridging() external onlyOwner {
        _pause();
    }

    /**
     * @notice Resume cross-chain bridging operations after pause
     * @dev Deactivates Pausable contract pause state
     *
     * REQUIREMENTS:
     * - Can only be called by owner
     * - Contract must currently be paused
     *
     * EFFECTS:
     * - Sets paused = false
     * - sendTokensCrossChain() becomes callable again
     * - Normal bridge operations resume
     *
     * SAFETY CHECKLIST before unpausing:
     * 1. Verify security issue is resolved
     * 2. Confirm all receivers are secure
     * 3. Check CCIP router is operational
     * 4. Ensure rate limits are properly configured
     * 5. Verify LINK balance is sufficient
     * 6. Test with small bridge first if possible
     *
     * Example:
     * ```
     * // After fixing security issue:
     * sender.unpauseBridging()
     * // Users can now bridge again
     * ```
     */
    function unpauseBridging() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Set protocol fee percentage for a specific destination chain
     * @dev Configures per-chain bridge fees collected in rebase tokens
     *
     * @param _destinationChainSelector CCIP chain selector for destination
     * @param feeBps Fee in basis points (0-10000, where 10000 = 100%)
     *        - 0 = no fee (free bridging)
     *        - 100 = 1% fee
     *        - 500 = 5% fee (typical)
     *        - 10000 = 100% fee (blocks all bridging)
     *
     * REQUIREMENTS:
     * - Can only be called by owner
     * - feeBps must be ≤ 10,000 (reverts with InvalidFeeBps if exceeded)
     *
     * EFFECTS:
     * - Updates chainFeeBps[chainSelector]
     * - Emits ChainFeeUpdated event
     * - All future bridges to this chain use new fee
     * - In-flight bridges unaffected
     *
     * FEE COLLECTION MECHANICS:
     * When user bridges X tokens:
     * 1. Calculate: protocolFee = (X × feeBps) / 10,000
     * 2. Calculate: bridgedAmount = X - protocolFee
     * 3. Burn X tokens from user
     * 4. Send bridgedAmount to destination (via CCIP message)
     * 5. Mint protocolFee to feeRecipient on source chain
     * 6. Net effect: source supply -bridgedAmount, fees to protocol
     *
     * Example with 5% fee on 1000 token bridge:
     * ```
     * sender.setChainFeeBps(ArbitrumSelector, 500)  // 5% fee
     *
     * User bridges 1000 tokens:
     * protocolFee = (1000 × 500) / 10,000 = 50 tokens
     * bridgedAmount = 1000 - 50 = 950 tokens
     * Burn 1000 from user
     * Send 950 to Arbitrum receiver (user gets 950 on Arbitrum)
     * Mint 50 to feeRecipient on Ethereum (protocol revenue)
     * ```
     *
     * GOVERNANCE USE CASES:
     * 1. Set competitive fees based on CCIP costs per chain
     * 2. Incentivize/discourage bridging to specific chains
     * 3. Adjust fees based on destination chain adoption
     * 4. Zero fee for promotional periods or partnerships
     */
    function setChainFeeBps(uint64 _destinationChainSelector, uint256 feeBps) external onlyOwner {
        if (feeBps > 10_000) revert InvalidFeeBps();
        chainFeeBps[_destinationChainSelector] = feeBps;
        emit ChainFeeUpdated(_destinationChainSelector, feeBps);
    }

    /**
     * @notice Update the address that receives collected protocol fees
     * @dev Protocol fees are minted to this address when users bridge tokens
     *
     * @param recipient Address to receive protocol fees
     *        - Typically treasury multisig or governance contract
     *        - Cannot be zero address (reverts with InvalidReceiverAddress)
     *
     * REQUIREMENTS:
     * - Can only be called by owner
     * - recipient must not be address(0)
     *
     * EFFECTS:
     * - Updates feeRecipient address
     * - Emits FeeRecipientUpdated event
     * - All future protocol fees minted to new recipient
     * - Previous fees already collected are unaffected
     *
     * FEE MINTING FLOW:
     * When user bridges with protocol fee:
     * 1. Calculate protocolFee from chainFeeBps
     * 2. Burn full amount from user
     * 3. Send bridgedAmount to destination
     * 4. Mint protocolFee to feeRecipient on source chain
     *
     * GOVERNANCE CONSIDERATIONS:
     * - Use multisig for production (not EOA)
     * - Consider timelock for changes
     * - Coordinate with accounting/treasury
     * - Ensure recipient can handle rebase token mechanics
     *
     * Example:
     * ```
     * // Initial: fees go to deployer
     * // Update to treasury multisig:
     * sender.setFeeRecipient(0xTreasuryMultisig)
     * // All future fees mint to multisig
     * ```
     */
    function setFeeRecipient(address recipient) external onlyOwner {
        if (recipient == address(0)) revert InvalidReceiverAddress();
        feeRecipient = recipient;
        emit FeeRecipientUpdated(recipient);
    }

    /**
     * @notice Configure per-transaction and daily bridging limits for a chain
     * @dev Implements two-tier rate limiting: per-send cap and 24h daily limit
     *
     * @param _destinationChainSelector CCIP chain selector for destination
     * @param perSendCap Maximum tokens per single bridge transaction
     *        - 0 = no limit (unlimited per-tx bridging)
     *        - Typical: 1,000 to 10,000 tokens
     * @param dailyLimit Maximum tokens bridged to chain per 24 hours
     *        - 0 = no limit (unlimited daily bridging)
     *        - Typical: 100,000 to 1,000,000 tokens
     *
     * REQUIREMENTS:
     * - Can only be called by owner
     * - No validation that dailyLimit ≥ perSendCap (but recommended)
     *
     * EFFECTS:
     * - Updates chainSendCap[chainSelector] = perSendCap
     * - Updates chainDailyLimit[chainSelector] = dailyLimit
     * - Emits ChainCapsUpdated event
     * - All future bridges checked against new limits
     * - Current daily counter unaffected (continues until midnight UTC reset)
     *
     * RATE LIMITING MECHANICS:
     * Per-Send Cap Check:
     * ```
     * if (perSendCap > 0 && bridgeAmount > perSendCap) revert SendAmountExceedsCap
     * ```
     *
     * Daily Limit Check:
     * ```
     * dayBucket = block.timestamp / 1 days  // Midnight UTC buckets
     * if (chainLastReset[chain] != dayBucket) {
     *     chainLastReset[chain] = dayBucket
     *     chainDailyAmount[chain] = 0  // Reset counter
     * }
     * if (dailyLimit > 0 && chainDailyAmount[chain] + amount > dailyLimit) {
     *     revert DailyLimitExceeded
     * }
     * chainDailyAmount[chain] += amount  // Increment counter
     * ```
     *
     * Example Scenarios:
     * ```
     * // Scenario 1: Conservative limits for new chain
     * sender.setChainCaps(
     *     BaseSelector,
     *     100e18,      // Max 100 tokens per tx
     *     10000e18     // Max 10,000 tokens per day
     * )
     *
     * // Scenario 2: Mature chain with high volume
     * sender.setChainCaps(
     *     ArbitrumSelector,
     *     10000e18,    // Max 10,000 tokens per tx
     *     1000000e18   // Max 1M tokens per day
     * )
     *
     * // Scenario 3: Emergency - block all bridging
     * sender.setChainCaps(chain, 0, 0)  // Both zero = unlimited
     * // Actually, set to 1 wei to effectively block:
     * sender.setChainCaps(chain, 1, 1)  // Min possible
     *
     * // Scenario 4: Remove all limits
     * sender.setChainCaps(chain, 0, 0)  // No caps
     * ```
     *
     * GOVERNANCE USE CASES:
     * 1. Initial setup: Set conservative caps for new chains
     * 2. Growth: Increase caps as TVL and security proven
     * 3. Emergency: Drastically reduce caps during incidents
     * 4. Risk management: Different caps per chain based on maturity
     *
     * DAILY LIMIT RESET:
     * - Resets at midnight UTC (not 24h from first tx)
     * - Formula: block.timestamp / 86400 (1 days in seconds)
     * - All chains reset independently
     * - No manual reset needed
     */
    function setChainCaps(uint64 _destinationChainSelector, uint256 perSendCap, uint256 dailyLimit) external onlyOwner {
        chainSendCap[_destinationChainSelector] = perSendCap;
        chainDailyLimit[_destinationChainSelector] = dailyLimit;
        emit ChainCapsUpdated(_destinationChainSelector, perSendCap, dailyLimit);
    }

    /**
     * @dev Send tokens cross-chain
     * @param _destinationChainSelector Destination chain selector
     * @param _receiver Receiver address on destination chain
     * @param _amount Amount of tokens to send
     */
    function sendTokensCrossChain(
        uint64 _destinationChainSelector,
        address _receiver,
        uint256 _amount
    ) external whenNotPaused returns (bytes32 messageId) {
        // Validate destination chain
        if (!allowlistedDestinationChains[_destinationChainSelector]) {
            revert DestinationChainNotAllowlisted(_destinationChainSelector);
        }

        // Validate receiver
        address allowlistedReceiver = allowlistedReceivers[_destinationChainSelector];
        if (allowlistedReceiver == address(0)) {
            revert ReceiverNotAllowlisted(_destinationChainSelector);
        }

        // Enforce per-send cap if set
        uint256 perSendCap = chainSendCap[_destinationChainSelector];
        if (perSendCap > 0 && _amount > perSendCap) {
            revert SendAmountExceedsCap(_amount, perSendCap);
        }

        // Enforce daily cap if set
        uint256 dayBucket = block.timestamp / 1 days;
        if (chainLastReset[_destinationChainSelector] != dayBucket) {
            chainLastReset[_destinationChainSelector] = dayBucket;
            chainDailyAmount[_destinationChainSelector] = 0;
        }

        uint256 dailyLimit = chainDailyLimit[_destinationChainSelector];
        if (dailyLimit > 0 && chainDailyAmount[_destinationChainSelector] + _amount > dailyLimit) {
            uint256 remaining = dailyLimit - chainDailyAmount[_destinationChainSelector];
            revert DailyLimitExceeded(_amount, remaining);
        }

        // Calculate protocol fee
        uint256 feeBps = chainFeeBps[_destinationChainSelector];
        uint256 protocolFee = (feeBps > 0) ? (_amount * feeBps) / 10_000 : 0;
        uint256 bridgedAmount = _amount - protocolFee;

        // Burn tokens from sender
        rebaseToken.burn(msg.sender, _amount);

        // Get user's interest rate to bridge it
        uint256 userInterestRate = rebaseToken.getInterestRate(msg.sender);

        // Prepare CCIP message with interest rate
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(allowlistedReceiver),
            data: abi.encode(_receiver, bridgedAmount, userInterestRate),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 250_000})),
            feeToken: address(i_linkToken)
        });

        // Calculate fees
        uint256 fees = i_router.getFee(_destinationChainSelector, message);

        // Check LINK balance
        if (fees > i_linkToken.balanceOf(address(this))) {
            revert NotEnoughBalance(i_linkToken.balanceOf(address(this)), fees);
        }

        // Approve router to spend LINK
        i_linkToken.approve(address(i_router), fees);

        // Send message
        messageId = i_router.ccipSend(_destinationChainSelector, message);

        // Mint protocol fee to fee recipient to keep supply neutral
        if (protocolFee > 0) {
            if (feeRecipient == address(0)) revert FeeRecipientNotSet();
            rebaseToken.mint(feeRecipient, protocolFee, userInterestRate);
        }

        // Update accounting for daily limits
        chainDailyAmount[_destinationChainSelector] += _amount;

        emit MessageSent(messageId, _destinationChainSelector, _receiver, bridgedAmount, fees);

        return messageId;
    }

    /**
     * @dev Withdraw LINK tokens
     * @param _beneficiary Address to send tokens to
     */
    function withdrawLINK(address _beneficiary) external onlyOwner {
        uint256 amount = i_linkToken.balanceOf(address(this));
        i_linkToken.transfer(_beneficiary, amount);
    }

    /**
     * @dev Get router address
     */
    function getRouter() external view returns (address) {
        return address(i_router);
    }
}
