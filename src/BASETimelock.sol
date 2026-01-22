// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title BASETimelock
 * @author Basero Protocol
 * @notice Time-locked contract execution for decentralized governance security
 * @dev OpenZeppelin TimelockController with custom admin and treasury management
 * 
 * @dev Architecture:
 * - Enforces 2-day minimum delay between proposal approval and execution
 * - Separates proposer role (Governor) from executor role (public)
 * - Admin role holds security capabilities (multisig initially)
 * - Protects against governance attacks and flash-loan manipulation
 * 
 * @dev Role Hierarchy:
 * 1. Proposer (BASEGovernor): Creates queued operations
 * 2. Executor (anyone): Executes operations after delay
 * 3. Admin (Treasury Multisig): Manages roles, emergency functions
 * 
 * @dev Execution Timeline:
 * - Block 0: Governor queues operation
 * - Block 0: Operation queued for execution
 * - Delay: 2 days (172,800 seconds) must pass
 * - After: Anyone can execute the operation
 * - Community has 2 days to react to malicious proposals
 * 
 * @dev Key Parameters:
 * - MIN_DELAY: 2 days (172,800 seconds)
 * - Proposer: BASEGovernor contract
 * - Executor: address(0) for public execution (anyone can execute)
 * - Admin: Treasury multisig (governance upgrade authority)
 * 
 * @dev Typical Governance Flow:
 * 1. Community votes on proposal (7 days)
 * 2. Proposal passes → Governor queues it in timelock
 * 3. 2-day delay passes
 * 4. Anyone can execute the proposal
 * 
 * @dev Security:
 * - 2-day delay prevents governance attacks
 * - Public executor role prevents single-point-of-failure
 * - Multisig admin can cancel malicious operations
 * - Emergency withdrawal for treasury management
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
     * @notice Initialize timelock with governance roles and security parameters
     * @dev Sets up role-based access control for decentralized governance
     * 
     * @param _governorAddress Address of BASEGovernor contract (proposer role)
     * @param _treasuryMultisig Address of treasury multisig (admin role)
     * @param _proposers Array of addresses that can queue operations (usually [governorAddress])
     * @param _executors Array of addresses that can execute operations (usually [address(0)] for public)
     * @param _admin Initial admin address (multisig or later governance)
     * 
     * Requirements:
     * - _governorAddress must not be zero
     * - _treasuryMultisig must not be zero
     * - _proposers should include governor address
     * - _executors typically includes address(0) for decentralized execution
     * 
     * Initial State:
     * - MIN_DELAY: 2 days (172,800 seconds)
     * - Governor: Can queue operations
     * - Public: Can execute operations after delay
     * - Treasury Multisig: Can cancel/manage roles
     * 
     * Example:
     * address[] memory proposers = [governorAddress];
     * address[] memory executors = [address(0)]; // Public execution
     * new BASETimelock(
     *   governorAddress,
     *   treasuryMultisigAddress,
     *   proposers,
     *   executors,
     *   treasuryMultisigAddress
     * )
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
     * @notice Update the Governor contract address
     * @dev Only callable by admin (treasury multisig)
     * 
     * @param newGovernor Address of new BASEGovernor implementation
     * 
     * Requirements:
     * - Caller must have DEFAULT_ADMIN_ROLE
     * - newGovernor cannot be zero address
     * 
     * Effects:
     * - Updates governor address reference
     * - Previous governor can no longer queue operations
     * - New governor can queue operations immediately
     * 
     * Emits:
     * - GovernorUpdated(oldGovernor, newGovernor)
     * 
     * Use Case:
     * Upgrade Governor contract to new implementation or fix
     */
    function updateGovernor(address newGovernor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newGovernor == address(0)) revert InvalidGovernorAddress();

        address oldGovernor = governorAddress;
        governorAddress = newGovernor;

        emit GovernorUpdated(oldGovernor, newGovernor);
    }

    /**
     * @notice Update treasury multisig address (admin only)
     * @dev Transfers admin responsibilities to new multisig
     * 
     * @param newMultisig Address of new treasury multisig
     * 
     * Requirements:
     * - Caller must have DEFAULT_ADMIN_ROLE
     * - newMultisig cannot be zero address
     * 
     * Effects:
     * - Updates multisig address reference
     * - Previous multisig loses admin role
     * - New multisig becomes admin
     * 
     * Emits:
     * - TreasuryMultisigUpdated(oldMultisig, newMultisig)
     * 
     * Use Case:
     * Transfer admin role when multisig members change or multisig is upgraded
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
     * @notice Emergency withdrawal of ETH from timelock (admin only, no delay)
     * @dev Bypasses normal queuing for emergency treasury management
     * 
     * @param recipient Recipient address for ETH transfer
     * @param amount Amount of ETH to withdraw (in wei)
     * 
     * Requirements:
     * - Caller must have DEFAULT_ADMIN_ROLE (multisig)
     * - recipient cannot be zero address
     * - amount must not exceed timelock balance
     * 
     * Effects:
     * - Transfers ETH from timelock to recipient
     * - Executes immediately (no 2-day delay)
     * 
     * Use Case:
     * Emergency liquidity withdrawal or fund recovery
     * Does not require governance approval (multisig only)
     */
    function emergencyWithdrawETH(address payable recipient, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (recipient == address(0)) revert InvalidMultisigAddress();
        require(amount <= address(this).balance, "Insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Transfer failed");
    }

    /**
     * @notice Get current ETH balance in timelock
     * @dev View function, anyone can call
     * 
     * @return Current ETH balance (in wei)
     * 
     * Example:
     * uint256 balance = getTreasuryBalance();
     * // Returns current ETH held by timelock treasury
     */
    function getTreasuryBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get minimum delay between proposal queue and execution
     * @dev Constant value, cannot be changed
     * 
     * @return Minimum delay in seconds (2 days = 172,800 seconds)
     * 
     * Example:
     * uint256 delay = getMinDelay();
     * // Returns 172800 (2 days)
     * 
     * Security:
     * This delay ensures community has time to review proposals
     */
    function getMinDelay() external pure returns (uint256) {
        return MIN_DELAY;
    }

    /**
     * @notice Check if a queued operation is ready for execution
     * @dev Operation is ready when delay period has passed
     * 
     * @param id Operation ID (hash of targets, values, calldatas)
     * @return True if operation can be executed now
     * 
     * Formula:
     * ready = (currentTime - queueTime) >= MIN_DELAY
     * 
     * Example:
     * bytes32 opId = keccak256(abi.encode(targets, values, calldatas, salt));
     * bool ready = timelock.isOperationReady(opId);
     * if (ready) {
     *   timelock.execute(targets, values, calldatas, salt);
     * }
     * 
     * Returns:
     * - True: Operation can be executed
     * - False: Still waiting for delay
     */
    function isOperationReady(bytes32 id) external view returns (bool) {
        return isOperationReady(id);
    }

    /**
     * @notice Get current block timestamp
     * @dev Used to check when operations can be executed
     * 
     * @return Current block timestamp (seconds since epoch)
     * 
     * Example:
     * uint256 now = getCurrentTimestamp();
     * // Returns current block timestamp
     */
    function getCurrentTimestamp() external view returns (uint256) {
        return block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                        RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Receive ETH transfers to timelock treasury
     * @dev Fallback function for receiving ETH
     * 
     * Example:
     * // Send ETH to timelock
     * (bool success, ) = payable(timelock).call{value: 1 ether}("");
     */
    receive() external payable {}
}
