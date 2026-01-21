// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {CCIPRebaseTokenSender} from "../src/CCIPRebaseTokenSender.sol";
import {CCIPRebaseTokenReceiver} from "../src/CCIPRebaseTokenReceiver.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock Router
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

// Mock LINK Token
contract MockLINK is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }

    function totalSupply() external pure returns (uint256) {
        return 1_000_000 ether;
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

contract CCIPPauseTest is Test {
    RebaseToken public sourceToken;
    RebaseToken public destToken;
    CCIPRebaseTokenSender public sender;
    CCIPRebaseTokenReceiver public receiver;
    MockCCIPRouter public mockRouter;
    MockLINK public mockLink;

    address public owner;
    address public alice;

    uint64 constant SOURCE_CHAIN_SELECTOR = 1;
    uint64 constant DEST_CHAIN_SELECTOR = 2;

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");

        mockRouter = new MockCCIPRouter();
        mockLink = new MockLINK();

        sourceToken = new RebaseToken("Source Token", "SRBT");
        sender = new CCIPRebaseTokenSender(address(mockRouter), address(mockLink), address(sourceToken));

        destToken = new RebaseToken("Dest Token", "DRBT");
        receiver = new CCIPRebaseTokenReceiver(address(mockRouter), address(destToken));

        sourceToken.transferOwnership(address(sender));
        destToken.transferOwnership(address(receiver));

        sender.allowlistDestinationChain(DEST_CHAIN_SELECTOR, true);
        sender.allowlistReceiver(DEST_CHAIN_SELECTOR, address(receiver));

        receiver.allowlistSourceChain(SOURCE_CHAIN_SELECTOR, true);
        receiver.allowlistSender(SOURCE_CHAIN_SELECTOR, address(sender));

        mockLink.mint(address(sender), 100 ether);

        vm.deal(alice, 100 ether);
    }

    function testPauseBridging() public {
        sender.pauseBridging();

        sourceToken.mint(alice, 10 ether, 1000);

        vm.prank(alice);
        vm.expectRevert();
        sender.sendTokensCrossChain(DEST_CHAIN_SELECTOR, alice, 10 ether);
    }

    function testUnpauseBridging() public {
        sender.pauseBridging();
        sender.unpauseBridging();

        sourceToken.mint(alice, 10 ether, 1000);

        vm.prank(alice);
        sender.sendTokensCrossChain(DEST_CHAIN_SELECTOR, alice, 10 ether);
    }

    function testReceiverPauseBridging() public {
        receiver.pauseBridging();

        // Simulate CCIP receive call - will be blocked by pausable
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: SOURCE_CHAIN_SELECTOR,
            sender: abi.encode(address(sender)),
            data: abi.encode(alice, 10 ether, 1000),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.expectRevert();
        receiver.ccipReceive(message);
    }
}
