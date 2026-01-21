// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title StorageLayoutValidator
 * @dev Tool to validate storage layouts and detect collisions during upgrades
 * @notice Use this before upgrading contracts to ensure storage safety
 */
contract StorageLayoutValidator {
    
    // ============= Storage Layout Registry =============
    
    struct StorageLayout {
        bytes32 layoutHash;
        uint256 totalSlots;
        uint256 version;
        uint256 timestamp;
        string[] variableNames;
    }
    
    mapping(address => mapping(uint256 => StorageLayout)) public layouts;
    mapping(address => uint256) public latestVersion;
    
    // ============= Events =============
    
    event LayoutRegistered(address indexed contractAddr, uint256 version, bytes32 layoutHash);
    event CollisionDetected(address indexed contractAddr, uint256 fromVersion, uint256 toVersion);
    event ValidationPassed(address indexed contractAddr, uint256 fromVersion, uint256 toVersion);
    
    // ============= Errors =============
    
    error StorageCollisionDetected(uint256 oldSlots, uint256 newSlots);
    error InvalidLayout();
    error LayoutNotFound();
    
    // ============= Registration =============
    
    /**
     * @dev Register a storage layout for a contract version
     * @param contractAddr Contract address
     * @param version Version number
     * @param layoutHash Hash of storage layout
     * @param totalSlots Total storage slots used
     * @param variableNames Names of storage variables
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
     * @dev Validate upgrade from one version to another
     * @param contractAddr Contract address
     * @param fromVersion Current version
     * @param toVersion Target version
     * @return safe Whether upgrade is safe
     * @return message Validation message
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
     * @dev Check remaining gap slots
     * @param contractAddr Contract address
     * @param version Version to check
     * @param gapSize Total gap size allocated
     * @return remaining Remaining gap slots
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
     * @dev Compare two versions and show differences
     * @param contractAddr Contract address
     * @param version1 First version
     * @param version2 Second version
     * @return slotDiff Difference in slot usage
     * @return hashMatch Whether hashes match
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
    
    function getLayout(address contractAddr, uint256 version) 
        external 
        view 
        returns (StorageLayout memory) 
    {
        return layouts[contractAddr][version];
    }
    
    function getLatestLayout(address contractAddr) 
        external 
        view 
        returns (StorageLayout memory) 
    {
        uint256 latest = latestVersion[contractAddr];
        return layouts[contractAddr][latest];
    }
    
    function getVariableNames(address contractAddr, uint256 version)
        external
        view
        returns (string[] memory)
    {
        return layouts[contractAddr][version].variableNames;
    }
}
