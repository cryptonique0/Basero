// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/**
 * @title BASEGovernanceToken
 * @dev ERC20 token with voting power for DAO governance
 * @notice Supports delegation and voting power checkpoints for on-chain voting
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
     * @dev Constructor that initializes the governance token
     * @param initialOwner Address that receives initial supply and ownership
     * @param initialSupply Initial token supply to mint (typically to multisig or treasury)
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
     * @notice Mint new governance tokens (only owner can call)
     * @dev Respects MAX_SUPPLY cap
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
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
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) public {
        if (amount == 0) revert ZeroAmount();
        _burn(msg.sender, amount);
        s_currentSupply -= amount;
        emit TokensBurned(msg.sender, amount);
    }

    /**
     * @notice Burn tokens from a specific address (only owner can call)
     * @dev Used to burn unclaimed or locked tokens
     * @param from Address to burn from
     * @param amount Amount of tokens to burn
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
     * @return Current supply of tokens
     */
    function getCurrentSupply() public view returns (uint256) {
        return s_currentSupply;
    }

    /**
     * @notice Get remaining mintable supply
     * @return Remaining supply available to mint
     */
    function getRemainingMintable() public view returns (uint256) {
        return MAX_SUPPLY - s_currentSupply;
    }

    /*//////////////////////////////////////////////////////////////
                   OVERRIDE FUNCTIONS (ERC20 + ERC20Votes)
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Override for _update to integrate ERC20Votes
     */
    function _update(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._update(from, to, amount);
    }

    /**
     * @dev Override for nonces to integrate ERC20Permit
     */
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    /*//////////////////////////////////////////////////////////////
                   VOTING POWER DELEGATION HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Delegate voting power to self (participate in voting)
     * @dev Must be called to activate voting rights
     */
    function delegateSelf() external {
        _delegate(msg.sender, msg.sender);
    }

    /**
     * @notice Delegate voting power to another address
     * @param delegatee Address to delegate voting power to
     */
    function delegateVotes(address delegatee) external {
        _delegate(msg.sender, delegatee);
    }

    /**
     * @notice Delegate voting power using permit signature
     * @param delegator Address delegating voting power
     * @param delegatee Address to delegate to
     * @param nonce Nonce for signature
     * @param expiry Signature expiry timestamp
     * @param v Signature v component
     * @param r Signature r component
     * @param s Signature s component
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
