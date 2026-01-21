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
 * @dev Handles cross-chain transfers of rebase tokens using Chainlink CCIP
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
     * @dev Constructor
     * @param _router CCIP Router address
     * @param _linkToken LINK token address
     * @param _rebaseToken Rebase token address
     */
    constructor(address _router, address _linkToken, address _rebaseToken) Ownable(msg.sender) {
        i_router = IRouterClient(_router);
        i_linkToken = IERC20(_linkToken);
        rebaseToken = RebaseToken(_rebaseToken);
        feeRecipient = msg.sender;
    }

    /**
     * @dev Allowlist a destination chain
     * @param _destinationChainSelector Chain selector to allowlist
     * @param allowed Whether the chain is allowed
     */
    function allowlistDestinationChain(uint64 _destinationChainSelector, bool allowed) external onlyOwner {
        allowlistedDestinationChains[_destinationChainSelector] = allowed;
        emit DestinationChainAllowlisted(_destinationChainSelector, allowed);
    }

    /**
     * @dev Allowlist a receiver on a destination chain
     * @param _destinationChainSelector Chain selector
     * @param _receiver Receiver address
     */
    function allowlistReceiver(uint64 _destinationChainSelector, address _receiver) external onlyOwner {
        if (_receiver == address(0)) revert InvalidReceiverAddress();
        allowlistedReceivers[_destinationChainSelector] = _receiver;
        emit ReceiverAllowlisted(_destinationChainSelector, _receiver);
    }

    function pauseBridging() external onlyOwner {
        _pause();
    }

    function unpauseBridging() external onlyOwner {
        _unpause();
    }

    function setChainFeeBps(uint64 _destinationChainSelector, uint256 feeBps) external onlyOwner {
        if (feeBps > 10_000) revert InvalidFeeBps();
        chainFeeBps[_destinationChainSelector] = feeBps;
        emit ChainFeeUpdated(_destinationChainSelector, feeBps);
    }

    function setFeeRecipient(address recipient) external onlyOwner {
        if (recipient == address(0)) revert InvalidReceiverAddress();
        feeRecipient = recipient;
        emit FeeRecipientUpdated(recipient);
    }

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
