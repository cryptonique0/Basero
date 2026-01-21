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

    /**
     * @dev Returns the total supply of tokens
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev Returns the balance of an account
     * @param account The address to query
     */
    function balanceOf(address account) public view override returns (uint256) {
        if (_totalShares == 0) return 0;
        return (_shares[account] * _totalSupply) / _totalShares;
    }

    /**
     * @dev Returns the shares of an account
     * @param account The address to query
     */
    function sharesOf(address account) public view returns (uint256) {
        return _shares[account];
    }

    /**
     * @dev Returns the total shares
     */
    function getTotalShares() public view returns (uint256) {
        return _totalShares;
    }

    /**
     * @dev Converts token amount to shares
     * @param tokenAmount Amount of tokens
     */
    function getSharesByTokenAmount(uint256 tokenAmount) public view returns (uint256) {
        if (_totalSupply == 0) return 0;
        return (tokenAmount * _totalShares) / _totalSupply;
    }

    /**
     * @dev Converts shares to token amount
     * @param sharesAmount Amount of shares
     */
    function getTokenAmountByShares(uint256 sharesAmount) public view returns (uint256) {
        if (_totalShares == 0) return 0;
        return (sharesAmount * _totalSupply) / _totalShares;
    }

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
        require(_shares[from] >= sharesAmount, "Transfer amount exceeds balance");

        _shares[from] -= sharesAmount;
        _shares[to] += sharesAmount;

        emit SharesTransferred(from, to, sharesAmount);
    }

    /**
     * @dev Rebase the token supply
     * @param newTotalSupply The new total supply
     * @notice This function adjusts the total supply while keeping shares constant
     */
    function rebase(uint256 newTotalSupply) external onlyOwner {
        require(newTotalSupply > 0, "New supply must be positive");
        uint256 oldTotalSupply = _totalSupply;
        _totalSupply = newTotalSupply;
        emit Rebase(oldTotalSupply, newTotalSupply, block.timestamp);
    }

    /**
     * @dev Rebase by percentage (in basis points, 10000 = 100%)
     * @param basisPoints Percentage in basis points (e.g., 500 = 5% increase)
     * @param isIncrease True for increase, false for decrease
     */
    function rebaseByPercentage(uint256 basisPoints, bool isIncrease) external onlyOwner {
        require(basisPoints > 0, "Basis points must be positive");
        require(basisPoints <= 10_000, "Basis points cannot exceed 100%");

        uint256 oldTotalSupply = _totalSupply;
        uint256 adjustment = (_totalSupply * basisPoints) / 10_000;

        if (isIncrease) {
            _totalSupply += adjustment;
        } else {
            require(_totalSupply > adjustment, "Decrease too large");
            _totalSupply -= adjustment;
        }

        emit Rebase(oldTotalSupply, _totalSupply, block.timestamp);
    }

    /**
     * @dev Mint new tokens (creates new shares)
     * @param to Recipient address
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Mint to zero address");
        require(amount > 0, "Amount must be positive");

        uint256 sharesToMint = getSharesByTokenAmount(amount);
        _totalShares += sharesToMint;
        _totalSupply += amount;
        _shares[to] += sharesToMint;

        emit Transfer(address(0), to, amount);
    }

    /**
     * @dev Burn tokens (destroys shares)
     * @param from Address to burn from
     * @param amount Amount of tokens to burn
     */
    function burn(address from, uint256 amount) external onlyOwner {
        require(from != address(0), "Burn from zero address");
        require(amount > 0, "Amount must be positive");
        require(balanceOf(from) >= amount, "Burn amount exceeds balance");

        uint256 sharesToBurn = getSharesByTokenAmount(amount);
        _totalShares -= sharesToBurn;
        _totalSupply -= amount;
        _shares[from] -= sharesToBurn;

        emit Transfer(from, address(0), amount);
    }
}
