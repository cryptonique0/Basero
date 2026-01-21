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
 * @dev Receives cross-chain rebase token transfers via Chainlink CCIP
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
     * @dev Constructor
     * @param _router CCIP Router address
     * @param _rebaseToken Rebase token address
     */
    constructor(address _router, address _rebaseToken) CCIPReceiver(_router) Ownable(msg.sender) {
        rebaseToken = RebaseToken(_rebaseToken);
    }

    /**
     * @dev Allowlist a source chain
     * @param _sourceChainSelector Chain selector to allowlist
     * @param allowed Whether the chain is allowed
     */
    function allowlistSourceChain(uint64 _sourceChainSelector, bool allowed) external onlyOwner {
        allowlistedSourceChains[_sourceChainSelector] = allowed;
        emit SourceChainAllowlisted(_sourceChainSelector, allowed);
    }

    /**
     * @dev Allowlist a sender on a source chain
     * @param _sourceChainSelector Chain selector
     * @param _sender Sender address
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
