// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {CCIPRebaseTokenSender} from "../src/CCIPRebaseTokenSender.sol";
import {CCIPRebaseTokenReceiver} from "../src/CCIPRebaseTokenReceiver.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Reuse mocks from CCIPPause.t.sol pattern
contract MockCCIPRouter2 is IRouterClient {
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

contract MockLINK2 is IERC20 {
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

contract CCIPFeesAndCapsTest is Test {
    RebaseToken public sourceToken;
    CCIPRebaseTokenSender public sender;
    MockCCIPRouter2 public mockRouter;
    MockLINK2 public mockLink;

    address public owner;
    address public alice;
    address public feeRecipient;

    uint64 constant DEST_CHAIN_SELECTOR = 2;

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        feeRecipient = makeAddr("feeRecipient");

        mockRouter = new MockCCIPRouter2();
        mockLink = new MockLINK2();

        sourceToken = new RebaseToken("Source Token", "SRBT");
        sender = new CCIPRebaseTokenSender(address(mockRouter), address(mockLink), address(sourceToken));

        sourceToken.transferOwnership(address(sender));

        sender.allowlistDestinationChain(DEST_CHAIN_SELECTOR, true);
        sender.allowlistReceiver(DEST_CHAIN_SELECTOR, address(0x1234));
        sender.setFeeRecipient(feeRecipient);

        mockLink.mint(address(sender), 100 ether);

        vm.deal(alice, 100 ether);
    }

    // ===== Per-Chain Fee Tests =====

    function testChainFeeDeductedFromBridgedAmount() public {
        sender.setChainFeeBps(DEST_CHAIN_SELECTOR, 1000); // 10% fee

        sourceToken.mint(alice, 100 ether, 1000);

        vm.prank(alice);
        sender.sendTokensCrossChain(DEST_CHAIN_SELECTOR, alice, 100 ether);

        // Fee recipient should have 10 ether (10% of 100)
        uint256 feeRecipientBalance = sourceToken.balanceOf(feeRecipient);
        assertEq(feeRecipientBalance, 10 ether);
    }

    function testZeroFeeNoDeduction() public {
        sender.setChainFeeBps(DEST_CHAIN_SELECTOR, 0);

        sourceToken.mint(alice, 100 ether, 1000);

        vm.prank(alice);
        sender.sendTokensCrossChain(DEST_CHAIN_SELECTOR, alice, 100 ether);

        uint256 feeRecipientBalance = sourceToken.balanceOf(feeRecipient);
        assertEq(feeRecipientBalance, 0);
    }

    function testFeePercentageVaries() public {
        sourceToken.mint(alice, 1000 ether, 1000);

        // Test 5% fee
        sender.setChainFeeBps(DEST_CHAIN_SELECTOR, 500);
        vm.prank(alice);
        sender.sendTokensCrossChain(DEST_CHAIN_SELECTOR, alice, 100 ether);

        uint256 balance1 = sourceToken.balanceOf(feeRecipient);
        assertEq(balance1, 5 ether);

        // Test 20% fee
        sender.setChainFeeBps(DEST_CHAIN_SELECTOR, 2000);
        vm.prank(alice);
        sender.sendTokensCrossChain(DEST_CHAIN_SELECTOR, alice, 100 ether);

        uint256 balance2 = sourceToken.balanceOf(feeRecipient);
        assertEq(balance2, 5 ether + 20 ether); // Accumulated
    }

    // ===== Per-Send Cap Tests =====

    function testPerSendCapEnforced() public {
        sender.setChainCaps(DEST_CHAIN_SELECTOR, 50 ether, type(uint256).max);

        sourceToken.mint(alice, 100 ether, 1000);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPRebaseTokenSender.SendAmountExceedsCap.selector,
                60 ether,
                50 ether
            )
        );
        sender.sendTokensCrossChain(DEST_CHAIN_SELECTOR, alice, 60 ether);

        vm.prank(alice);
        sender.sendTokensCrossChain(DEST_CHAIN_SELECTOR, alice, 50 ether);
    }

    // ===== Daily Limit Tests =====

    function testDailyLimitEnforced() public {
        sender.setChainCaps(DEST_CHAIN_SELECTOR, type(uint256).max, 100 ether);

        sourceToken.mint(alice, 300 ether, 1000);

        vm.prank(alice);
        sender.sendTokensCrossChain(DEST_CHAIN_SELECTOR, alice, 60 ether);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPRebaseTokenSender.DailyLimitExceeded.selector,
                60 ether,
                40 ether
            )
        );
        sender.sendTokensCrossChain(DEST_CHAIN_SELECTOR, alice, 60 ether);

        vm.prank(alice);
        sender.sendTokensCrossChain(DEST_CHAIN_SELECTOR, alice, 40 ether);

        assertEq(sourceToken.balanceOf(alice), 140 ether);
    }

    function testDailyLimitResets() public {
        sender.setChainCaps(DEST_CHAIN_SELECTOR, type(uint256).max, 100 ether);

        sourceToken.mint(alice, 300 ether, 1000);

        vm.prank(alice);
        sender.sendTokensCrossChain(DEST_CHAIN_SELECTOR, alice, 100 ether);

        // Move to next day
        vm.warp(block.timestamp + 1 days);

        vm.prank(alice);
        sender.sendTokensCrossChain(DEST_CHAIN_SELECTOR, alice, 100 ether);

        assertEq(sourceToken.balanceOf(alice), 100 ether);
    }

    // ===== Combined Fee and Cap Tests =====

    function testFeeAndCapsTogether() public {
        sender.setChainFeeBps(DEST_CHAIN_SELECTOR, 1000); // 10% fee
        sender.setChainCaps(DEST_CHAIN_SELECTOR, 100 ether, 200 ether);

        sourceToken.mint(alice, 400 ether, 1000);

        vm.prank(alice);
        sender.sendTokensCrossChain(DEST_CHAIN_SELECTOR, alice, 100 ether);

        uint256 feeBalance = sourceToken.balanceOf(feeRecipient);
        assertEq(feeBalance, 10 ether);

        vm.prank(alice);
        vm.expectRevert(CCIPRebaseTokenSender.DailyLimitExceeded.selector);
        sender.sendTokensCrossChain(DEST_CHAIN_SELECTOR, alice, 101 ether);
    }

    // ===== Invalid Fee Config Tests =====

    function testInvalidFeeBpsRejected() public {
        vm.expectRevert(CCIPRebaseTokenSender.InvalidFeeBps.selector);
        sender.setChainFeeBps(DEST_CHAIN_SELECTOR, 10001);
    }
}
