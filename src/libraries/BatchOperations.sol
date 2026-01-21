// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title BatchOperations
 * @notice Gas-optimized batch operation helpers for Basero protocol
 * @dev Reduces transaction overhead by batching multiple operations
 */
library BatchOperations {
    
    /// @notice Batch multiple deposits for different users
    /// @dev Saves gas by amortizing transaction overhead across deposits
    /// @param vault The vault contract
    /// @param amounts Array of deposit amounts
    /// @return Total amount deposited
    function batchDeposit(
        address vault,
        uint256[] calldata amounts
    ) external payable returns (uint256) {
        uint256 totalAmount = 0;
        uint256 length = amounts.length;
        
        for (uint256 i = 0; i < length; ) {
            totalAmount += amounts[i];
            
            // Call deposit for this amount
            (bool success, ) = vault.call{value: amounts[i]}(
                abi.encodeWithSignature("deposit()")
            );
            require(success, "Deposit failed");
            
            unchecked { ++i; }
        }
        
        require(totalAmount == msg.value, "Amount mismatch");
        return totalAmount;
    }
}

/**
 * @title BatchVaultOperations
 * @notice Batch operations contract for RebaseTokenVault
 */
contract BatchVaultOperations {
    
    event BatchDeposit(address indexed user, uint256 count, uint256 totalAmount);
    event BatchWithdrawal(address indexed user, uint256 count, uint256 totalAmount);
    
    /// @notice Deposit on behalf of multiple recipients
    /// @param vault Vault contract address
    /// @param recipients Array of recipient addresses
    /// @param amounts Array of amounts (must match recipients length)
    function batchDepositFor(
        address payable vault,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external payable {
        require(recipients.length == amounts.length, "Length mismatch");
        
        uint256 totalAmount = 0;
        uint256 length = recipients.length;
        
        for (uint256 i = 0; i < length; ) {
            totalAmount += amounts[i];
            
            // Deposit for recipient
            (bool success, ) = vault.call{value: amounts[i]}(
                abi.encodeWithSignature("depositFor(address)", recipients[i])
            );
            require(success, "Deposit failed");
            
            unchecked { ++i; }
        }
        
        require(totalAmount == msg.value, "Amount mismatch");
        emit BatchDeposit(msg.sender, length, totalAmount);
    }
    
    /// @notice Withdraw multiple amounts in one transaction
    /// @param vault Vault contract address
    /// @param amounts Array of withdrawal amounts
    function batchWithdraw(
        address vault,
        uint256[] calldata amounts
    ) external {
        uint256 totalAmount = 0;
        uint256 length = amounts.length;
        
        for (uint256 i = 0; i < length; ) {
            totalAmount += amounts[i];
            
            (bool success, ) = vault.call(
                abi.encodeWithSignature("withdraw(uint256)", amounts[i])
            );
            require(success, "Withdrawal failed");
            
            unchecked { ++i; }
        }
        
        emit BatchWithdrawal(msg.sender, length, totalAmount);
    }
    
    /// @notice Claim interest for multiple users in one transaction
    /// @dev Useful for automated interest distribution
    /// @param vault Vault contract address
    /// @param users Array of user addresses
    function batchClaimInterest(
        address vault,
        address[] calldata users
    ) external {
        uint256 length = users.length;
        
        for (uint256 i = 0; i < length; ) {
            (bool success, ) = vault.call(
                abi.encodeWithSignature("claimInterest(address)", users[i])
            );
            require(success, "Claim failed");
            
            unchecked { ++i; }
        }
    }
}

/**
 * @title BatchTokenOperations
 * @notice Batch operations for token transfers
 */
contract BatchTokenOperations {
    
    event BatchTransfer(address indexed from, uint256 recipientCount, uint256 totalAmount);
    
    /// @notice Transfer tokens to multiple recipients
    /// @param token Token contract address
    /// @param recipients Array of recipient addresses
    /// @param amounts Array of amounts
    /// @dev Gas savings: ~21k base + ~5k per additional recipient vs individual txs
    function batchTransfer(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external {
        require(recipients.length == amounts.length, "Length mismatch");
        
        uint256 totalAmount = 0;
        uint256 length = recipients.length;
        
        for (uint256 i = 0; i < length; ) {
            (bool success, ) = token.call(
                abi.encodeWithSignature("transferFrom(address,address,uint256)", 
                    msg.sender, 
                    recipients[i], 
                    amounts[i]
                )
            );
            require(success, "Transfer failed");
            
            totalAmount += amounts[i];
            unchecked { ++i; }
        }
        
        emit BatchTransfer(msg.sender, length, totalAmount);
    }
    
    /// @notice Approve multiple spenders in one transaction
    /// @param token Token contract address
    /// @param spenders Array of spender addresses
    /// @param amounts Array of approval amounts
    function batchApprove(
        address token,
        address[] calldata spenders,
        uint256[] calldata amounts
    ) external {
        require(spenders.length == amounts.length, "Length mismatch");
        
        uint256 length = spenders.length;
        
        for (uint256 i = 0; i < length; ) {
            (bool success, ) = token.call(
                abi.encodeWithSignature("approve(address,uint256)", 
                    spenders[i], 
                    amounts[i]
                )
            );
            require(success, "Approval failed");
            
            unchecked { ++i; }
        }
    }
}

/**
 * @title BatchGovernanceOperations
 * @notice Batch operations for governance actions
 */
contract BatchGovernanceOperations {
    
    event BatchVote(address indexed voter, uint256 proposalCount);
    event BatchDelegation(address indexed delegator, uint256 count);
    
    /// @notice Vote on multiple proposals in one transaction
    /// @param governor Governor contract address
    /// @param proposalIds Array of proposal IDs
    /// @param support Array of support values (true = for, false = against)
    function batchVote(
        address governor,
        uint256[] calldata proposalIds,
        bool[] calldata support
    ) external {
        require(proposalIds.length == support.length, "Length mismatch");
        
        uint256 length = proposalIds.length;
        
        for (uint256 i = 0; i < length; ) {
            (bool success, ) = governor.call(
                abi.encodeWithSignature("castVote(uint256,bool)", 
                    proposalIds[i], 
                    support[i]
                )
            );
            require(success, "Vote failed");
            
            unchecked { ++i; }
        }
        
        emit BatchVote(msg.sender, length);
    }
    
    /// @notice Create multiple locks in one transaction
    /// @param votingEscrow VotingEscrow contract address
    /// @param amounts Array of lock amounts
    /// @param unlockTimes Array of unlock timestamps
    function batchCreateLocks(
        address votingEscrow,
        uint256[] calldata amounts,
        uint256[] calldata unlockTimes
    ) external {
        require(amounts.length == unlockTimes.length, "Length mismatch");
        
        uint256 length = amounts.length;
        
        for (uint256 i = 0; i < length; ) {
            (bool success, ) = votingEscrow.call(
                abi.encodeWithSignature("createLock(uint256,uint256)", 
                    amounts[i], 
                    unlockTimes[i]
                )
            );
            require(success, "Lock creation failed");
            
            unchecked { ++i; }
        }
    }
}

/**
 * @title BatchBridgeOperations
 * @notice Batch operations for cross-chain bridging
 */
contract BatchBridgeOperations {
    
    event BatchBridge(address indexed sender, uint256 transferCount, uint256 totalAmount);
    
    /// @notice Bridge tokens to multiple recipients on destination chain
    /// @param bridge Bridge contract address
    /// @param destinationChain Destination chain selector
    /// @param recipients Array of recipient addresses
    /// @param amounts Array of amounts
    function batchBridge(
        address bridge,
        uint64 destinationChain,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external {
        require(recipients.length == amounts.length, "Length mismatch");
        
        uint256 totalAmount = 0;
        uint256 length = recipients.length;
        
        for (uint256 i = 0; i < length; ) {
            (bool success, ) = bridge.call(
                abi.encodeWithSignature(
                    "transferToChain(uint64,address,uint256)", 
                    destinationChain,
                    recipients[i], 
                    amounts[i]
                )
            );
            require(success, "Bridge transfer failed");
            
            totalAmount += amounts[i];
            unchecked { ++i; }
        }
        
        emit BatchBridge(msg.sender, length, totalAmount);
    }
    
    /// @notice Execute multiple batch transfers
    /// @param bridge Bridge contract address
    /// @param batchIds Array of batch IDs
    function batchExecute(
        address bridge,
        uint256[] calldata batchIds
    ) external {
        uint256 length = batchIds.length;
        
        for (uint256 i = 0; i < length; ) {
            (bool success, ) = bridge.call(
                abi.encodeWithSignature("executeBatch(uint256)", batchIds[i])
            );
            require(success, "Batch execution failed");
            
            unchecked { ++i; }
        }
    }
}

/**
 * @title MultiCall
 * @notice Generic multicall contract for arbitrary contract calls
 * @dev Based on MakerDAO's Multicall but optimized for gas
 */
contract MultiCall {
    
    struct Call {
        address target;
        bytes callData;
    }
    
    struct Result {
        bool success;
        bytes returnData;
    }
    
    /// @notice Aggregate multiple calls into one transaction
    /// @param calls Array of calls to make
    /// @return blockNumber Current block number
    /// @return results Array of results
    function aggregate(Call[] calldata calls) 
        external 
        returns (uint256 blockNumber, Result[] memory results) 
    {
        blockNumber = block.number;
        uint256 length = calls.length;
        results = new Result[](length);
        
        for (uint256 i = 0; i < length; ) {
            Call calldata call = calls[i];
            
            (bool success, bytes memory returnData) = call.target.call(call.callData);
            results[i] = Result(success, returnData);
            
            unchecked { ++i; }
        }
    }
    
    /// @notice Aggregate calls and require all to succeed
    /// @param calls Array of calls to make
    /// @return blockNumber Current block number
    /// @return results Array of return data
    function aggregateStrict(Call[] calldata calls)
        external
        returns (uint256 blockNumber, bytes[] memory results)
    {
        blockNumber = block.number;
        uint256 length = calls.length;
        results = new bytes[](length);
        
        for (uint256 i = 0; i < length; ) {
            Call calldata call = calls[i];
            
            (bool success, bytes memory returnData) = call.target.call(call.callData);
            require(success, "Call failed");
            
            results[i] = returnData;
            unchecked { ++i; }
        }
    }
    
    /// @notice Try aggregate (don't revert on failure)
    /// @param requireSuccess If true, revert on any failure
    /// @param calls Array of calls to make
    /// @return results Array of results
    function tryAggregate(bool requireSuccess, Call[] calldata calls)
        external
        returns (Result[] memory results)
    {
        uint256 length = calls.length;
        results = new Result[](length);
        
        for (uint256 i = 0; i < length; ) {
            Call calldata call = calls[i];
            
            (bool success, bytes memory returnData) = call.target.call(call.callData);
            
            if (requireSuccess) {
                require(success, "Call failed");
            }
            
            results[i] = Result(success, returnData);
            unchecked { ++i; }
        }
    }
}

/**
 * @title OptimizedBatchDeposit
 * @notice Highly optimized batch deposit using assembly
 * @dev WARNING: Use with caution - assembly code requires careful review
 */
contract OptimizedBatchDeposit {
    
    /// @notice Ultra-optimized batch deposit using assembly
    /// @param vault Vault address
    /// @param amounts Array of amounts
    function batchDepositOptimized(
        address payable vault,
        uint256[] calldata amounts
    ) external payable {
        assembly {
            // Cache calldata length
            let length := amounts.length
            
            // Total amount tracker
            let totalAmount := 0
            
            // Function selector for deposit()
            let selector := 0xd0e30db0 // deposit()
            
            // Loop through amounts
            for { let i := 0 } lt(i, length) { i := add(i, 1) } {
                // Load amount from calldata
                let amount := calldataload(add(amounts.offset, mul(i, 0x20)))
                
                // Add to total
                totalAmount := add(totalAmount, amount)
                
                // Prepare call
                mstore(0x00, selector)
                
                // Call vault.deposit{value: amount}()
                let success := call(
                    gas(),           // Forward all gas
                    vault,           // Target address
                    amount,          // Value to send
                    0x00,            // Input data location
                    0x04,            // Input data size (4 bytes for selector)
                    0x00,            // Output data location
                    0x00             // Output data size
                )
                
                // Revert if call failed
                if iszero(success) {
                    revert(0, 0)
                }
            }
            
            // Check total matches msg.value
            if iszero(eq(totalAmount, callvalue())) {
                revert(0, 0)
            }
        }
    }
}
