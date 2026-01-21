// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RebaseToken
 * @dev Cross-chain rebase token with interest accrual mechanics
 * @notice This token tracks user shares and applies interest rates that can vary per user
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

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event SharesTransferred(address indexed from, address indexed to, uint256 sharesAmount);
    event InterestRateSet(address indexed user, uint256 interestRate);

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Constructor that initializes the token
     * @param name_ Token name
     * @param symbol_ Token symbol
     */
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) Ownable(msg.sender) {
        s_totalSupply = 0;
        s_totalShares = 0;
    }

    /*//////////////////////////////////////////////////////////////
                            REBASE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns the total supply of tokens
     */
    function totalSupply() public view override returns (uint256) {
        return s_totalSupply;
    }

    /**
     * @dev Returns the balance of an account
     * @param account The address to query
     */
    function balanceOf(address account) public view override returns (uint256) {
        if (s_totalShares == 0) return 0;
        return (s_shares[account] * s_totalSupply) / s_totalShares;
    }

    /**
     * @dev Returns the shares of an account
     * @param account The address to query
     */
    function sharesOf(address account) public view returns (uint256) {
        return s_shares[account];
    }

    /**
     * @dev Returns the total shares
     */
    function getTotalShares() public view returns (uint256) {
        return s_totalShares;
    }

    /**
     * @dev Returns the interest rate for a user
     * @param account The address to query
     */
    function getInterestRate(address account) public view returns (uint256) {
        return s_userInterestRate[account];
    }

    /**
     * @dev Converts token amount to shares
     * @param tokenAmount Amount of tokens
     */
    function getSharesByTokenAmount(uint256 tokenAmount) public view returns (uint256) {
        if (s_totalSupply == 0) return tokenAmount;
        return (tokenAmount * s_totalShares) / s_totalSupply;
    }

    /**
     * @dev Converts shares to token amount
     * @param sharesAmount Amount of shares
     */
    function getTokenAmountByShares(uint256 sharesAmount) public view returns (uint256) {
        if (s_totalShares == 0) return 0;
        return (sharesAmount * s_totalSupply) / s_totalShares;
    }

    /*//////////////////////////////////////////////////////////////
                           TRANSFER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Transfer tokens by transferring shares
     * @param to Recipient address
     * @param amount Amount of tokens to transfer
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        address owner = _msgSender();
        uint256 sharesToTransfer = getSharesByTokenAmount(amount);
        _transferShares(owner, to, sharesToTransfer);
        emit Transfer(owner, to, amount);
        return true;
    }

    /**
     * @dev Transfer tokens from one address to another
     * @param from Sender address
     * @param to Recipient address
     * @param amount Amount of tokens to transfer
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
     * @dev Internal function to transfer shares
     * @param from Sender address
     * @param to Recipient address
     * @param sharesAmount Amount of shares to transfer
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
     * @dev Mint new tokens with specific interest rate
     * @param to Recipient address
     * @param amount Amount of tokens to mint
     * @param interestRate Interest rate for this user (in basis points)
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
     * @dev Burn tokens from an address
     * @param from Address to burn from
     * @param amount Amount of tokens to burn
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
     * @dev Apply interest to the total supply (rebase)
     * @param additionalSupply Amount to add to total supply
     */
    function accrueInterest(uint256 additionalSupply) external onlyOwner {
        s_totalSupply += additionalSupply;
    }

    /**
     * @dev Update a user's interest rate (used when bridging)
     * @param user The user's address
     * @param newRate The new interest rate
     */
    function setUserInterestRate(address user, uint256 newRate) external onlyOwner {
        s_userInterestRate[user] = newRate;
        emit InterestRateSet(user, newRate);
    }
}
