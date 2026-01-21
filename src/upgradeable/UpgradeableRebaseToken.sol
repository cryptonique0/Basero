// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title UpgradeableRebaseToken
 * @dev UUPS upgradeable rebase token with individual interest rate tracking
 * @notice Implements shares-based accounting with upgrade safety via storage gaps
 */
contract UpgradeableRebaseToken is 
    Initializable, 
    UUPSUpgradeable, 
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable 
{
    // ============= Storage Layout V1 =============
    
    string private _name;
    string private _symbol;
    uint8 private _decimals;
    
    uint256 private _totalShares;
    uint256 private _totalSupply;
    
    mapping(address => uint256) private _shares;
    mapping(address => uint256) private _interestRates;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    // ============= Storage Gap (50 slots) =============
    // Reserve storage slots for future upgrades
    // This prevents storage collisions when adding new variables
    uint256[50] private __gap;
    
    // ============= Events =============
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Rebase(uint256 oldSupply, uint256 newSupply, uint256 timestamp);
    event InterestRateUpdated(address indexed account, uint256 newRate);
    event Upgraded(address indexed implementation, uint256 version);
    
    // ============= Errors =============
    
    error InsufficientBalance();
    error InsufficientAllowance();
    error ZeroAddress();
    error InvalidAmount();
    error Unauthorized();
    
    // ============= Initialization =============
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @dev Initialize the upgradeable token
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param owner_ Initial owner address
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        address owner_
    ) public initializer {
        if (owner_ == address(0)) revert ZeroAddress();
        
        __Ownable_init(owner_);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        
        _name = name_;
        _symbol = symbol_;
        _decimals = 18;
        _totalSupply = 0;
        _totalShares = 0;
    }
    
    // ============= Upgrade Authorization =============
    
    /**
     * @dev Authorize upgrade (only owner can upgrade)
     * @param newImplementation Address of new implementation
     */
    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyOwner 
    {
        emit Upgraded(newImplementation, getVersion());
    }
    
    /**
     * @dev Get current contract version
     * @return version Version number
     */
    function getVersion() public pure returns (uint256) {
        return 1;
    }
    
    // ============= ERC20 Metadata =============
    
    function name() public view returns (string memory) {
        return _name;
    }
    
    function symbol() public view returns (string memory) {
        return _symbol;
    }
    
    function decimals() public view returns (uint8) {
        return _decimals;
    }
    
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }
    
    // ============= Balance & Shares =============
    
    /**
     * @dev Get token balance (shares to tokens conversion)
     * @param account Account address
     * @return Token balance
     */
    function balanceOf(address account) public view returns (uint256) {
        if (_totalShares == 0) return 0;
        return (_shares[account] * _totalSupply) / _totalShares;
    }
    
    /**
     * @dev Get shares held by account
     * @param account Account address
     * @return Shares balance
     */
    function sharesOf(address account) public view returns (uint256) {
        return _shares[account];
    }
    
    /**
     * @dev Get interest rate for account
     * @param account Account address
     * @return Interest rate in basis points
     */
    function interestRateOf(address account) public view returns (uint256) {
        return _interestRates[account];
    }
    
    // ============= Transfers =============
    
    /**
     * @dev Transfer tokens
     * @param to Recipient address
     * @param amount Token amount
     */
    function transfer(address to, uint256 amount) 
        public 
        nonReentrant 
        returns (bool) 
    {
        _transfer(msg.sender, to, amount);
        return true;
    }
    
    /**
     * @dev Transfer tokens from
     * @param from Sender address
     * @param to Recipient address
     * @param amount Token amount
     */
    function transferFrom(address from, address to, uint256 amount)
        public
        nonReentrant
        returns (bool)
    {
        uint256 currentAllowance = _allowances[from][msg.sender];
        if (currentAllowance < amount) revert InsufficientAllowance();
        
        _allowances[from][msg.sender] = currentAllowance - amount;
        _transfer(from, to, amount);
        
        return true;
    }
    
    /**
     * @dev Internal transfer (shares-based)
     * @param from Sender
     * @param to Recipient
     * @param amount Token amount
     */
    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        
        uint256 sharesToTransfer = (_totalShares * amount) / _totalSupply;
        
        if (_shares[from] < sharesToTransfer) revert InsufficientBalance();
        
        _shares[from] -= sharesToTransfer;
        _shares[to] += sharesToTransfer;
        
        // Transfer interest rate to recipient if they don't have one
        if (_interestRates[to] == 0 && _interestRates[from] > 0) {
            _interestRates[to] = _interestRates[from];
        }
        
        emit Transfer(from, to, amount);
    }
    
    // ============= Allowances =============
    
    function allowance(address owner, address spender) 
        public 
        view 
        returns (uint256) 
    {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) public returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    // ============= Rebase & Mint/Burn =============
    
    /**
     * @dev Rebase by absolute amount
     * @param amount Amount to add/subtract
     * @param positive True to increase supply
     */
    function rebase(uint256 amount, bool positive) external onlyOwner {
        uint256 oldSupply = _totalSupply;
        
        if (positive) {
            _totalSupply += amount;
        } else {
            if (_totalSupply < amount) revert InvalidAmount();
            _totalSupply -= amount;
        }
        
        emit Rebase(oldSupply, _totalSupply, block.timestamp);
    }
    
    /**
     * @dev Rebase by percentage (in basis points)
     * @param percentage Percentage in basis points (100 = 1%)
     * @param positive True to increase supply
     */
    function rebaseByPercentage(uint256 percentage, bool positive) 
        external 
        onlyOwner 
    {
        uint256 oldSupply = _totalSupply;
        uint256 adjustment = (_totalSupply * percentage) / 10000;
        
        if (positive) {
            _totalSupply += adjustment;
        } else {
            if (_totalSupply < adjustment) revert InvalidAmount();
            _totalSupply -= adjustment;
        }
        
        emit Rebase(oldSupply, _totalSupply, block.timestamp);
    }
    
    /**
     * @dev Mint tokens with interest rate
     * @param account Recipient
     * @param amount Token amount
     * @param interestRate Interest rate in basis points
     */
    function mint(address account, uint256 amount, uint256 interestRate) 
        external 
        onlyOwner 
        nonReentrant 
    {
        if (account == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        
        uint256 sharesToMint;
        if (_totalSupply == 0) {
            sharesToMint = amount;
            _totalShares = amount;
        } else {
            sharesToMint = (_totalShares * amount) / _totalSupply;
            _totalShares += sharesToMint;
        }
        
        _totalSupply += amount;
        _shares[account] += sharesToMint;
        _interestRates[account] = interestRate;
        
        emit Transfer(address(0), account, amount);
        emit InterestRateUpdated(account, interestRate);
    }
    
    /**
     * @dev Burn tokens
     * @param account Account to burn from
     * @param amount Token amount
     */
    function burn(address account, uint256 amount) 
        external 
        onlyOwner 
        nonReentrant 
    {
        if (account == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        
        uint256 sharesToBurn = (_totalShares * amount) / _totalSupply;
        
        if (_shares[account] < sharesToBurn) revert InsufficientBalance();
        
        _shares[account] -= sharesToBurn;
        _totalShares -= sharesToBurn;
        _totalSupply -= amount;
        
        emit Transfer(account, address(0), amount);
    }
    
    // ============= Storage Validation =============
    
    /**
     * @dev Validate storage layout (for upgrade safety)
     * @return Layout hash for comparison
     */
    function getStorageLayoutHash() external pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            "v1",
            "name", "symbol", "decimals",
            "totalShares", "totalSupply",
            "shares", "interestRates", "allowances",
            "gap[50]"
        ));
    }
    
    /**
     * @dev Get total storage slots used
     * @return Number of storage slots
     */
    function getStorageSlots() external pure returns (uint256) {
        // 3 (metadata) + 2 (totals) + 3 (mappings) + 50 (gap) = 58 slots
        return 58;
    }
}
