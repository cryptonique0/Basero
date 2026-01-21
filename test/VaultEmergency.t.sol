// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenVault} from "../src/RebaseTokenVault.sol";

contract VaultEmergencyTest is Test {
    RebaseToken public token;
    RebaseTokenVault public vault;
    MockERC20 public mockToken;

    address public owner;
    address public alice;

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");

        token = new RebaseToken("Cross-Chain Rebase Token", "CCRT");
        vault = new RebaseTokenVault(address(token));
        token.transferOwnership(address(vault));

        mockToken = new MockERC20();

        vm.deal(alice, 1000 ether);
    }

    // ===== Emergency ETH Withdraw Tests =====

    function testEmergencyWithdrawETH() public {
        vm.deal(address(vault), 10 ether);

        vault.emergencyWithdrawETH(alice, 5 ether);

        assertEq(alice.balance, 5 ether);
    }

    function testEmergencyWithdrawETHAll() public {
        vm.deal(address(vault), 15 ether);

        vault.emergencyWithdrawETH(alice, 0); // 0 means all

        assertEq(alice.balance, 15 ether);
    }

    function testEmergencyWithdrawETHOwnerOnly() public {
        vm.deal(address(vault), 10 ether);

        vm.prank(alice);
        vm.expectRevert();
        vault.emergencyWithdrawETH(alice, 5 ether);
    }

    function testEmergencyWithdrawETHZeroAddress() public {
        vm.deal(address(vault), 10 ether);

        vm.expectRevert(RebaseTokenVault.ZeroAddressNotAllowed.selector);
        vault.emergencyWithdrawETH(address(0), 5 ether);
    }

    function testEmergencyWithdrawETHZeroAmount() public {
        vm.expectRevert(RebaseTokenVault.AmountZero.selector);
        vault.emergencyWithdrawETH(alice, 0);
    }

    function testEmergencyWithdrawETHInsufficientBalance() public {
        vm.deal(address(vault), 5 ether);

        vm.expectRevert(RebaseTokenVault.TransferFailed.selector);
        vault.emergencyWithdrawETH(alice, 10 ether);
    }

    // ===== Sweep ERC20 Tests =====

    function testSweepERC20() public {
        mockToken.mint(address(vault), 100 ether);

        vault.sweepERC20(address(mockToken), alice, 50 ether);

        assertEq(mockToken.balanceOf(alice), 50 ether);
        assertEq(mockToken.balanceOf(address(vault)), 50 ether);
    }

    function testSweepERC20FullAmount() public {
        mockToken.mint(address(vault), 100 ether);

        vault.sweepERC20(address(mockToken), alice, 100 ether);

        assertEq(mockToken.balanceOf(alice), 100 ether);
        assertEq(mockToken.balanceOf(address(vault)), 0);
    }

    function testSweepERC20OwnerOnly() public {
        mockToken.mint(address(vault), 100 ether);

        vm.prank(alice);
        vm.expectRevert();
        vault.sweepERC20(address(mockToken), alice, 50 ether);
    }

    function testSweepERC20CannotSweepRebaseToken() public {
        vm.expectRevert(RebaseTokenVault.TokenNotSweepable.selector);
        vault.sweepERC20(address(token), alice, 1 ether);
    }

    function testSweepERC20ZeroAddress() public {
        mockToken.mint(address(vault), 100 ether);

        vm.expectRevert(RebaseTokenVault.ZeroAddressNotAllowed.selector);
        vault.sweepERC20(address(mockToken), address(0), 50 ether);
    }

    function testSweepERC20ZeroAmount() public {
        mockToken.mint(address(vault), 100 ether);

        vm.expectRevert(RebaseTokenVault.AmountZero.selector);
        vault.sweepERC20(address(mockToken), alice, 0);
    }

    // ===== Reentrancy Guard Tests =====

    function testEmergencyWithdrawHasReentrancyGuard() public {
        vm.deal(address(vault), 10 ether);

        MaliciousReentrancy attacker = new MaliciousReentrancy(address(vault));
        vm.deal(address(attacker), 1 ether);

        vm.expectRevert();
        attacker.attack();
    }

    function testSweepHasReentrancyGuard() public {
        mockToken.mint(address(vault), 100 ether);

        MaliciousReentrancySweep attacker = new MaliciousReentrancySweep(
            address(vault),
            address(mockToken)
        );

        vm.expectRevert();
        attacker.attack();
    }
}

// Mock ERC20 for testing
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

// Malicious reentrancy attacker
contract MaliciousReentrancy {
    RebaseTokenVault public vault;
    uint256 public attacks = 0;

    constructor(address _vault) {
        vault = RebaseTokenVault(_vault);
    }

    function attack() external {
        vault.emergencyWithdrawETH(address(this), 1 ether);
    }

    receive() external payable {
        attacks++;
        if (attacks < 2) {
            vault.emergencyWithdrawETH(address(this), 1 ether);
        }
    }
}

// Malicious reentrancy for sweep
contract MaliciousReentrancySweep {
    RebaseTokenVault public vault;
    MockERC20 public token;
    uint256 public attacks = 0;

    constructor(address _vault, address _token) {
        vault = RebaseTokenVault(_vault);
        token = MockERC20(_token);
    }

    function attack() external {
        vault.sweepERC20(address(token), address(this), 10 ether);
    }

    function onTransfer(address, address, uint256) external {
        attacks++;
        if (attacks < 2) {
            vault.sweepERC20(address(token), address(this), 10 ether);
        }
    }
}
