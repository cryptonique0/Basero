// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {RebaseTokenVault} from "./RebaseTokenVault.sol";
import {CCIPRebaseTokenSender} from "./CCIPRebaseTokenSender.sol";
import {CCIPRebaseTokenReceiver} from "./CCIPRebaseTokenReceiver.sol";

/**
 * @title BASEGovernanceHelpers
 * @dev Helper contract for constructing governance proposals
 * @notice Provides utilities to encode common parameter change proposals
 *
 * SUPPORTED PROPOSALS:
 * - Vault fee updates
 * - Vault cap updates
 * - Vault accrual configuration
 * - CCIP per-chain fee updates
 * - CCIP cap updates
 * - Treasury ETH distributions
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
     * @notice Encode a vault fee configuration proposal
     * @dev Governance can update protocol fees via this proposal
     * @param feeRecipient New fee recipient address
     * @param feeBps New fee basis points (0-10000)
     * @return targets Array with vault address
     * @return values Array with 0 ETH
     * @return calldatas Array with encoded setFeeConfig call
     * @return description Proposal description
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
     * @notice Encode a vault deposit cap proposal
     * @dev Governance can update deposit limits via this proposal
     * @param minDeposit New minimum deposit amount
     * @param maxDepositPerAddress New per-user cap
     * @param maxTotalDeposits New global TVL cap
     * @return targets Array with vault address
     * @return values Array with 0 ETH
     * @return calldatas Array with encoded setDepositCaps call
     * @return description Proposal description
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
     * @notice Encode a vault accrual configuration proposal
     * @dev Governance can update interest accrual parameters
     * @param accrualPeriod New accrual period in seconds (1 hour to 7 days)
     * @param maxDailyAccrualBps Max daily accrual in basis points
     * @return targets Array with vault address
     * @return values Array with 0 ETH
     * @return calldatas Array with encoded setAccrualConfig call
     * @return description Proposal description
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
     * @notice Encode a CCIP per-chain fee proposal
     * @dev Governance can update bridge fees per destination chain
     * @param chainSelector CCIP chain selector
     * @param feeBps Fee in basis points for that chain
     * @return targets Array with sender address
     * @return values Array with 0 ETH
     * @return calldatas Array with encoded setChainFeeBps call
     * @return description Proposal description
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
     * @notice Encode a CCIP per-chain cap proposal
     * @dev Governance can update bridging limits per destination chain
     * @param chainSelector CCIP chain selector
     * @param sendCap Maximum amount per send transaction
     * @param dailyLimit Maximum amount per day
     * @return targets Array with sender address
     * @return values Array with 0 ETH
     * @return calldatas Array with encoded setChainCaps call
     * @return description Proposal description
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
