// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {CCIPRebaseTokenSender} from "../src/CCIPRebaseTokenSender.sol";
import {CCIPRebaseTokenReceiver} from "../src/CCIPRebaseTokenReceiver.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock CCIP Router for testing
contract MockCCIPRouter is IRouterClient {
    uint256 public constant MOCK_FEE = 0.01 ether;

    function getFee(uint64, Client.EVM2AnyMessage memory) external pure returns (uint256) {
        return MOCK_FEE;
    }

    function ccipSend(uint64, Client.EVM2AnyMessage memory) external payable returns (bytes32) {
        return keccak256(abi.encodePacked(block.timestamp, msg.sender));
    }

    function isChainSupported(uint64) external pure returns (bool) {
        return true;
    }

    function getSupportedTokens(uint64) external pure returns (address[] memory) {
        return new address[](0);
    }
}

// Mock LINK Token for testing
contract MockLINK is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }
}

contract CCIPRebaseTokenTest is Test {
    RebaseToken public sourceToken;
    RebaseToken public destToken;
    CCIPRebaseTokenSender public sender;
    CCIPRebaseTokenReceiver public receiver;
    MockCCIPRouter public mockRouter;
    MockLINK public mockLink;

    address public owner;
    address public alice;
    address public bob;

    uint64 constant SOURCE_CHAIN_SELECTOR = 1;
    uint64 constant DEST_CHAIN_SELECTOR = 2;
    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;

    event MessageSent(bytes32 indexed messageId, uint64 indexed destinationChainSelector, address receiver, uint256 amount, uint256 fees);
    event MessageReceived(bytes32 indexed messageId, uint64 indexed sourceChainSelector, address sender, address recipient, uint256 amount);

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy mocks
        mockRouter = new MockCCIPRouter();
        mockLink = new MockLINK();

        // Deploy source chain contracts
        sourceToken = new RebaseToken("Source Rebase Token", "SRBT", INITIAL_SUPPLY);
        sender = new CCIPRebaseTokenSender(
            address(mockRouter),
            address(mockLink),
            address(sourceToken)
        );

        // Deploy destination chain contracts
        destToken = new RebaseToken("Dest Rebase Token", "DRBT", 0);
        receiver = new CCIPRebaseTokenReceiver(
            address(mockRouter),
            address(destToken)
        );

        // Grant permissions
        sourceToken.transferOwnership(address(sender));
        destToken.transferOwnership(address(receiver));

        // Configure sender
        sender.allowlistDestinationChain(DEST_CHAIN_SELECTOR, true);
        sender.allowlistReceiver(DEST_CHAIN_SELECTOR, address(receiver));

        // Configure receiver
        receiver.allowlistSourceChain(SOURCE_CHAIN_SELECTOR, true);
        receiver.allowlistSender(SOURCE_CHAIN_SELECTOR, address(sender));

        // Fund sender with LINK
        mockLink.mint(address(sender), 100 ether);
    }

    function testSenderConfiguration() public view {
        assertTrue(sender.allowlistedDestinationChains(DEST_CHAIN_SELECTOR));
        assertEq(sender.allowlistedReceivers(DEST_CHAIN_SELECTOR), address(receiver));
        assertEq(address(sender.rebaseToken()), address(sourceToken));
    }

    function testReceiverConfiguration() public view {
        assertTrue(receiver.allowlistedSourceChains(SOURCE_CHAIN_SELECTOR));
        assertEq(receiver.allowlistedSenders(SOURCE_CHAIN_SELECTOR), address(sender));
        assertEq(address(receiver.rebaseToken()), address(destToken));
    }

    function testAllowlistDestinationChain() public {
        uint64 newChainSelector = 3;
        
        sender.allowlistDestinationChain(newChainSelector, true);
        assertTrue(sender.allowlistedDestinationChains(newChainSelector));

        sender.allowlistDestinationChain(newChainSelector, false);
        assertFalse(sender.allowlistedDestinationChains(newChainSelector));
    }

    function testAllowlistSourceChain() public {
        uint64 newChainSelector = 3;
        
        receiver.allowlistSourceChain(newChainSelector, true);
        assertTrue(receiver.allowlistedSourceChains(newChainSelector));

        receiver.allowlistSourceChain(newChainSelector, false);
        assertFalse(receiver.allowlistedSourceChains(newChainSelector));
    }

    function testCannotAllowlistInvalidReceiver() public {
        vm.expectRevert(CCIPRebaseTokenSender.InvalidReceiverAddress.selector);
        sender.allowlistReceiver(DEST_CHAIN_SELECTOR, address(0));
    }

    function testCannotAllowlistInvalidSender() public {
        vm.expectRevert(CCIPRebaseTokenReceiver.InvalidSenderAddress.selector);
        receiver.allowlistSender(SOURCE_CHAIN_SELECTOR, address(0));
    }

    function testWithdrawLINK() public {
        uint256 initialBalance = mockLink.balanceOf(address(sender));
        
        sender.withdrawLINK(alice);
        
        assertEq(mockLink.balanceOf(alice), initialBalance);
        assertEq(mockLink.balanceOf(address(sender)), 0);
    }

    function testOnlyOwnerCanAllowlistChains() public {
        vm.prank(alice);
        vm.expectRevert();
        sender.allowlistDestinationChain(3, true);

        vm.prank(alice);
        vm.expectRevert();
        receiver.allowlistSourceChain(3, true);
    }

    function testOnlyOwnerCanWithdrawLINK() public {
        vm.prank(alice);
        vm.expectRevert();
        sender.withdrawLINK(alice);
    }

    function testGetRouter() public view {
        assertEq(sender.getRouter(), address(mockRouter));
        assertEq(receiver.getRouter(), address(mockRouter));
    }
}
