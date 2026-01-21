// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {RebaseToken} from "./RebaseToken.sol";

/**
 * @title EnhancedCCIPBridge
 * @dev Multi-chain bridge with batch transfers, composability, and rate limiting
 * Supports Ethereum, Polygon, Scroll, zkSync, Arbitrum, and more
 */
contract EnhancedCCIPBridge is CCIPReceiver, Ownable, Pausable, ReentrancyGuard {
    // ============= State Variables =============
    
    RebaseToken public immutable rebaseToken;
    IERC20 private immutable i_linkToken;

    // Chain registry: maps chain selector to metadata
    struct ChainConfig {
        bool enabled;
        address receiver;
        uint256 minBridgeAmount;
        uint256 maxBridgeAmount;
        uint256 batchWindow; // seconds
        bytes32 routerAddress; // for non-EVM chains
    }

    // Rate limiting: per-source-chain configuration
    struct RateLimitConfig {
        uint256 tokensPerSecond;
        uint256 maxBurstSize;
        uint256 lastRefillTime;
        uint256 tokensAvailable;
    }

    // Batch transfer tracking
    struct BatchTransfer {
        uint256 id;
        uint64 destinationChain;
        address[] recipients;
        uint256[] amounts;
        uint256 totalAmount;
        uint256 timestamp;
        bool executed;
    }

    // Composability routing: enables cross-chain contract calls
    struct ComposableRoute {
        uint64 targetChain;
        address targetContract;
        bytes callData;
        bool autoExecute;
    }

    mapping(uint64 => ChainConfig) public chainConfigs;
    mapping(uint64 => RateLimitConfig) public rateLimits;
    mapping(uint256 => BatchTransfer) public batchTransfers;
    mapping(bytes32 => ComposableRoute) public composableRoutes;

    // Token accounting
    mapping(address => mapping(uint64 => uint256)) public userBridgedAmount;
    mapping(uint64 => uint256) public chainBridgedTotal;

    // Batch accounting
    uint256 public batchCounter;
    mapping(uint64 => uint256[]) public chainBatches; // chain -> batch IDs

    // Rate limit token buckets per source chain
    mapping(uint64 => uint256) public chainRateLimitTokens;
    mapping(uint64 => uint256) public chainRateLimitLastUpdate;

    // Events
    event ChainConfigured(
        uint64 indexed chainSelector,
        address indexed receiver,
        uint256 minAmount,
        uint256 maxAmount
    );

    event RateLimitConfigured(
        uint64 indexed sourceChain,
        uint256 tokensPerSecond,
        uint256 maxBurstSize
    );

    event BatchCreated(
        uint256 indexed batchId,
        uint64 indexed destinationChain,
        uint256 recipientCount,
        uint256 totalAmount
    );

    event BatchExecuted(
        uint256 indexed batchId,
        bytes32 indexed messageId,
        uint64 indexed destinationChain
    );

    event ComposableRouteSet(
        bytes32 indexed routeId,
        uint64 indexed targetChain,
        address indexed targetContract
    );

    event CrossChainTransfer(
        bytes32 indexed messageId,
        uint64 indexed destinationChain,
        address indexed recipient,
        uint256 amount,
        uint256 fees
    );

    event RateLimitApplied(
        uint64 indexed sourceChain,
        uint256 tokensConsumed,
        uint256 tokensRemaining
    );

    event MessageReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address indexed sender,
        uint256 amount
    );

    // Errors
    error ChainNotConfigured(uint64 chainSelector);
    error InvalidReceiverAddress();
    error BridgeAmountOutOfBounds(uint256 amount, uint256 min, uint256 max);
    error RateLimitExceeded(uint256 requested, uint256 available);
    error InvalidBatchId();
    error BatchAlreadyExecuted();
    error EmptyBatchTransfer();
    error BatchAmountMismatch();
    error ComposableRouteNotSet();
    error InvalidSourceChain(uint64 chainSelector);
    error InsufficientLinkBalance();

    // ============= Constructor =============

    constructor(address _router, address _linkToken, address _rebaseToken) 
        CCIPReceiver(_router) 
        Ownable(msg.sender) 
    {
        i_linkToken = IERC20(_linkToken);
        rebaseToken = RebaseToken(_rebaseToken);
    }

    // ============= Chain Management =============

    /**
     * @dev Configure a new chain or update existing chain config
     * @param _chainSelector CCIP chain selector
     * @param _receiver Receiver contract on destination chain
     * @param _minAmount Minimum bridge amount
     * @param _maxAmount Maximum bridge amount
     * @param _batchWindow Time window for batch collection
     */
    function configureChain(
        uint64 _chainSelector,
        address _receiver,
        uint256 _minAmount,
        uint256 _maxAmount,
        uint256 _batchWindow
    ) external onlyOwner {
        if (_receiver == address(0)) revert InvalidReceiverAddress();
        if (_minAmount > _maxAmount) revert BridgeAmountOutOfBounds(_minAmount, 0, _maxAmount);

        chainConfigs[_chainSelector] = ChainConfig({
            enabled: true,
            receiver: _receiver,
            minBridgeAmount: _minAmount,
            maxBridgeAmount: _maxAmount,
            batchWindow: _batchWindow,
            routerAddress: bytes32(uint256(uint160(_receiver)))
        });

        emit ChainConfigured(_chainSelector, _receiver, _minAmount, _maxAmount);
    }

    /**
     * @dev Disable a chain without removing config
     * @param _chainSelector CCIP chain selector
     */
    function disableChain(uint64 _chainSelector) external onlyOwner {
        chainConfigs[_chainSelector].enabled = false;
        emit ChainConfigured(_chainSelector, address(0), 0, 0);
    }

    // ============= Rate Limiting =============

    /**
     * @dev Configure rate limiting for a source chain
     * @param _sourceChain Source chain selector
     * @param _tokensPerSecond Tokens allowed per second
     * @param _maxBurstSize Maximum burst size
     */
    function setRateLimit(
        uint64 _sourceChain,
        uint256 _tokensPerSecond,
        uint256 _maxBurstSize
    ) external onlyOwner {
        rateLimits[_sourceChain] = RateLimitConfig({
            tokensPerSecond: _tokensPerSecond,
            maxBurstSize: _maxBurstSize,
            lastRefillTime: block.timestamp,
            tokensAvailable: _maxBurstSize
        });

        chainRateLimitTokens[_sourceChain] = _maxBurstSize;
        chainRateLimitLastUpdate[_sourceChain] = block.timestamp;

        emit RateLimitConfigured(_sourceChain, _tokensPerSecond, _maxBurstSize);
    }

    /**
     * @dev Check and consume tokens from rate limit bucket
     * @param _sourceChain Source chain selector
     * @param _amount Amount to consume
     */
    function _consumeRateLimit(uint64 _sourceChain, uint256 _amount) internal {
        RateLimitConfig storage config = rateLimits[_sourceChain];
        
        // Skip if rate limiting not configured
        if (config.tokensPerSecond == 0) return;

        uint256 timePassed = block.timestamp - chainRateLimitLastUpdate[_sourceChain];
        uint256 tokensToAdd = (timePassed * config.tokensPerSecond);
        
        // Cap tokens available at max burst size
        uint256 available = chainRateLimitTokens[_sourceChain] + tokensToAdd;
        if (available > config.maxBurstSize) {
            available = config.maxBurstSize;
        }

        // Check if enough tokens available
        if (available < _amount) {
            revert RateLimitExceeded(_amount, available);
        }

        // Update state
        chainRateLimitTokens[_sourceChain] = available - _amount;
        chainRateLimitLastUpdate[_sourceChain] = block.timestamp;

        emit RateLimitApplied(_sourceChain, _amount, available - _amount);
    }

    // ============= Batch Transfers =============

    /**
     * @dev Create a batch transfer
     * @param _destinationChain Target chain selector
     * @param _recipients Array of recipient addresses
     * @param _amounts Array of amounts for each recipient
     * @return batchId ID of created batch
     */
    function createBatchTransfer(
        uint64 _destinationChain,
        address[] calldata _recipients,
        uint256[] calldata _amounts
    ) external whenNotPaused returns (uint256) {
        if (!chainConfigs[_destinationChain].enabled) {
            revert ChainNotConfigured(_destinationChain);
        }
        if (_recipients.length == 0) revert EmptyBatchTransfer();
        if (_recipients.length != _amounts.length) revert BatchAmountMismatch();

        // Validate each amount
        uint256 totalAmount = 0;
        uint256 minAmount = chainConfigs[_destinationChain].minBridgeAmount;
        uint256 maxAmount = chainConfigs[_destinationChain].maxBridgeAmount;

        for (uint256 i = 0; i < _amounts.length; i++) {
            if (_amounts[i] < minAmount || _amounts[i] > maxAmount) {
                revert BridgeAmountOutOfBounds(_amounts[i], minAmount, maxAmount);
            }
            totalAmount += _amounts[i];
        }

        // Create batch
        uint256 batchId = batchCounter++;
        
        BatchTransfer storage batch = batchTransfers[batchId];
        batch.id = batchId;
        batch.destinationChain = _destinationChain;
        batch.recipients = new address[](_recipients.length);
        batch.amounts = new uint256[](_amounts.length);
        batch.totalAmount = totalAmount;
        batch.timestamp = block.timestamp;
        batch.executed = false;

        // Copy data to storage
        for (uint256 i = 0; i < _recipients.length; i++) {
            batch.recipients[i] = _recipients[i];
            batch.amounts[i] = _amounts[i];
        }

        chainBatches[_destinationChain].push(batchId);

        emit BatchCreated(batchId, _destinationChain, _recipients.length, totalAmount);

        return batchId;
    }

    /**
     * @dev Execute a batch transfer via CCIP
     * @param _batchId ID of batch to execute
     */
    function executeBatch(uint256 _batchId) external onlyOwner nonReentrant whenNotPaused returns (bytes32) {
        BatchTransfer storage batch = batchTransfers[_batchId];
        
        if (batch.id != _batchId) revert InvalidBatchId();
        if (batch.executed) revert BatchAlreadyExecuted();
        if (batch.totalAmount == 0) revert EmptyBatchTransfer();

        ChainConfig storage config = chainConfigs[batch.destinationChain];
        if (!config.enabled) revert ChainNotConfigured(batch.destinationChain);

        // Check LINK balance
        uint256 fees = _estimateCCIPFees(batch.destinationChain, batch.totalAmount);
        if (i_linkToken.balanceOf(address(this)) < fees) {
            revert InsufficientLinkBalance();
        }

        // Prepare message
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(config.receiver),
            data: abi.encode(batch.recipients, batch.amounts),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 500_000})),
            feeToken: address(i_linkToken)
        });

        // Approve router and send
        i_linkToken.approve(address(i_ccipRouter), fees);
        bytes32 messageId = i_ccipRouter.ccipSend(batch.destinationChain, message);

        // Mark as executed and update accounting
        batch.executed = true;
        chainBridgedTotal[batch.destinationChain] += batch.totalAmount;

        emit BatchExecuted(_batchId, messageId, batch.destinationChain);

        return messageId;
    }

    // ============= Single Transfers =============

    /**
     * @dev Send single transfer cross-chain (for immediate transfers)
     * @param _destinationChain Target chain selector
     * @param _recipient Recipient address
     * @param _amount Amount to send
     */
    function bridgeTokens(
        uint64 _destinationChain,
        address _recipient,
        uint256 _amount
    ) external nonReentrant whenNotPaused returns (bytes32) {
        ChainConfig storage config = chainConfigs[_destinationChain];
        if (!config.enabled) revert ChainNotConfigured(_destinationChain);
        if (_amount < config.minBridgeAmount || _amount > config.maxBridgeAmount) {
            revert BridgeAmountOutOfBounds(_amount, config.minBridgeAmount, config.maxBridgeAmount);
        }

        // Check LINK balance
        uint256 fees = _estimateCCIPFees(_destinationChain, _amount);
        if (i_linkToken.balanceOf(address(this)) < fees) {
            revert InsufficientLinkBalance();
        }

        // Prepare message
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(config.receiver),
            data: abi.encode(_recipient, _amount),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 300_000})),
            feeToken: address(i_linkToken)
        });

        // Approve router and send
        i_linkToken.approve(address(i_ccipRouter), fees);
        bytes32 messageId = i_ccipRouter.ccipSend(_destinationChain, message);

        // Update accounting
        userBridgedAmount[msg.sender][_destinationChain] += _amount;
        chainBridgedTotal[_destinationChain] += _amount;

        emit CrossChainTransfer(messageId, _destinationChain, _recipient, _amount, fees);

        return messageId;
    }

    // ============= Composability =============

    /**
     * @dev Set up a composable route for cross-chain contract interactions
     * @param _routeId Unique identifier for this route
     * @param _targetChain Target chain selector
     * @param _targetContract Target contract address on destination chain
     * @param _callData Call data for target contract
     * @param _autoExecute Whether to execute automatically on receive
     */
    function setComposableRoute(
        bytes32 _routeId,
        uint64 _targetChain,
        address _targetContract,
        bytes calldata _callData,
        bool _autoExecute
    ) external onlyOwner {
        if (!chainConfigs[_targetChain].enabled) {
            revert ChainNotConfigured(_targetChain);
        }
        if (_targetContract == address(0)) revert InvalidReceiverAddress();

        composableRoutes[_routeId] = ComposableRoute({
            targetChain: _targetChain,
            targetContract: _targetContract,
            callData: _callData,
            autoExecute: _autoExecute
        });

        emit ComposableRouteSet(_routeId, _targetChain, _targetContract);
    }

    /**
     * @dev Execute composable call across chains
     * @param _routeId Route identifier
     * @param _amount Amount to bridge
     */
    function executeComposableCall(
        bytes32 _routeId,
        uint256 _amount
    ) external nonReentrant whenNotPaused returns (bytes32) {
        ComposableRoute storage route = composableRoutes[_routeId];
        if (route.targetContract == address(0)) revert ComposableRouteNotSet();

        ChainConfig storage config = chainConfigs[route.targetChain];
        if (!config.enabled) revert ChainNotConfigured(route.targetChain);

        // Prepare composable message
        bytes memory composableData = abi.encode(
            msg.sender,
            _amount,
            route.targetContract,
            route.callData,
            route.autoExecute
        );

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(config.receiver),
            data: composableData,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 600_000})),
            feeToken: address(i_linkToken)
        });

        uint256 fees = _estimateCCIPFees(route.targetChain, _amount);
        if (i_linkToken.balanceOf(address(this)) < fees) {
            revert InsufficientLinkBalance();
        }

        i_linkToken.approve(address(i_ccipRouter), fees);
        bytes32 messageId = i_ccipRouter.ccipSend(route.targetChain, message);

        emit CrossChainTransfer(messageId, route.targetChain, route.targetContract, _amount, fees);

        return messageId;
    }

    // ============= CCIP Receive =============

    /**
     * @dev Handle incoming CCIP messages
     * @param _any2EvmMessage The CCIP message
     */
    function _ccipReceive(Client.Any2EVMMessage memory _any2EvmMessage) 
        internal 
        override 
        whenNotPaused 
    {
        uint64 sourceChain = _any2EvmMessage.sourceChainSelector;
        
        // Check rate limit
        _consumeRateLimit(sourceChain, 1e18); // 1 token worth of rate limit

        // Decode message
        (address recipient, uint256 amount) = abi.decode(_any2EvmMessage.data, (address, uint256));

        // Mint tokens (interest rate encoded in separate message if needed)
        rebaseToken.mint(recipient, amount, 1000); // Default 10% rate

        emit MessageReceived(
            _any2EvmMessage.messageId,
            sourceChain,
            abi.decode(_any2EvmMessage.sender, (address)),
            amount
        );
    }

    // ============= Admin Functions =============

    /**
     * @dev Pause bridging in emergency
     */
    function pauseBridging() external onlyOwner {
        _pause();
    }

    /**
     * @dev Resume bridging
     */
    function unpauseBridging() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Withdraw LINK tokens (for owner to refund)
     * @param _amount Amount to withdraw
     */
    function withdrawLink(uint256 _amount) external onlyOwner {
        i_linkToken.transfer(msg.sender, _amount);
    }

    // ============= View Functions =============

    /**
     * @dev Get batch details
     * @param _batchId Batch ID
     */
    function getBatchDetails(uint256 _batchId) 
        external 
        view 
        returns (
            uint256 id,
            uint64 destinationChain,
            uint256 totalAmount,
            uint256 recipientCount,
            uint256 timestamp,
            bool executed
        ) 
    {
        BatchTransfer storage batch = batchTransfers[_batchId];
        return (
            batch.id,
            batch.destinationChain,
            batch.totalAmount,
            batch.recipients.length,
            batch.timestamp,
            batch.executed
        );
    }

    /**
     * @dev Get batch recipients and amounts
     * @param _batchId Batch ID
     */
    function getBatchTransfers(uint256 _batchId)
        external
        view
        returns (address[] memory recipients, uint256[] memory amounts)
    {
        BatchTransfer storage batch = batchTransfers[_batchId];
        return (batch.recipients, batch.amounts);
    }

    /**
     * @dev Get all batch IDs for a chain
     * @param _chainSelector Chain selector
     */
    function getChainBatches(uint64 _chainSelector) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return chainBatches[_chainSelector];
    }

    /**
     * @dev Get chain configuration
     * @param _chainSelector Chain selector
     */
    function getChainConfig(uint64 _chainSelector)
        external
        view
        returns (
            bool enabled,
            address receiver,
            uint256 minAmount,
            uint256 maxAmount,
            uint256 batchWindow
        )
    {
        ChainConfig storage config = chainConfigs[_chainSelector];
        return (
            config.enabled,
            config.receiver,
            config.minBridgeAmount,
            config.maxBridgeAmount,
            config.batchWindow
        );
    }

    /**
     * @dev Get rate limit status for a chain
     * @param _sourceChain Source chain selector
     */
    function getRateLimitStatus(uint64 _sourceChain)
        external
        view
        returns (
            uint256 tokensPerSecond,
            uint256 maxBurstSize,
            uint256 tokensAvailable,
            uint256 lastUpdate
        )
    {
        RateLimitConfig storage config = rateLimits[_sourceChain];
        uint256 timePassed = block.timestamp - chainRateLimitLastUpdate[_sourceChain];
        uint256 tokensToAdd = (timePassed * config.tokensPerSecond);
        uint256 available = chainRateLimitTokens[_sourceChain] + tokensToAdd;
        if (available > config.maxBurstSize) {
            available = config.maxBurstSize;
        }

        return (
            config.tokensPerSecond,
            config.maxBurstSize,
            available,
            chainRateLimitLastUpdate[_sourceChain]
        );
    }

    /**
     * @dev Estimate CCIP fees (simplified)
     * @param _destinationChain Destination chain
     * @param _amount Amount to transfer
     */
    function _estimateCCIPFees(uint64 _destinationChain, uint256 _amount)
        internal
        view
        returns (uint256)
    {
        // Simplified fee estimation
        // In production, use actual router.getFee()
        return 1 * 10**18; // 1 LINK as placeholder
    }

    /**
     * @dev Get supported chains count
     */
    function getSupportedChainsCount() external view returns (uint256) {
        // In production, maintain a counter or array
        return batchCounter; // Placeholder
    }
}
