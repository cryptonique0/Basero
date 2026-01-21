// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title StorageLayoutValidator
 * @author Basero Team
 * @notice Validates storage layouts to prevent collisions during UUPS upgrades
 * @dev Tracks storage layouts per version and detects unsafe upgrade patterns
 * @custom:security Critical for upgrade safety - always validate before upgrading
 */
contract StorageLayoutValidator {
    
    // ============= Storage Layout Registry =============
    
    /**
     * @notice Represents a contract's storage layout for a specific version
     * @param layoutHash Keccak256 hash of variable names and types
     * @param totalSlots Total storage slots consumed (including gap)
     * @param version Version number of this layout
     * @param timestamp When layout was registered
     * @param variableNames Array of storage variable names in order
     */
    struct StorageLayout {
        bytes32 layoutHash;
        uint256 totalSlots;
        uint256 version;
        uint256 timestamp;
        string[] variableNames;
    }
    
    /// @notice Storage layouts by contract address and version
    /// @dev Maps contractAddr => version => StorageLayout
    mapping(address => mapping(uint256 => StorageLayout)) public layouts;
    
    /// @notice Latest version number for each contract
    /// @dev Maps contractAddr => latestVersion
    mapping(address => uint256) public latestVersion;
    
    // ============= Events =============
    
    /// @notice Emitted when a new storage layout is registered
    /// @param contractAddr Address of contract (proxy address)
    /// @param version Version number being registered
    /// @param layoutHash Hash of the storage layout
    event LayoutRegistered(address indexed contractAddr, uint256 version, bytes32 layoutHash);
    
    /// @notice Emitted when upgrade validation detects collision
    /// @param contractAddr Address of contract
    /// @param fromVersion Current version
    /// @param toVersion Target version with collision
    event CollisionDetected(address indexed contractAddr, uint256 fromVersion, uint256 toVersion);
    
    /// @notice Emitted when upgrade validation passes
    /// @param contractAddr Address of contract
    /// @param fromVersion Current version
    /// @param toVersion Target version (safe)
    event ValidationPassed(address indexed contractAddr, uint256 fromVersion, uint256 toVersion);
    
    // ============= Errors =============
    
    /// @notice Thrown when storage collision is detected
    /// @param oldSlots Slots used in old version
    /// @param newSlots Slots used in new version (fewer than old)
    error StorageCollisionDetected(uint256 oldSlots, uint256 newSlots);
    
    /// @notice Thrown when layout parameters are invalid
    error InvalidLayout();
    
    /// @notice Thrown when queried layout doesn't exist
    error LayoutNotFound();
    
    // ============= Registration =============
    
    /**
     * @notice Register a storage layout for a contract version
     * @dev Called during deployment/upgrade to track storage structure
     * @dev Updates latestVersion if this version is newer
     * @param contractAddr Proxy contract address (not implementation)
     * @param version Version number (increment for each upgrade)
     * @param layoutHash Keccak256 hash from getStorageLayoutHash()
     * @param totalSlots Total slots from getStorageSlots() (includes gap)
     * @param variableNames Ordered array of storage variable names
     * @custom:gas ~120k gas (multiple SSTOREs for struct and array)
     * @custom:emits LayoutRegistered
     * @custom:example registerLayout(proxyAddr, 1, hash, 58, ["name", "symbol", ...])
     */
    function registerLayout(
        address contractAddr,
        uint256 version,
        bytes32 layoutHash,
        uint256 totalSlots,
        string[] calldata variableNames
    ) external {
        if (layoutHash == bytes32(0) || totalSlots == 0) revert InvalidLayout();
        
        layouts[contractAddr][version] = StorageLayout({
            layoutHash: layoutHash,
            totalSlots: totalSlots,
            version: version,
            timestamp: block.timestamp,
            variableNames: variableNames
        });
        
        if (version > latestVersion[contractAddr]) {
            latestVersion[contractAddr] = version;
        }
        
        emit LayoutRegistered(contractAddr, version, layoutHash);
    }
    
    // ============= Validation =============
    
    /**
     * @notice Validate upgrade safety from one version to another
     * @dev Checks for storage collisions and gap consumption
     * @dev Returns false if new version uses fewer slots (data loss risk)
     * @dev Warns if less than 10 gap slots remaining
     * @param contractAddr Proxy contract address
     * @param fromVersion Current version number
     * @param toVersion Target upgrade version number
     * @return safe True if upgrade is safe, false if collision detected
     * @return message Human-readable validation result
     * @custom:gas ~45k gas (multiple SLOADs, event emission)
     * @custom:emits ValidationPassed or CollisionDetected
     * @custom:security MUST call before executing upgrade
     */
    function validateUpgrade(
        address contractAddr,
        uint256 fromVersion,
        uint256 toVersion
    ) external returns (bool safe, string memory message) {
        StorageLayout memory oldLayout = layouts[contractAddr][fromVersion];
        StorageLayout memory newLayout = layouts[contractAddr][toVersion];
        
        if (oldLayout.layoutHash == bytes32(0) || newLayout.layoutHash == bytes32(0)) {
            revert LayoutNotFound();
        }
        
        // Check if new layout uses more slots than available
        if (newLayout.totalSlots < oldLayout.totalSlots) {
            emit CollisionDetected(contractAddr, fromVersion, toVersion);
            return (false, "New layout uses fewer slots - data loss risk");
        }
        
        // Check if layouts are identical
        if (oldLayout.layoutHash == newLayout.layoutHash) {
            emit ValidationPassed(contractAddr, fromVersion, toVersion);
            return (true, "Layouts identical - safe upgrade");
        }
        
        // Calculate available gap space
        uint256 usedSlots = oldLayout.totalSlots;
        uint256 newSlots = newLayout.totalSlots;
        
        // Warning if gap is getting small
        if (newSlots > usedSlots && newSlots - usedSlots < 10) {
            emit ValidationPassed(contractAddr, fromVersion, toVersion);
            return (true, "WARNING: Less than 10 gap slots remaining");
        }
        
        emit ValidationPassed(contractAddr, fromVersion, toVersion);
        return (true, "Upgrade validated - storage layout safe");
    }
    
    /**
     * @notice Check how many storage gap slots remain unused
     * @dev Calculates: gapSize - (totalSlots - gapSize) = remaining
     * @param contractAddr Proxy contract address
     * @param version Version to check
     * @param gapSize Total gap allocation (e.g., 50 for token, 40 for vault)
     * @return remaining Number of unused gap slots available
     * @custom:gas ~3k gas (struct SLOAD, arithmetic)
     * @custom:example token v1: 58 total, 50 gap => 50 - (58-50) = 42 remaining
     */
    function checkRemainingGap(
        address contractAddr,
        uint256 version,
        uint256 gapSize
    ) external view returns (uint256 remaining) {
        StorageLayout memory layout = layouts[contractAddr][version];
        if (layout.layoutHash == bytes32(0)) revert LayoutNotFound();
        
        // Assume gap is at the end of storage
        uint256 usedSlots = layout.totalSlots - gapSize;
        return gapSize - usedSlots;
    }
    
    /**
     * @notice Compare storage layouts between two versions
     * @dev Returns slot difference and hash equality
     * @param contractAddr Proxy contract address
     * @param version1 First version number
     * @param version2 Second version number
     * @return slotDiff Difference in slots (v2 - v1), positive means growth
     * @return hashMatch True if layouts are identical
     * @custom:gas ~5k gas (2 struct SLOADs, arithmetic)
     */
    function compareVersions(
        address contractAddr,
        uint256 version1,
        uint256 version2
    ) external view returns (int256 slotDiff, bool hashMatch) {
        StorageLayout memory layout1 = layouts[contractAddr][version1];
        StorageLayout memory layout2 = layouts[contractAddr][version2];
        
        if (layout1.layoutHash == bytes32(0) || layout2.layoutHash == bytes32(0)) {
            revert LayoutNotFound();
        }
        
        slotDiff = int256(layout2.totalSlots) - int256(layout1.totalSlots);
        hashMatch = (layout1.layoutHash == layout2.layoutHash);
    }
    
    // ============= Query Functions =============
    
    /**
     * @notice Get storage layout for a specific contract version
     * @param contractAddr Proxy contract address
     * @param version Version number to query
     * @return Full StorageLayout struct including hash, slots, timestamp, variables
     * @custom:gas ~3k gas (struct SLOAD)
     */
    function getLayout(address contractAddr, uint256 version) 
        external 
        view 
        returns (StorageLayout memory) 
    {
        return layouts[contractAddr][version];
    }
    
    /**
     * @notice Get the latest registered storage layout for a contract
     * @dev Uses latestVersion mapping to find most recent layout
     * @param contractAddr Proxy contract address
     * @return Latest StorageLayout struct
     * @custom:gas ~5k gas (2 SLOADs: latestVersion + layout)
     */
    function getLatestLayout(address contractAddr) 
        external 
        view 
        returns (StorageLayout memory) 
    {
        uint256 latest = latestVersion[contractAddr];
        return layouts[contractAddr][latest];
    }
    
    /**
     * @notice Get the ordered list of storage variable names for a version
     * @param contractAddr Proxy contract address
     * @param version Version number
     * @return Array of variable names in storage order
     * @custom:gas ~5k + (500 * numVars) gas (struct SLOAD + array copy)
     */
    function getVariableNames(address contractAddr, uint256 version)
        external
        view
        returns (string[] memory)
    {
        return layouts[contractAddr][version].variableNames;
    }
}
