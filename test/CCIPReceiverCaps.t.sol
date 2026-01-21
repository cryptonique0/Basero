// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {CCIPRebaseTokenReceiver} from "../src/CCIPRebaseTokenReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

contract CCIPReceiverCapsTest is Test {
    RebaseToken public destToken;
    CCIPRebaseTokenReceiver public receiver;

    address public owner;
    address public alice;
    address public mockRouter;

    uint64 constant SOURCE_CHAIN_SELECTOR = 1;

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        mockRouter = makeAddr("mockRouter");

        destToken = new RebaseToken("Dest Token", "DRBT");
        receiver = new CCIPRebaseTokenReceiver(mockRouter, address(destToken));

        destToken.transferOwnership(address(receiver));

        receiver.allowlistSourceChain(SOURCE_CHAIN_SELECTOR, true);
        receiver.allowlistSender(SOURCE_CHAIN_SELECTOR, alice);
    }

    // ===== Bridged Cap Tests =====

    function testReceiverBridgedCapEnforced() public {
        receiver.setChainCaps(SOURCE_CHAIN_SELECTOR, 50 ether, type(uint256).max);

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: SOURCE_CHAIN_SELECTOR,
            sender: abi.encode(alice),
            data: abi.encode(alice, 60 ether, 1000),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPRebaseTokenReceiver.BridgeCapExceeded.selector,
                60 ether,
                50 ether
            )
        );
        vm.prank(mockRouter);
        receiver.ccipReceive(message);
    }

    // ===== Daily Receive Limit Tests =====

    function testReceiverDailyLimitEnforced() public {
        receiver.setChainCaps(SOURCE_CHAIN_SELECTOR, type(uint256).max, 100 ether);

        Client.Any2EVMMessage memory message1 = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: SOURCE_CHAIN_SELECTOR,
            sender: abi.encode(alice),
            data: abi.encode(alice, 60 ether, 1000),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(mockRouter);
        receiver.ccipReceive(message1);

        Client.Any2EVMMessage memory message2 = Client.Any2EVMMessage({
            messageId: bytes32(uint256(2)),
            sourceChainSelector: SOURCE_CHAIN_SELECTOR,
            sender: abi.encode(alice),
            data: abi.encode(alice, 60 ether, 1000),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPRebaseTokenReceiver.BridgeDailyLimitExceeded.selector,
                60 ether,
                40 ether
            )
        );
        vm.prank(mockRouter);
        receiver.ccipReceive(message2);
    }

    function testReceiverDailyLimitResets() public {
        receiver.setChainCaps(SOURCE_CHAIN_SELECTOR, type(uint256).max, 100 ether);

        Client.Any2EVMMessage memory message1 = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: SOURCE_CHAIN_SELECTOR,
            sender: abi.encode(alice),
            data: abi.encode(alice, 100 ether, 1000),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(mockRouter);
        receiver.ccipReceive(message1);

        // Move to next day
        vm.warp(block.timestamp + 1 days);

        Client.Any2EVMMessage memory message2 = Client.Any2EVMMessage({
            messageId: bytes32(uint256(2)),
            sourceChainSelector: SOURCE_CHAIN_SELECTOR,
            sender: abi.encode(alice),
            data: abi.encode(alice, 100 ether, 1000),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(mockRouter);
        receiver.ccipReceive(message2);

        assertEq(destToken.balanceOf(alice), 200 ether);
    }

    // ===== Combined Cap Tests =====

    function testReceiverCombinedCaps() public {
        receiver.setChainCaps(SOURCE_CHAIN_SELECTOR, 75 ether, 150 ether);

        // First message hits per-message limit
        Client.Any2EVMMessage memory message1 = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: SOURCE_CHAIN_SELECTOR,
            sender: abi.encode(alice),
            data: abi.encode(alice, 100 ether, 1000),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPRebaseTokenReceiver.BridgeCapExceeded.selector,
                100 ether,
                75 ether
            )
        );
        vm.prank(mockRouter);
        receiver.ccipReceive(message1);

        // Now send within per-message limit
        Client.Any2EVMMessage memory message2 = Client.Any2EVMMessage({
            messageId: bytes32(uint256(2)),
            sourceChainSelector: SOURCE_CHAIN_SELECTOR,
            sender: abi.encode(alice),
            data: abi.encode(alice, 75 ether, 1000),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(mockRouter);
        receiver.ccipReceive(message2);

        // Try to exceed daily limit
        Client.Any2EVMMessage memory message3 = Client.Any2EVMMessage({
            messageId: bytes32(uint256(3)),
            sourceChainSelector: SOURCE_CHAIN_SELECTOR,
            sender: abi.encode(alice),
            data: abi.encode(alice, 76 ether, 1000),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPRebaseTokenReceiver.BridgeDailyLimitExceeded.selector,
                76 ether,
                75 ether
            )
        );
        vm.prank(mockRouter);
        receiver.ccipReceive(message3);
    }
}
