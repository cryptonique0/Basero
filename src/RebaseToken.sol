// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RebaseToken
 * @author Basero Protocol
 * @notice A rebase token implementation using shares-based accounting for efficient balance tracking
 * @dev Cross-chain compatible token with per-user interest rates and automatic balance adjustments
 * 
 * @dev The token uses a shares system where:
 * - Users own shares, not tokens directly
 * - Token balance = (userShares * totalSupply) / totalShares
 * - Rebasing changes totalSupply while keeping shares constant
 * - Each user can have a different locked interest rate
 * 
 * @dev This design ensures:
 * - Gas-efficient rebasing (O(1) operation)
 * - No need to update all user balances on rebase
 * - Proportional balance increases for all holders
 * - Cross-chain compatibility via burn/mint mechanics
 * 
 * @dev Security considerations:
 * - Owner has privileged mint/burn capabilities (intended for vault/bridge)
 * - Interest rates are immutable per user once set
 * - Rounding may cause minor precision loss in conversions
 */
contract RebaseToken is ERC20, Ownable {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Total shares representing ownership
    uint256 private s_totalShares;

    // Mapping from account to shares owned
    mapping(address => uint256) private s_shares;

    // Mapping from account to their locked interest rate (in basis points, 10000 = 100%)
    mapping(address => uint256) private s_userInterestRate;

    // Total supply of tokens (can be rebased)
    uint256 private s_totalSupply;

    // Reserved storage space to allow for future upgrades without shifting storage
    uint256[50] private __gap;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event SharesTransferred(address indexed from, address indexed to, uint256 sharesAmount);
    event InterestRateSet(address indexed user, uint256 interestRate);

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the rebase token with name and symbol
     * @dev Sets up the ERC20 token and Ownable with msg.sender as owner
     * @dev Initializes totalSupply and totalShares to 0
     * @param name_ The name of the token (e.g., "Basero Token")
     * @param symbol_ The symbol of the token (e.g., "BASE")
     * 
     * Requirements:
     * - name_ and symbol_ should not be empty strings (inherited from ERC20)
     */
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) Ownable(msg.sender) {
        s_totalSupply = 0;
        s_totalShares = 0;
    }

    /*//////////////////////////////////////////////////////////////
                            REBASE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the total supply of tokens in the protocol
     * @dev Overrides ERC20.totalSupply() to return the rebased total supply
     * @dev This value changes when accrueInterest() is called, but shares remain constant
     * 
     * @return The total supply of tokens (not shares)
     * 
     * Formula:
     * totalSupply = s_totalSupply (can increase via rebasing)
     */
    function totalSupply() public view override returns (uint256) {
        return s_totalSupply;
    }

    /**
     * @notice Get the token balance of an account
     * @dev Calculates balance from shares proportionally to total supply
     * @dev Overrides ERC20.balanceOf() to return share-based balance
     * 
     * @param account The address to query the balance of
     * @return The token balance of the account (not shares)
     * 
     * Formula:
     * balance = (userShares * totalSupply) / totalShares
     * 
     * Special cases:
     * - Returns 0 if totalShares == 0
     * - Balance increases proportionally when totalSupply increases (rebase)
     * 
     * Example:
     * If user has 100 shares, totalShares = 1000, totalSupply = 10000
     * balance = (100 * 10000) / 1000 = 1000 tokens
     */
    function balanceOf(address account) public view override returns (uint256) {
        if (s_totalShares == 0) return 0;
        return (s_shares[account] * s_totalSupply) / s_totalShares;
    }

    /**
     * @notice Get the shares owned by an account
     * @dev Shares are the underlying units that don't change during rebasing
     * @dev Use this to see actual ownership proportion in the protocol
     * 
     * @param account The address to query the shares of
     * @return The number of shares owned by the account
     * 
     * Note:
     * - Shares remain constant during rebases
     * - Ownership percentage = userShares / totalShares
     * - Shares change only on transfer, mint, or burn
     */
    function sharesOf(address account) public view returns (uint256) {
        return s_shares[account];
    }

    /**
     * @notice Get the total shares in the protocol
     * @dev Total shares is the sum of all user shares
     * @dev Unlike totalSupply, this value only changes on mint/burn
     * 
     * @return The total number of shares issued
     * 
     * Invariant:
     * totalShares == sum(sharesOf(user)) for all users
     */
    function getTotalShares() public view returns (uint256) {
        return s_totalShares;
    }

    /**
     * @notice Get the locked interest rate for a user
     * @dev Interest rate is set when tokens are first minted to user
     * @dev Rate is immutable per user (doesn't change after initial set)
     * 
     * @param account The address to query the interest rate for
     * @return The interest rate in basis points (10000 = 100%)
     * 
     * Example:
     * - 500 = 5% interest rate
     * - 1000 = 10% interest rate
     * - 10000 = 100% interest rate
     * 
     * Note: Returns 0 if user has never received tokens
     */
    function getInterestRate(address account) public view returns (uint256) {
        return s_userInterestRate[account];
    }

    /**
     * @notice Convert a token amount to equivalent shares
     * @dev Used internally for transfers and balance calculations
     * @dev Rounding may cause minor precision loss
     * 
     * @param tokenAmount The amount of tokens to convert
     * @return The equivalent number of shares
     * 
     * Formula:
     * shares = (tokenAmount * totalShares) / totalSupply
     * 
     * Special case:
     * - If totalSupply == 0, returns tokenAmount (1:1 ratio for first mint)
     * 
     * Example:
     * If totalSupply = 10000, totalShares = 1000
     * 100 tokens = (100 * 1000) / 10000 = 10 shares
     */
    function getSharesByTokenAmount(uint256 tokenAmount) public view returns (uint256) {
        if (s_totalSupply == 0) return tokenAmount;
        return (tokenAmount * s_totalShares) / s_totalSupply;
    }

    /**
     * @notice Convert shares to equivalent token amount
     * @dev Inverse of getSharesByTokenAmount()
     * @dev Result increases when totalSupply increases (rebase)
     * 
     * @param sharesAmount The amount of shares to convert
     * @return The equivalent number of tokens
     * 
     * Formula:
     * tokens = (sharesAmount * totalSupply) / totalShares
     * 
     * Special case:
     * - Returns 0 if totalShares == 0
     * 
     * Example:
     * If totalSupply = 10000, totalShares = 1000
     * 10 shares = (10 * 10000) / 1000 = 100 tokens
     */
    function getTokenAmountByShares(uint256 sharesAmount) public view returns (uint256) {
        if (s_totalShares == 0) return 0;
        return (sharesAmount * s_totalSupply) / s_totalShares;
    }

    /*//////////////////////////////////////////////////////////////
                           TRANSFER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Transfer tokens to another address
     * @dev Converts token amount to shares and transfers shares
     * @dev Overrides ERC20.transfer() to use shares-based system
     * 
     * @param to The recipient address
     * @param amount The amount of tokens to transfer
     * @return success True if transfer succeeded
     * 
     * Requirements:
     * - `to` cannot be the zero address
     * - Caller must have at least `amount` tokens worth of shares
     * 
     * Emits:
     * - Transfer(from, to, amount) - ERC20 standard event
     * - SharesTransferred(from, to, sharesAmount) - Internal tracking
     * 
     * Note: Due to rounding, transferred token amount might differ by 1 wei
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        address owner = _msgSender();
        uint256 sharesToTransfer = getSharesByTokenAmount(amount);
        _transferShares(owner, to, sharesToTransfer);
        emit Transfer(owner, to, amount);
        return true;
    }

    /**
     * @notice Transfer tokens from one address to another using allowance
     * @dev Checks allowance, converts to shares, and transfers
     * @dev Overrides ERC20.transferFrom() to use shares-based system
     * 
     * @param from The sender address (token owner)
     * @param to The recipient address
     * @param amount The amount of tokens to transfer
     * @return success True if transfer succeeded
     * 
     * Requirements:
     * - `from` and `to` cannot be zero addresses
     * - `from` must have at least `amount` tokens
     * - Caller must have allowance >= `amount`
     * 
     * Emits:
     * - Transfer(from, to, amount)
     * - SharesTransferred(from, to, sharesAmount)
     * - Approval(from, spender, newAllowance) - if allowance changed
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        uint256 sharesToTransfer = getSharesByTokenAmount(amount);
        _transferShares(from, to, sharesToTransfer);
        emit Transfer(from, to, amount);
        return true;
    }

    /**
     * @dev Internal function to transfer shares between accounts
     * @dev This is the core transfer logic operating on shares, not tokens
     * 
     * @param from The sender address
     * @param to The recipient address  
     * @param sharesAmount The amount of shares to transfer
     * 
     * Requirements:
     * - `from` cannot be zero address
     * - `to` cannot be zero address
     * - `from` must have at least `sharesAmount` shares
     * 
     * Emits:
     * - SharesTransferred(from, to, sharesAmount)
     * 
     * Note: This modifies s_shares mapping but not s_totalShares
     */
    function _transferShares(address from, address to, uint256 sharesAmount) internal {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");
        require(s_shares[from] >= sharesAmount, "Transfer amount exceeds balance");

        s_shares[from] -= sharesAmount;
        s_shares[to] += sharesAmount;

        emit SharesTransferred(from, to, sharesAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        MINT AND BURN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mint new tokens to an address with a specific interest rate
     * @dev Converts amount to shares and increases totalSupply and totalShares
     * @dev Can only be called by owner (typically vault or bridge contract)
     * 
     * @param to The recipient address
     * @param amount The amount of tokens to mint
     * @param interestRate The interest rate for this user in basis points (10000 = 100%)
     * 
     * Requirements:
     * - Caller must be owner
     * - `to` cannot be zero address
     * - `amount` must be greater than 0
     * 
     * Effects:
     * - Increases totalSupply by `amount`
     * - Increases totalShares by calculated shares
     * - Sets user interest rate if not already set
     * - Updates user's share balance
     * 
     * Emits:
     * - Transfer(address(0), to, amount)
     * - InterestRateSet(to, interestRate) - if first mint to user
     * 
     * Formula:
     * If totalSupply == 0: shares = amount (1:1 for first mint)
     * Else: shares = (amount * totalShares) / totalSupply
     * 
     * Example:
     * Mint 1000 tokens at 5% interest (500 bps)
     * - Creates shares proportional to existing ratio
     * - Locks in 5% interest rate for this user
     */
    function mint(address to, uint256 amount, uint256 interestRate) external onlyOwner {
        require(to != address(0), "Mint to zero address");
        require(amount > 0, "Amount must be positive");

        uint256 sharesToMint;
        if (s_totalSupply == 0) {
            sharesToMint = amount;
        } else {
            sharesToMint = getSharesByTokenAmount(amount);
        }

        s_totalShares += sharesToMint;
        s_totalSupply += amount;
        s_shares[to] += sharesToMint;

        // Set or update user's interest rate
        if (s_userInterestRate[to] == 0) {
            s_userInterestRate[to] = interestRate;
            emit InterestRateSet(to, interestRate);
        }

        emit Transfer(address(0), to, amount);
    }

    /**
     * @notice Burn tokens from an address
     * @dev Converts amount to shares and decreases totalSupply and totalShares
     * @dev Can only be called by owner (typically vault or bridge contract)
     * 
     * @param from The address to burn tokens from
     * @param amount The amount of tokens to burn
     * 
     * Requirements:
     * - Caller must be owner
     * - `from` cannot be zero address
     * - `amount` must be greater than 0
     * - `from` must have at least `amount` tokens
     * 
     * Effects:
     * - Decreases totalSupply by `amount`
     * - Decreases totalShares by calculated shares
     * - Updates user's share balance
     * 
     * Emits:
     * - Transfer(from, address(0), amount)
     * 
     * Formula:
     * shares = (amount * totalShares) / totalSupply
     * 
     * Example:
     * Burn 500 tokens from user
     * - Removes proportional shares from user
     * - Reduces total supply and total shares
     * - Does not affect other users' balances
     */
    function burn(address from, uint256 amount) external onlyOwner {
        require(from != address(0), "Burn from zero address");
        require(amount > 0, "Amount must be positive");
        require(balanceOf(from) >= amount, "Burn amount exceeds balance");

        uint256 sharesToBurn = getSharesByTokenAmount(amount);
        s_totalShares -= sharesToBurn;
        s_totalSupply -= amount;
        s_shares[from] -= sharesToBurn;

        emit Transfer(from, address(0), amount);
    }

    /*//////////////////////////////////////////////////////////////
                        INTEREST ACCRUAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Apply interest accrual by increasing total supply (rebase)
     * @dev Increases totalSupply without changing totalShares (proportional increase for all)
     * @dev This is the core rebase mechanism - O(1) complexity
     * @dev Can only be called by owner (typically automated keeper or governance)
     * 
     * @param additionalSupply The amount to add to total supply
     * 
     * Requirements:
     * - Caller must be owner
     * 
     * Effects:
     * - Increases totalSupply by `additionalSupply`
     * - All user balances increase proportionally
     * - Individual shares remain unchanged
     * - Share price increases
     * 
     * Formula:
     * newTotalSupply = oldTotalSupply + additionalSupply
     * newUserBalance = (userShares * newTotalSupply) / totalShares
     * 
     * Example:
     * Before: totalSupply = 10000, totalShares = 1000, user has 100 shares
     * User balance = (100 * 10000) / 1000 = 1000 tokens
     * 
     * Accrue 1000 tokens (10% APY):
     * After: totalSupply = 11000, totalShares = 1000 (unchanged)
     * User balance = (100 * 11000) / 1000 = 1100 tokens (10% increase)
     * 
     * Gas: O(1) - No loops, single storage write
     */
    function accrueInterest(uint256 additionalSupply) external onlyOwner {
        s_totalSupply += additionalSupply;
    }

    /**
     * @notice Update a user's interest rate
     * @dev Typically used when tokens are bridged to update rate on destination chain
     * @dev Can only be called by owner (bridge contract)
     * 
     * @param user The user's address
     * @param newRate The new interest rate in basis points (10000 = 100%)
     * 
     * Requirements:
     * - Caller must be owner
     * 
     * Emits:
     * - InterestRateSet(user, newRate)
     * 
     * Use case:
     * - User bridges 1000 tokens with 5% rate from Sepolia to Base
     * - Bridge burns on Sepolia, mints on Base
     * - This function sets the 5% rate on Base to maintain consistency
     * 
     * Warning:
     * - This can override existing rate, use carefully
     * - Intended primarily for cross-chain synchronization
     */
    function setUserInterestRate(address user, uint256 newRate) external onlyOwner {
        s_userInterestRate[user] = newRate;
        emit InterestRateSet(user, newRate);
    }
}
