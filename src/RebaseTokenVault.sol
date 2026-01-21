// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {RebaseToken} from "./RebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RebaseTokenVault
 * @dev Vault contract where users deposit ETH to receive RebaseTokens
 * @notice Interest rates decrease discretely over time and early depositors get higher rates
 */
contract RebaseTokenVault is Ownable {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    RebaseToken public immutable i_rebaseToken;

    // Current interest rate (in basis points, 10000 = 100%)
    // Starts at 10% (1000 basis points) and decreases
    uint256 private s_currentInterestRate;

    // Interest rate decrement per tier
    uint256 private constant INTEREST_RATE_DECREMENT = 100; // 1% decrease per tier

    // Minimum interest rate (2% or 200 basis points)
    uint256 private constant MINIMUM_INTEREST_RATE = 200;

    // Amount of ETH deposited per tier before rate decreases
    uint256 private constant DEPOSIT_TIER_AMOUNT = 10 ether;

    // Total ETH deposited
    uint256 private s_totalEthDeposited;

    // Track how much ETH each user has deposited
    mapping(address => uint256) private s_userEthDeposited;

    // Last time interest was accrued
    uint256 private s_lastAccrualTime;

    // Interest accrual period (1 day)
    uint256 private constant ACCRUAL_PERIOD = 1 days;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(address indexed user, uint256 ethAmount, uint256 tokensReceived, uint256 interestRate);
    event Redeem(address indexed user, uint256 tokenAmount, uint256 ethReceived);
    event InterestAccrued(uint256 interestAmount, uint256 timestamp);
    event InterestRateDecreased(uint256 oldRate, uint256 newRate, uint256 totalDeposited);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InsufficientDeposit();
    error InsufficientBalance();
    error TransferFailed();
    error NoTokensToRedeem();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Constructor
     * @param rebaseToken Address of the RebaseToken contract
     */
    constructor(address rebaseToken) Ownable(msg.sender) {
        i_rebaseToken = RebaseToken(rebaseToken);
        s_currentInterestRate = 1000; // Start at 10%
        s_lastAccrualTime = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT AND REDEEM FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Deposit ETH to receive RebaseTokens
     * @notice Users receive tokens at the current interest rate
     */
    function deposit() external payable {
        if (msg.value == 0) revert InsufficientDeposit();

        // Accrue interest before minting new tokens
        _accrueInterest();

        // Calculate tokens to mint (1:1 ratio with ETH)
        uint256 tokensToMint = msg.value;

        // Get current interest rate for this user
        uint256 userInterestRate = s_currentInterestRate;

        // Mint tokens with the current interest rate
        i_rebaseToken.mint(msg.sender, tokensToMint, userInterestRate);

        // Update user's deposit tracking
        s_userEthDeposited[msg.sender] += msg.value;
        s_totalEthDeposited += msg.value;

        // Check if we need to decrease the interest rate
        _updateInterestRate();

        emit Deposit(msg.sender, msg.value, tokensToMint, userInterestRate);
    }

    /**
     * @dev Redeem RebaseTokens for ETH
     * @param tokenAmount Amount of tokens to redeem
     * @notice Users can only redeem on L1
     */
    function redeem(uint256 tokenAmount) external {
        if (tokenAmount == 0) revert NoTokensToRedeem();

        uint256 userBalance = i_rebaseToken.balanceOf(msg.sender);
        if (userBalance < tokenAmount) revert InsufficientBalance();

        // Accrue interest before burning tokens
        _accrueInterest();

        // Calculate ETH to return (based on shares to maintain fair redemption)
        uint256 userShares = i_rebaseToken.sharesOf(msg.sender);
        uint256 totalShares = i_rebaseToken.getTotalShares();
        uint256 sharesToBurn = i_rebaseToken.getSharesByTokenAmount(tokenAmount);

        // Calculate proportional ETH to return
        uint256 ethToReturn = (s_totalEthDeposited * sharesToBurn) / totalShares;

        // Burn tokens
        i_rebaseToken.burn(msg.sender, tokenAmount);

        // Update total deposited
        s_totalEthDeposited -= ethToReturn;

        // Transfer ETH back to user
        (bool success,) = msg.sender.call{value: ethToReturn}("");
        if (!success) revert TransferFailed();

        emit Redeem(msg.sender, tokenAmount, ethToReturn);
    }

    /*//////////////////////////////////////////////////////////////
                        INTEREST ACCRUAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Accrue interest to all token holders
     * @notice Called automatically on deposit and redeem
     */
    function _accrueInterest() internal {
        uint256 timePassed = block.timestamp - s_lastAccrualTime;

        // Only accrue if at least one period has passed
        if (timePassed >= ACCRUAL_PERIOD) {
            uint256 currentSupply = i_rebaseToken.totalSupply();

            if (currentSupply > 0) {
                // Calculate average interest rate across all holders
                // This is a simplified version - in production you'd track this more precisely
                uint256 periodsElapsed = timePassed / ACCRUAL_PERIOD;
                uint256 interestToAccrue = (currentSupply * s_currentInterestRate * periodsElapsed) / 10_000 / 365;

                if (interestToAccrue > 0) {
                    i_rebaseToken.accrueInterest(interestToAccrue);
                    emit InterestAccrued(interestToAccrue, block.timestamp);
                }
            }

            s_lastAccrualTime = block.timestamp;
        }
    }

    /**
     * @dev Update interest rate based on total deposits
     */
    function _updateInterestRate() internal {
        uint256 currentTier = s_totalEthDeposited / DEPOSIT_TIER_AMOUNT;
        uint256 targetRate = 1000 - (currentTier * INTEREST_RATE_DECREMENT);

        if (targetRate < MINIMUM_INTEREST_RATE) {
            targetRate = MINIMUM_INTEREST_RATE;
        }

        if (targetRate < s_currentInterestRate) {
            uint256 oldRate = s_currentInterestRate;
            s_currentInterestRate = targetRate;
            emit InterestRateDecreased(oldRate, targetRate, s_totalEthDeposited);
        }
    }

    /**
     * @dev Manually trigger interest accrual (public function)
     */
    function accrueInterest() external {
        _accrueInterest();
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Get current interest rate
     */
    function getCurrentInterestRate() external view returns (uint256) {
        return s_currentInterestRate;
    }

    /**
     * @dev Get total ETH deposited in the vault
     */
    function getTotalEthDeposited() external view returns (uint256) {
        return s_totalEthDeposited;
    }

    /**
     * @dev Get user's ETH deposit amount
     */
    function getUserEthDeposited(address user) external view returns (uint256) {
        return s_userEthDeposited[user];
    }

    /**
     * @dev Get time until next interest accrual
     */
    function getTimeUntilNextAccrual() external view returns (uint256) {
        uint256 timePassed = block.timestamp - s_lastAccrualTime;
        if (timePassed >= ACCRUAL_PERIOD) {
            return 0;
        }
        return ACCRUAL_PERIOD - timePassed;
    }

    /**
     * @dev Get user's interest rate
     */
    function getUserInterestRate(address user) external view returns (uint256) {
        return i_rebaseToken.getInterestRate(user);
    }

    /*//////////////////////////////////////////////////////////////
                            RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Allow contract to receive ETH
     */
    receive() external payable {
        // Forward to deposit function
        this.deposit{value: msg.value}();
    }
}
