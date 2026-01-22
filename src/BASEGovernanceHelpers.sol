// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {RebaseTokenVault} from "./RebaseTokenVault.sol";
import {CCIPRebaseTokenSender} from "./CCIPRebaseTokenSender.sol";
import {CCIPRebaseTokenReceiver} from "./CCIPRebaseTokenReceiver.sol";

/**
 * @title BASEGovernanceHelpers
 * @author Basero Labs
 * @notice Provides utilities for encoding governance proposals for parameter changes
 * @dev Helper contract for constructing governable parameter updates
 *
 * ARCHITECTURE:
 * This contract provides proposal encoders for governance to update critical
 * parameters across Vault and CCIP Bridge contracts. Used by off-chain tools
 * or governance interfaces to generate proposal data.
 *
 * PROPOSAL TYPES (7 total):
 * 1. Vault Fee Updates - Update protocol fee % and recipient
 * 2. Vault Deposit Caps - Update min/per-user/global caps
 * 3. Vault Accrual Config - Update interest accrual period and daily max
 * 4. CCIP Per-Chain Fees - Update bridge fees per destination chain
 * 5. CCIP Per-Chain Caps - Update send cap and daily limits per chain
 * 6. Treasury Distribution - Distribute accumulated protocol funds
 * 7. Utility Functions - Convert uint256/address to strings for descriptions
 *
 * WORKFLOW:
 * 1. Off-chain: Call encode*Proposal() function with new parameters
 * 2. Returns: targets[], values[], calldatas[], and description string
 * 3. Governance: Submit proposal with returned data to BASEGovernor
 * 4. Voters: Vote on proposal for 7 days
 * 5. Execute: If passed, proposal auto-executes via timelock (2-day delay)
 *
 * SECURITY CONSIDERATIONS:
 * - Parameter validation: feeBps ≤ 10000 bps (100%), accrualBps ≤ 1000 bps (10%)
 * - All proposals are governance-controlled (no admin backdoors)
 * - Timelock provides 2-day security delay before execution
 * - Proper array length checks prevent mismatched parameters
 *
 * KEY FORMULAS:
 * - Fee basis points: feeBps / 10000 = fee percentage
 *   Example: 500 bps = 5% fee
 * - Daily accrual limit: maxDailyBps / 10000 = max daily percentage
 *   Example: 500 bps = 5% max per day
 */
contract BASEGovernanceHelpers {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    RebaseTokenVault public vault;
    CCIPRebaseTokenSender public sender;
    CCIPRebaseTokenReceiver public receiver;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidVaultAddress();
    error InvalidSenderAddress();
    error InvalidReceiverAddress();
    error InvalidParameters();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize governance helpers with contract addresses
     * @dev Sets up references to vault and CCIP bridge contracts for proposal encoding
     * 
     * @param _vault Address of RebaseTokenVault for vault parameter updates
     * @param _sender Address of CCIPRebaseTokenSender for CCIP source chain config
     * @param _receiver Address of CCIPRebaseTokenReceiver for destination chain monitoring
     *
     * REQUIREMENTS:
     * - _vault must not be zero address (prevents incorrect proposals)
     * - _sender must not be zero address (prevents bridging to 0x0)
     * - _receiver must not be zero address (prevents orphaned receiver)
     *
     * EFFECTS:
     * - Sets vault reference for encodeVaultFeeProposal, encodeVaultCapProposal, etc.
     * - Sets sender reference for CCIP fee and cap encoding
     * - Sets receiver reference for potential future receiver-controlled proposals
     *
     * Example:
     * ```
     * helpers = new BASEGovernanceHelpers(
     *     0x123... (vault),
     *     0x456... (sender),
     *     0x789... (receiver)
     * )
     * ```
     */
    constructor(address _vault, address _sender, address _receiver) {
        if (_vault == address(0)) revert InvalidVaultAddress();
        if (_sender == address(0)) revert InvalidSenderAddress();
        if (_receiver == address(0)) revert InvalidReceiverAddress();

        vault = RebaseTokenVault(_vault);
        sender = CCIPRebaseTokenSender(_sender);
        receiver = CCIPRebaseTokenReceiver(_receiver);
    }

    /*//////////////////////////////////////////////////////////////
                       VAULT FEE PROPOSALS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Encode a vault fee configuration proposal for governance
     * @dev Creates proposal data to update vault protocol fees and recipient
     * @dev Governance workflow: encode → submit to Governor → vote → execute via timelock
     *
     * @param feeRecipient New address to receive collected protocol fees
     * @param feeBps New fee basis points (0-10000, where 10000 = 100%)
     *
     * @return targets Array containing [vault address]
     * @return values Array containing [0] (no ETH sent)
     * @return calldatas Array containing encoded setFeeConfig() call
     * @return description Human-readable proposal description
     *
     * REQUIREMENTS:
     * - feeBps ≤ 10000 bps (reverts if > 100%)
     * - feeRecipient must be valid (no validation here, done at execution)
     * - proposal must be passed by governance vote
     * - proposal must pass timelock 2-day delay before execution
     *
     * EFFECTS (when executed via timelock):
     * - Vault feeRecipient updated to new address
     * - Vault feeBps updated to new percentage
     * - All future deposits collect fees at new rate
     * - Existing balances unaffected
     *
     * FEE BASIS POINTS FORMULA:
     * actualFee = depositAmount × (feeBps / 10000)
     * Examples:
     * - 500 bps = 5% fee
     * - 100 bps = 1% fee
     * - 0 bps = 0% fee (no collection)
     * - 10000 bps = 100% fee (vault keeps all, users get nothing)
     *
     * Example Usage:
     * ```
     * (targets, values, calldatas, description) = helpers.encodeVaultFeeProposal(
     *     0xTreasury,  // new fee recipient
     *     500          // 5% fee
     * )
     * // Submit to governor: governor.propose(targets, values, calldatas, description)
     * ```
     */
    function encodeVaultFeeProposal(address feeRecipient, uint16 feeBps)
        external
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        if (feeBps > 10000) revert InvalidParameters();

        targets = new address[](1);
        targets[0] = address(vault);

        values = new uint256[](1);
        values[0] = 0;

        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("setFeeConfig(address,uint16)", feeRecipient, feeBps);

        description = string(
            abi.encodePacked("Update vault protocol fee to ", _uint2str(feeBps), " bps and recipient to ", _addr2str(feeRecipient))
        );

        return (targets, values, calldatas, description);
    }

    /*//////////////////////////////////////////////////////////////
                       VAULT DEPOSIT CAP PROPOSALS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Encode a vault deposit cap proposal for governance
     * @dev Creates proposal data to update vault deposit limits (min/per-user/global)
     * @dev Controls protocol growth rate and per-user concentration risk
     *
     * @param minDeposit Minimum deposit amount in wei (prevents dust)
     * @param maxDepositPerAddress Per-address cap in wei (limits concentration)
     * @param maxTotalDeposits Global TVL cap in wei (limits protocol size)
     *
     * @return targets Array containing [vault address]
     * @return values Array containing [0] (no ETH sent)
     * @return calldatas Array containing encoded setDepositCaps() call
     * @return description Human-readable proposal description
     *
     * EFFECTS (when executed):
     * - Vault minDeposit, maxDepositPerAddress, maxTotalDeposits updated
     * - Existing deposits unaffected, new deposits checked against new caps
     * - Deposits above cap revert with error
     *
     * Example with production values:
     * ```
     * minDeposit = 0.1 ether          // 0.1 ETH minimum
     * maxPerAddress = 100 ether       // 100 ETH per user max
     * maxTotal = 10000 ether          // 10,000 ETH global cap
     * ```
     */
    function encodeVaultCapProposal(uint256 minDeposit, uint256 maxDepositPerAddress, uint256 maxTotalDeposits)
        external
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        targets = new address[](1);
        targets[0] = address(vault);

        values = new uint256[](1);
        values[0] = 0;

        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setDepositCaps(uint256,uint256,uint256)",
            minDeposit,
            maxDepositPerAddress,
            maxTotalDeposits
        );

        description = string(
            abi.encodePacked("Update vault deposit caps: min=", _uint2str(minDeposit), ", per-user=", _uint2str(maxDepositPerAddress), ", total=", _uint2str(maxTotalDeposits))
        );

        return (targets, values, calldatas, description);
    }

    /*//////////////////////////////////////////////////////////////
                      VAULT ACCRUAL PROPOSALS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Encode a vault accrual configuration proposal for governance
     * @dev Creates proposal data to update interest accrual frequency and daily limits
     * @dev Controls how fast interest compounds and prevents runaway accrual via circuit breaker
     *
     * @param accrualPeriod Accrual period in seconds (1 hour to 7 days)
     *        - Lower = more frequent (more compounding, higher gas)
     *        - Higher = less frequent (better efficiency, less precision)
     * @param maxDailyAccrualBps Max daily accrual in bps (0-1000, i.e., 0-10%)
     *        - Circuit breaker to prevent unexpected growth
     *
     * @return targets Array containing [vault address]
     * @return values Array containing [0] (no ETH sent)
     * @return calldatas Array containing encoded setAccrualConfig() call
     * @return description Human-readable proposal description
     *
     * EFFECTS (when executed via timelock):
     * - Vault accrualPeriod updated (affects performUpkeep automation interval)
     * - Vault maxDailyAccrualBps updated (affects circuit breaker in _accrueInterest)
     * - Next interest accrual uses new parameters
     * - Existing accrued interest unaffected
     *
     * CIRCUIT BREAKER FORMULA:
     * maxAllowed = (totalETH × maxDailyAccrualBps) / 10000
     * actualAccrual = min(calculatedInterest, maxAllowed)
     *
     * Example: 1000 ETH vault at 4% APY with 5% daily circuit breaker
     * dailyInterest = (1000 × 4%) / 365 ≈ 0.11 ETH
     * maxAllowed = (1000 × 5%) / 100 = 5 ETH
     * actualAccrual = min(0.11, 5) = 0.11 ETH (within limit, all accrued)
     */
    function encodeVaultAccrualProposal(uint256 accrualPeriod, uint16 maxDailyAccrualBps)
        external
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        if (maxDailyAccrualBps > 1000) revert InvalidParameters(); // Max 10% daily

        targets = new address[](1);
        targets[0] = address(vault);

        values = new uint256[](1);
        values[0] = 0;

        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("setAccrualConfig(uint256,uint16)", accrualPeriod, maxDailyAccrualBps);

        description = string(
            abi.encodePacked("Update vault accrual: period=", _uint2str(accrualPeriod), "s, max daily=", _uint2str(maxDailyAccrualBps), " bps")
        );

        return (targets, values, calldatas, description);
    }

    /*//////////////////////////////////////////////////////////////
                      CCIP FEE PROPOSALS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Encode a CCIP per-chain fee proposal for governance
     * @dev Creates proposal data to update bridge fees for specific destination chains
     * @dev Each destination has different CCIP infrastructure costs, justified by different fees
     *
     * @param chainSelector CCIP chain selector ID (e.g., 5009297550715157269 for Arbitrum)
     * @param feeBps Bridge fee in basis points for that chain (0-10000, i.e., 0-100%)
     *
     * @return targets Array containing [sender address]
     * @return values Array containing [0] (no ETH sent)
     * @return calldatas Array containing encoded setChainFeeBps() call
     * @return description Human-readable proposal description
     *
     * FEE CALCULATION FORMULA (in CCIPRebaseTokenSender.bridgeTokens()):
     * feeAmount = (bridgeAmount × chainFeeBps[chainSelector]) / 10000
     * actualBridgeAmount = bridgeAmount - feeAmount
     *
     * Example: 100 token bridge to Arbitrum with 500 bps fee
     * feeAmount = (100 × 500) / 10000 = 5 tokens
     * User receives: 95 tokens, protocol keeps: 5 tokens
     */
    function encodeCCIPFeeProposal(uint64 chainSelector, uint16 feeBps)
        external
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        if (feeBps > 10000) revert InvalidParameters();

        targets = new address[](1);
        targets[0] = address(sender);

        values = new uint256[](1);
        values[0] = 0;

        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("setChainFeeBps(uint64,uint16)", chainSelector, feeBps);

        description = string(
            abi.encodePacked("Update CCIP fee for chain ", _uint2str(uint256(chainSelector)), " to ", _uint2str(feeBps), " bps")
        );

        return (targets, values, calldatas, description);
    }

    /*//////////////////////////////////////////////////////////////
                      CCIP CAP PROPOSALS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Encode a CCIP per-chain cap proposal for governance
     * @dev Creates proposal data to update bridging limits for specific destination chains
     * @dev Provides per-transaction and per-day rate limiting for risk management
     *
     * @param chainSelector CCIP chain selector ID for the destination chain
     * @param sendCap Maximum amount per single bridge transaction (token units)
     * @param dailyLimit Maximum amount that can be bridged to that chain per day
     *
     * @return targets Array containing [sender address]
     * @return values Array containing [0] (no ETH sent)
     * @return calldatas Array containing encoded setChainCaps() call
     * @return description Human-readable proposal description
     *
     * RATE LIMITING FORMULAS (in CCIPRebaseTokenSender.bridgeTokens()):
     * Single transaction: require(bridgeAmount ≤ sendCap, \"exceeds per-tx limit\")
     * Daily aggregate: require(dailyBridged[chain] + amount ≤ dailyLimit, \"exceeds daily limit\")
     *
     * Example with tiered chains:
     * Arbitrum (mature): sendCap = 1000, dailyLimit = 100000
     * Base (conservative): sendCap = 100, dailyLimit = 10000
     */
    function encodeCCIPCapProposal(uint64 chainSelector, uint256 sendCap, uint256 dailyLimit)
        external
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        targets = new address[](1);
        targets[0] = address(sender);

        values = new uint256[](1);
        values[0] = 0;

        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("setChainCaps(uint64,uint256,uint256)", chainSelector, sendCap, dailyLimit);

        description = string(
            abi.encodePacked(
                "Update CCIP caps for chain ",
                _uint2str(uint256(chainSelector)),
                ": send=",
                _uint2str(sendCap),
                ", daily=",
                _uint2str(dailyLimit)
            )
        );

        return (targets, values, calldatas, description);
    }

    /*//////////////////////////////////////////////////////////////
                      TREASURY DISTRIBUTION PROPOSALS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Encode a treasury ETH distribution proposal
     * @dev Governance can distribute accumulated treasury funds
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts to send (in wei)
     * @param timelockAddress Address of timelock holding funds
     * @return targets Array with timelock address repeated
     * @return values Array with ETH amounts
     * @return calldatas Array with encoded receive function calls (empty for ETH transfer)
     * @return description Proposal description
     */
    function encodeTreasuryDistributionProposal(
        address[] memory recipients,
        uint256[] memory amounts,
        address timelockAddress
    )
        external
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        if (recipients.length != amounts.length) revert InvalidParameters();

        targets = new address[](recipients.length);
        values = new uint256[](recipients.length);
        calldatas = new bytes[](recipients.length);

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            targets[i] = recipients[i];
            values[i] = amounts[i];
            calldatas[i] = "";
            totalAmount += amounts[i];
        }

        description = string(abi.encodePacked("Distribute ", _uint2str(totalAmount), " wei from treasury to ", _uint2str(recipients.length), " recipients"));

        return (targets, values, calldatas, description);
    }

    /*//////////////////////////////////////////////////////////////
                        UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Convert uint256 to string
     * @param value Value to convert
     * @return String representation
     */
    function _uint2str(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @notice Convert address to string
     * @param account Address to convert
     * @return String representation
     */
    function _addr2str(address account) internal pure returns (string memory) {
        return _bytes2hexString(abi.encodePacked(account));
    }

    /**
     * @notice Convert bytes to hex string
     * @param data Bytes to convert
     * @return Hex string
     */
    function _bytes2hexString(bytes memory data) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < data.length; i++) {
            str[2 + i * 2] = hexChars[uint8(data[i]) >> 4];
            str[3 + i * 2] = hexChars[uint8(data[i]) & 0x0f];
        }
        return string(str);
    }
}
