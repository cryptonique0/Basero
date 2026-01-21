// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title BASETimelock
 * @dev Timelock contract for delayed execution of governance decisions
 * @notice Enforces a minimum delay between proposal and execution
 *
 * TIMELOCK PARAMETERS:
 * - Minimum Delay: 2 days (172,800 seconds)
 * - This ensures community has time to review and react to governance decisions
 *
 * ROLE HIERARCHY:
 * - Proposer Role: Can queue operations (typically the Governor contract)
 * - Executor Role: Can execute operations after delay (typically PUBLIC)
 * - Admin Role: Can manage roles (typically multisig or later transferred to governance)
 *
 * KEY FEATURES:
 * - Queues operations with execution delay
 * - Executes operations after delay passes
 * - Cancels queued operations (admin only)
 * - Manages role assignments
 */
contract BASETimelock is TimelockController {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Minimum delay between proposal and execution
    uint256 public constant MIN_DELAY = 2 days;

    // Governor address (proposer)
    address public governorAddress;

    // Treasury multisig (initial admin)
    address public treasuryMultisig;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event GovernorUpdated(address indexed oldGovernor, address indexed newGovernor);
    event TreasuryMultisigUpdated(address indexed oldMultisig, address indexed newMultisig);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidGovernorAddress();
    error InvalidMultisigAddress();
    error OnlyGovernor();
    error OnlyMultisig();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Initialize timelock with governor and multisig addresses
     * @param _governorAddress Address of the BASEGovernor contract
     * @param _treasuryMultisig Address of treasury multisig (initial admin)
     * @param _proposers Array of proposer addresses (typically just governor)
     * @param _executors Array of executor addresses (typically address(0) for public execution)
     * @param _admin Initial admin address (typically treasury multisig)
     */
    constructor(
        address _governorAddress,
        address _treasuryMultisig,
        address[] memory _proposers,
        address[] memory _executors,
        address _admin
    ) TimelockController(_proposers, _executors, _admin) {
        if (_governorAddress == address(0)) revert InvalidGovernorAddress();
        if (_treasuryMultisig == address(0)) revert InvalidMultisigAddress();

        governorAddress = _governorAddress;
        treasuryMultisig = _treasuryMultisig;
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update governor address (only multisig)
     * @dev Used if governor contract is upgraded or replaced
     * @param newGovernor Address of new governor
     */
    function updateGovernor(address newGovernor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newGovernor == address(0)) revert InvalidGovernorAddress();

        address oldGovernor = governorAddress;
        governorAddress = newGovernor;

        emit GovernorUpdated(oldGovernor, newGovernor);
    }

    /**
     * @notice Update treasury multisig (only current multisig)
     * @dev Used if multisig changes or is upgraded
     * @param newMultisig Address of new treasury multisig
     */
    function updateTreasuryMultisig(address newMultisig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newMultisig == address(0)) revert InvalidMultisigAddress();

        address oldMultisig = treasuryMultisig;
        treasuryMultisig = newMultisig;

        emit TreasuryMultisigUpdated(oldMultisig, newMultisig);
    }

    /*//////////////////////////////////////////////////////////////
                         TREASURY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emergency withdrawal of ETH (multisig only, no delay)
     * @dev Bypasses timelock for emergency situations
     * @param recipient Address to receive ETH
     * @param amount Amount of ETH to withdraw
     */
    function emergencyWithdrawETH(address payable recipient, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (recipient == address(0)) revert InvalidMultisigAddress();
        require(amount <= address(this).balance, "Insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Transfer failed");
    }

    /**
     * @notice Check current ETH balance in timelock
     * @return Current ETH balance
     */
    function getTreasuryBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get minimum delay for operations
     * @return Delay in seconds (2 days)
     */
    function getMinDelay() external pure returns (uint256) {
        return MIN_DELAY;
    }

    /**
     * @notice Check if operation is ready for execution
     * @param id Operation ID
     * @return True if operation can be executed
     */
    function isOperationReady(bytes32 id) external view returns (bool) {
        return isOperationReady(id);
    }

    /**
     * @notice Get current block timestamp
     * @return Current timestamp
     */
    function getCurrentTimestamp() external view returns (uint256) {
        return block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                        RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Receive ETH sent to timelock
     */
    receive() external payable {}
}
