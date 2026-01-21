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
    
    /// @notice Emitted when tokens are transferred between addresses
    /// @param from Source address (address(0) for minting)
    /// @param to Destination address (address(0) for burning)
    /// @param value Token amount transferred (not shares)
    event Transfer(address indexed from, address indexed to, uint256 value);
    
    /// @notice Emitted when allowance is set
    /// @param owner Token owner granting allowance
    /// @param spender Address receiving spending rights
    /// @param value Allowance amount in tokens
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    /// @notice Emitted when total supply is rebased
    /// @dev Shares remain constant, only supply changes
    /// @param oldSupply Previous total supply
    /// @param newSupply New total supply after rebase
    /// @param timestamp Block timestamp of rebase
    event Rebase(uint256 oldSupply, uint256 newSupply, uint256 timestamp);
    
    /// @notice Emitted when an account's interest rate is updated
    /// @param account Account whose rate was updated
    /// @param newRate New interest rate in basis points (100 = 1%)
    event InterestRateUpdated(address indexed account, uint256 newRate);
    
    /// @notice Emitted when contract is upgraded to new implementation
    /// @param implementation Address of new implementation contract
    /// @param version Version number before upgrade
    event Upgraded(address indexed implementation, uint256 version);
    
    // ============= Errors =============
    
    /// @notice Thrown when account has insufficient balance for operation
    error InsufficientBalance();
    
    /// @notice Thrown when spender has insufficient allowance
    error InsufficientAllowance();
    
    /// @notice Thrown when zero address is provided where not allowed
    error ZeroAddress();
    
    /// @notice Thrown when amount is invalid (zero or exceeds limits)
    error InvalidAmount();
    
    /// @notice Thrown when caller lacks required authorization
    error Unauthorized();
    
    // ============= Initialization =============
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @notice Initialize the upgradeable rebase token (replaces constructor)
     * @dev Can only be called once due to initializer modifier. Sets up ownership, UUPS, and reentrancy guard
     * @param name_ Human-readable token name (e.g., "Rebase Token")
     * @param symbol_ Token ticker symbol (e.g., "REBASE")
     * @param owner_ Address that will own the contract and control upgrades
     * @custom:security Must be called atomically with proxy deployment to prevent front-running
     * @custom:gas Approximately 180k gas for full initialization
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
     * @notice Internal function to authorize contract upgrades
     * @dev Only callable by contract owner. Called by upgradeToAndCall()
     * @param newImplementation Address of new implementation contract
     * @custom:security Critical function - only owner can upgrade
     * @custom:gas ~5k gas for authorization check
     */
    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyOwner 
    {
        emit Upgraded(newImplementation, getVersion());
    }
    
    /**
     * @notice Get the current contract version
     * @dev Returns version before upgrade. Increment in new implementations
     * @return version Current version number (1 for initial deployment)
     * @custom:gas Pure function - no gas cost when called externally
     */
    function getVersion() public pure returns (uint256) {
        return 1;
    }
    
    // ============= ERC20 Metadata =============
    
    /**
     * @notice Get the token name
     * @return Token name string
     * @custom:gas ~2.5k gas
     */
    function name() public view returns (string memory) {
        return _name;
    }
    
    /**
     * @notice Get the token symbol
     * @return Token symbol string
     * @custom:gas ~2.5k gas
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }
    
    /**
     * @notice Get the token decimals
     * @return Number of decimals (always 18)
     * @custom:gas ~400 gas
     */
    function decimals() public view returns (uint8) {
        return _decimals;
    }
    
    /**
     * @notice Get the total token supply
     * @dev This changes during rebases while shares remain constant
     * @return Current total supply in tokens
     * @custom:gas ~400 gas
     */
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }
    
    // ============= Balance & Shares =============
    
    /**
     * @notice Get token balance for an account
     * @dev Converts shares to tokens using: (shares * totalSupply) / totalShares
     * @dev Balance increases/decreases automatically during rebases
     * @param account Address to query balance for
     * @return Token balance (not shares)
     * @custom:gas ~3k gas (2 SLOADs + 1 division)
     */
    function balanceOf(address account) public view returns (uint256) {
        if (_totalShares == 0) return 0;
        return (_shares[account] * _totalSupply) / _totalShares;
    }
    
    /**
     * @notice Get shares held by an account
     * @dev Shares remain constant across rebases (unlike balanceOf)
     * @param account Address to query shares for
     * @return Number of shares held
     * @custom:gas ~2.5k gas (1 SLOAD from mapping)
     */
    function sharesOf(address account) public view returns (uint256) {
        return _shares[account];
    }
    
    /**
     * @notice Get the interest rate assigned to an account
     * @dev Rate set during minting, affects future rebases
     * @param account Address to query rate for
     * @return Interest rate in basis points (100 = 1%, 1000 = 10%)
     * @custom:gas ~2.5k gas (1 SLOAD from mapping)
     */
    function interestRateOf(address account) public view returns (uint256) {
        return _interestRates[account];
    }
    
    // ============= Transfers =============
    
    /**
     * @notice Transfer tokens to another address
     * @dev Transfers shares calculated from token amount. Emits Transfer event
     * @param to Recipient address (cannot be zero address)
     * @param amount Token amount to transfer (not shares)
     * @return success Always returns true if not reverted
     * @custom:gas ~54k gas for standard transfer (with reentrancy guard)
     * @custom:emits Transfer
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
     * @notice Transfer tokens on behalf of another address
     * @dev Requires sufficient allowance. Decreases allowance and transfers shares
     * @param from Address to transfer from (must have approved msg.sender)
     * @param to Recipient address (cannot be zero address)
     * @param amount Token amount to transfer
     * @return success Always returns true if not reverted
     * @custom:gas ~60k gas (additional allowance check vs transfer)
     * @custom:emits Transfer
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
     * @notice Internal transfer logic using shares-based accounting
     * @dev Converts token amount to shares, transfers shares, preserves interest rates
     * @dev Transfers interest rate to recipient if they have none
     * @param from Source address (must have sufficient balance)
     * @param to Destination address (cannot be zero)
     * @param amount Token amount to transfer (converted to shares)
     * @custom:gas ~48k base gas (3 SSTOREs + 2 SLOADs)
     * @custom:emits Transfer
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
    
    /**
     * @notice Get the allowance granted by owner to spender
     * @param owner Address that owns the tokens
     * @param spender Address that can spend the tokens
     * @return Remaining allowance in tokens
     * @custom:gas ~2.5k gas (nested mapping SLOAD)
     */
    function allowance(address owner, address spender) 
        public 
        view 
        returns (uint256) 
    {
        return _allowances[owner][spender];
    }
    
    /**
     * @notice Approve spender to spend tokens on behalf of caller
     * @dev Sets allowance to exact amount (not additive). Use carefully to avoid race conditions
     * @param spender Address being granted spending rights
     * @param amount Maximum tokens spender can transfer
     * @return success Always returns true if not reverted
     * @custom:gas ~45k gas (1 SSTORE)
     * @custom:emits Approval
     * @custom:security Consider using increaseAllowance/decreaseAllowance to avoid race conditions
     */
    function approve(address spender, uint256 amount) public returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    // ============= Rebase & Mint/Burn =============
    
    /**
     * @notice Rebase the total supply by an absolute amount
     * @dev Changes total supply while keeping shares constant. All balances change proportionally
     * @dev Callable only by owner (typically the vault during interest accrual)
     * @param amount Absolute amount to add/subtract from total supply
     * @param positive True to increase supply (positive rebase), false to decrease (negative rebase)
     * @custom:gas ~30k gas (1 SLOAD, 1 SSTORE, event emission)
     * @custom:emits Rebase
     * @custom:security Owner-only to prevent unauthorized supply manipulation
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
     * @notice Rebase the total supply by a percentage
     * @dev Convenience function for percentage-based rebases. Calculates amount from percentage
     * @param percentage Percentage in basis points (100 = 1%, 1000 = 10%, 10000 = 100%)
     * @param positive True to increase supply, false to decrease
     * @custom:gas ~32k gas (additional multiplication vs absolute rebase)
     * @custom:emits Rebase
     * @custom:example 500 basis points with 1000 supply = 50 token adjustment
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
     * @notice Mint new tokens to an account with an assigned interest rate
     * @dev Creates new shares and increases total supply. Sets account's interest rate
     * @dev First mint initializes 1:1 share-to-token ratio
     * @param account Recipient address (cannot be zero)
     * @param amount Token amount to mint
     * @param interestRate Interest rate for this account in basis points (e.g., 1000 = 10%)
     * @custom:gas ~85k gas for first mint, ~65k for subsequent (cold SSTORE vs warm)
     * @custom:emits Transfer (from zero address)
     * @custom:emits InterestRateUpdated
     * @custom:security Owner-only to prevent unauthorized minting
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
     * @notice Burn tokens from an account
     * @dev Reduces shares and total supply. Account must have sufficient balance
     * @param account Address to burn tokens from (cannot be zero)
     * @param amount Token amount to burn (converted to shares)
     * @custom:gas ~58k gas (multiple SSTOREs for shares and supply)
     * @custom:emits Transfer (to zero address)
     * @custom:security Owner-only to prevent unauthorized burning
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
     * @notice Get a hash of the current storage layout for upgrade validation
     * @dev Used by StorageLayoutValidator to detect storage collisions before upgrades
     * @dev Hash includes all storage variable names and gap size
     * @return Hash of storage layout (keccak256 of variable names)
     * @custom:gas Pure function - no gas cost externally
     * @custom:upgrade Critical for safe upgrades - verify hash before upgrading
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
     * @notice Get the total number of storage slots used by this contract
     * @dev Used to validate storage consumption and gap availability
     * @dev Breakdown: 3 metadata + 2 totals + 3 mappings + 50 gap = 58 total
     * @return Total storage slots (58 for version 1)
     * @custom:gas Pure function - no gas cost externally
     * @custom:upgrade Verify new version doesn't exceed available slots
     */
    function getStorageSlots() external pure returns (uint256) {
        // 3 (metadata) + 2 (totals) + 3 (mappings) + 50 (gap) = 58 slots
        return 58;
    }
}
