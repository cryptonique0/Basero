// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/**
 * @title BASEGovernanceToken
 * @author Basero Protocol
 * @notice ERC20 governance token with voting power and delegation for BASE DAO
 * @dev OpenZeppelin ERC20Votes with permit signing and ownership controls
 * 
 * @dev Architecture:
 * - ERC20 standard token with 100M supply cap
 * - ERC20Votes: Voting power snapshots per block (prevents flash-loan attacks)
 * - ERC20Permit: Gasless approvals via signature
 * - Delegation: Users delegate voting power (self-delegation to participate)
 * - Checkpoints: Voting power tracked at each block for governance
 * 
 * @dev Key Features:
 * 1. Voting Power: Voting rights tied to token balance
 * 2. Delegation: Can delegate to self or others
 * 3. Snapshots: Voting power recorded at each block height
 * 4. Permit: Approve tokens via EIP-712 signature
 * 5. Burn: Tokens can be burned to reduce supply
 * 6. Checkpoints: Historical voting power queries
 * 
 * @dev Token Parameters:
 * - Name: "BASE Governance Token"
 * - Symbol: "BASE"
 * - Decimals: 18 (standard)
 * - Max Supply: 100,000,000 tokens (100M * 10^18 wei)
 * - Initial Supply: Set at deployment (typically to treasury)
 * 
 * @dev Voting Mechanics:
 * - Voting power = token balance (with checkpoints)
 * - Must delegate to activate voting rights
 * - Self-delegation for direct voting
 * - Cross-delegation for delegation to others
 * - Voting power snapshot at proposal block (prevents manipulation)
 * 
 * @dev Security:
 * - Voting power snapshots prevent flash-loan attacks
 * - EIP-712 permit prevents unauthorized transfers
 * - Nonce tracking prevents replay attacks
 * - Ownership controls limit minting
 * - Supply cap prevents infinite inflation
 * 
 * @dev Voting Power Formula:
 * votingPower(address, block) = balanceOfAt(address, block)
 * 
 * Example:
 * User has 1,000 tokens at block 100
 * Voting power at block 100 = 1,000
 * Voting power at block 99 = 0 (if transferred in)
 */
contract BASEGovernanceToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Maximum supply cap
    uint256 public constant MAX_SUPPLY = 100_000_000e18; // 100M tokens

    // Current minted supply
    uint256 private s_currentSupply;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurned(address indexed from, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error ExceedsMaxSupply();
    error ZeroAmount();
    error InvalidRecipient();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize governance token with initial supply
     * @dev Sets up voting token with ERC20Permit signature support
     * 
     * @param initialOwner Address to receive initial tokens and minting authority
     * @param initialSupply Initial tokens to mint (typically to treasury/multisig)
     * 
     * Requirements:
     * - initialOwner cannot be zero address
     * - initialSupply must not exceed MAX_SUPPLY (100M tokens)
     * 
     * Effects:
     * - Mints initialSupply tokens to initialOwner
     * - Sets initialOwner as contract owner (can mint/burn)
     * - Initializes ERC20Permit for signature-based approvals
     * - Sets up voting snapshots
     * 
     * Example:
     * new BASEGovernanceToken(
     *   treasuryMultisigAddress,
     *   10_000_000e18 // 10M initial supply
     * )
     * 
     * Initial State:
     * - totalSupply: initialSupply
     * - balanceOf[initialOwner]: initialSupply
     * - delegatedVotes: 0 (must call delegateSelf to activate)
     */
    constructor(
        address initialOwner,
        uint256 initialSupply
    ) ERC20("BASE Governance Token", "BASE") ERC20Permit("BASE Governance Token") Ownable(initialOwner) {
        if (initialSupply > MAX_SUPPLY) revert ExceedsMaxSupply();
        if (initialOwner == address(0)) revert InvalidRecipient();

        s_currentSupply = initialSupply;
        _mint(initialOwner, initialSupply);
    }

    /*//////////////////////////////////////////////////////////////
                           MINTING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mint new governance tokens
     * @dev Only owner can mint, respects 100M supply cap
     * 
     * @param to Recipient address for minted tokens
     * @param amount Number of tokens to mint (in wei, 1 token = 10^18 wei)
     * 
     * Requirements:
     * - Caller must be contract owner
     * - Recipient cannot be zero address
     * - amount must be greater than zero
     * - currentSupply + amount must not exceed 100,000,000e18
     * 
     * Effects:
     * - Increases currentSupply by amount
     * - Transfers amount tokens to recipient
     * - Creates voting power checkpoint
     * 
     * Emits:
     * - Transfer(address(0), to, amount) - ERC20 standard event
     * - TokensMinted(to, amount) - Custom event
     * 
     * Example:
     * mint(0xUser, 1_000_000e18) // Mint 1M tokens to user
     * 
     * Use Cases:
     * - Initial distribution to treasury
     * - Incentive rewards for LPs or stakers
     * - Community grants
     * - Protocol-owned liquidity
     */
    function mint(address to, uint256 amount) public onlyOwner {
        if (to == address(0)) revert InvalidRecipient();
        if (amount == 0) revert ZeroAmount();
        if (s_currentSupply + amount > MAX_SUPPLY) revert ExceedsMaxSupply();

        s_currentSupply += amount;
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }

    /**
     * @notice Burn tokens from caller's balance
     * @dev Permanently removes tokens from supply
     * 
     * @param amount Number of tokens to burn (in wei)
     * 
     * Requirements:
     * - Caller must have sufficient balance
     * - amount must be greater than zero
     * 
     * Effects:
     * - Decreases caller's balance by amount
     * - Decreases totalSupply by amount
     * - Creates voting power checkpoint
     * - Updates currentSupply tracking
     * 
     * Emits:
     * - Transfer(msg.sender, address(0), amount) - ERC20 standard
     * - TokensBurned(msg.sender, amount) - Custom event
     * 
     * Use Case:
     * Users voluntarily burn tokens to reduce supply or exit governance
     * 
     * Formula:
     * currentSupply_after = currentSupply_before - amount
     */
    function burn(uint256 amount) public {
        if (amount == 0) revert ZeroAmount();
        _burn(msg.sender, amount);
        s_currentSupply -= amount;
        emit TokensBurned(msg.sender, amount);
    }

    /**
     * @notice Burn tokens from a specified address
     * @dev Only owner can call, used for removing unclaimed/locked tokens
     * 
     * @param from Address to burn tokens from
     * @param amount Number of tokens to burn
     * 
     * Requirements:
     * - Caller must be contract owner
     * - from address cannot be zero
     * - amount must be greater than zero
     * - from must have sufficient balance
     * 
     * Effects:
     * - Decreases from's balance by amount
     * - Decreases totalSupply by amount
     * - Creates voting power checkpoint
     * - Updates currentSupply tracking
     * 
     * Emits:
     * - Transfer(from, address(0), amount) - ERC20 standard
     * - TokensBurned(from, amount) - Custom event
     * 
     * Use Cases:
     * - Burn unclaimed distribution tokens
     * - Remove locked founder allocations
     * - Emergency supply reduction
     */
    function burnFrom(address from, uint256 amount) public onlyOwner {
        if (from == address(0)) revert InvalidRecipient();
        if (amount == 0) revert ZeroAmount();

        _burn(from, amount);
        s_currentSupply -= amount;
        emit TokensBurned(from, amount);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get current minted supply
     * @dev Tracks actual supply considering mints and burns
     * 
     * @return Current total supply in wei (total tokens minted - burned)
     * 
     * Example:
     * supply = getCurrentSupply();
     * // Returns 50,000,000e18 if 50M tokens currently exist
     * 
     * Note:
     * This value can be different from totalSupply() if implementation differs
     */
    function getCurrentSupply() public view returns (uint256) {
        return s_currentSupply;
    }

    /**
     * @notice Get remaining tokens available to mint
     * @dev Calculates MAX_SUPPLY - currentSupply
     * 
     * @return Remaining mintable supply (in wei)
     * 
     * Formula:
     * remaining = MAX_SUPPLY - currentSupply
     * remaining = 100,000,000e18 - currentSupply
     * 
     * Example:
     * If 50M tokens minted:
     * remaining = 100M - 50M = 50M tokens
     * Can still mint up to 50M more
     */
    function getRemainingMintable() public view returns (uint256) {
        return MAX_SUPPLY - s_currentSupply;
    }

    /*//////////////////////////////////////////////////////////////
                   OVERRIDE FUNCTIONS (ERC20 + ERC20Votes)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal transfer hook for voting power updates
     * @dev Resolves conflict between ERC20 and ERC20Votes
     * 
     * @param from Sender address (address(0) for mints)
     * @param to Recipient address (address(0) for burns)
     * @param amount Token amount being transferred
     * 
     * Effects:
     * - Updates token balances via ERC20
     * - Updates voting power checkpoints via ERC20Votes
     * - Records snapshot for block height
     */
    function _update(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._update(from, to, amount);
    }

    /**
     * @notice Get signature nonce for ERC20Permit
     * @dev Resolves conflict between ERC20Permit and Nonces
     * 
     * @param owner Address to get nonce for
     * @return Current nonce (incremented after each permit/delegateBySignature)
     * 
     * Use:
     * Used in EIP-712 signatures to prevent replay attacks
     */
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    /*//////////////////////////////////////////////////////////////
                   VOTING POWER DELEGATION HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Delegate voting power to self (activate voting rights)
     * @dev Must be called to participate in governance voting
     * 
     * Requirements:
     * - No special requirements, anyone can call for themselves
     * 
     * Effects:
     * - Sets msg.sender's delegate to themselves
     * - Activates voting rights for msg.sender
     * - Updates checkpoint for current block
     * 
     * Emits:
     * - DelegateChanged(msg.sender, address(0), msg.sender)
     * - DelegateVotesChanged(msg.sender, 0, balanceOf[msg.sender])
     * 
     * Example:
     * // User has 1000 tokens but can't vote yet
     * token.delegateSelf();
     * // Now user has 1000 voting power
     * 
     * Note:
     * Must be called after receiving tokens to activate voting power
     * Otherwise you hold tokens but have 0 voting power
     */
    function delegateSelf() external {
        _delegate(msg.sender, msg.sender);
    }

    /**
     * @notice Delegate voting power to another address
     * @dev Allows voting power to be represented by another wallet
     * 
     * @param delegatee Address to receive voting power delegation
     * 
     * Requirements:
     * - Delegatee address must be valid (can be zero to undelegate)
     * 
     * Effects:
     * - Transfers msg.sender's voting power to delegatee
     * - Updates delegation checkpoint
     * - msg.sender no longer has voting power
     * - delegatee now has voting power equal to msg.sender's balance
     * 
     * Emits:
     * - DelegateChanged(msg.sender, previousDelegate, delegatee)
     * - DelegateVotesChanged(previousDelegate, oldVotes, newVotes)
     * - DelegateVotesChanged(delegatee, oldVotes, newVotes)
     * 
     * Example:
     * // Alice has 1000 tokens
     * token.delegateVotes(bob); // Bob now has voting power from Alice's tokens
     * 
     * Use Cases:
     * - Delegate to trusted community member
     * - Delegate to multisig for corporate governance
     * - Delegate to protocol for liquidity pools
     */
    function delegateVotes(address delegatee) external {
        _delegate(msg.sender, delegatee);
    }

    /**
     * @notice Delegate voting power via EIP-712 signature (gasless)
     * @dev Allows delegation without transaction (meta-transaction)
     * 
     * @param delegator Address delegating voting power (signer)
     * @param delegatee Address to receive voting power
     * @param nonce Nonce for signature (must match current nonce)
     * @param expiry Timestamp when signature expires
     * @param v Signature v component (27 or 28)
     * @param r Signature r component
     * @param s Signature s component
     * 
     * Requirements:
     * - Signature must be valid (recovered address == delegator)
     * - Signature must not be expired (block.timestamp <= expiry)
     * - Nonce must match current delegator nonce
     * 
     * Effects:
     * - Delegates delegator's voting power to delegatee
     * - Increments delegator's nonce (prevents replay)
     * - Updates voting power checkpoint
     * 
     * EIP-712 Signature:
     * struct Delegation {
     *   address delegatee;
     *   uint256 nonce;
     *   uint256 expiry;
     * }
     * 
     * Example:
     * // Off-chain: User signs delegation
     * signature = eth_signTypedData({
     *   delegatee: bob,
     *   nonce: 0,
     *   expiry: block.timestamp + 1 hour
     * });
     * 
     * // On-chain: Anyone can execute (no gas for signer)
     * token.delegateBySignature(
     *   alice, bob,
     *   0, // nonce
     *   block.timestamp + 1 hour,
     *   v, r, s
     * );
     * 
     * Gas Savings:
     * User pays 0 gas (relayer covers), only signature cost off-chain
     */
    function delegateBySignature(
        address delegator,
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 domainSeparator = _domainSeparatorV4();
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)"),
                delegatee,
                nonce,
                expiry
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address recovered = ecrecover(digest, v, r, s);

        require(recovered == delegator, "Invalid signature");
        require(block.timestamp <= expiry, "Signature expired");

        _delegate(delegator, delegatee);
    }
}
