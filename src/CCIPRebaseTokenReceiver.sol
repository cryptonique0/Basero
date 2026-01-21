// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {RebaseToken} from "./RebaseToken.sol";

/**
 * @title CCIPRebaseTokenReceiver
 * @dev Receives cross-chain rebase token transfers via Chainlink CCIP
 */
contract CCIPRebaseTokenReceiver is CCIPReceiver, Ownable {
    RebaseToken public immutable rebaseToken;

    // Mapping to track allowed source chains
    mapping(uint64 => bool) public allowlistedSourceChains;

    // Mapping to track allowed sender contracts on source chains
    mapping(uint64 => address) public allowlistedSenders;

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

    // Errors
    error SourceChainNotAllowlisted(uint64 sourceChainSelector);
    error SenderNotAllowlisted(address sender);
    error InvalidSenderAddress();

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

    /**
     * @dev Handle received CCIP messages
     * @param any2EvmMessage CCIP message
     */
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
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

        // Decode message data
        (address recipient, uint256 amount) = abi.decode(any2EvmMessage.data, (address, uint256));

        // Mint tokens to recipient
        rebaseToken.mint(recipient, amount);

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
