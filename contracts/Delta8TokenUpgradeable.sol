// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Delta8GummiesToken
 * @dev ERC-20 Utility Token for Delta-8 Gummies product ecosystem
 *
 * Features:
 * - Utility token providing product access, discounts, and staking rewards
 * - 50% product discount for holders of 100+ tokens (VIP membership)
 * - Staking rewards (15-25% APY) through revenue-share mechanism
 * - Product redemption: Burn tokens to purchase Delta-8 gummies at member pricing
 * - Batch traceability with lab test verification
 * - Oracle integration for dynamic pricing and fair redemption rates
 * - Pausable and burnable for security and redemption purposes
 */
contract Delta8GummiesToken is ERC20, ERC20Burnable, ERC20Pausable, AccessControl, ReentrancyGuard {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant REDEEMER_ROLE = keccak256("REDEEMER_ROLE");

    // Total supply: 10 million tokens for utility and membership ecosystem
    uint256 public constant INITIAL_SUPPLY = 10_000_000 * 10**18;

    // VIP Membership discount threshold (100 tokens minimum)
    uint256 public constant DISCOUNT_THRESHOLD = 100 * 10**18;

    // Maximum batch size limit (1M tokens = 1M grams)
    uint256 public constant MAX_BATCH_SIZE = 1_000_000 * 10**18;

    // Product inventory tracking for redemption pricing
    struct InventoryData {
        uint256 totalWeight;        // Total grams of Delta-8 distillate in inventory
        uint256 lastUpdateTime;     // Last oracle update timestamp
        string batchId;             // Reference to physical batch (e.g., Oregon lab ID)
        string labTestUrl;          // IPFS/URL to lab test results
    }

    InventoryData public inventoryData;
    address public pricingOracle;   // Oracle for dynamic redemption pricing
    address public treasuryAddress; // Treasury address for token recycling (redemptions transfer here)

    // Batch traceability for delta8gummies.com product linkage
    struct ProductBatch {
        string batchId;             // Unique batch identifier
        uint256 distillateWeight;   // Weight in grams
        uint256 tokensIssued;       // Tokens minted for this batch
        uint256 timestamp;          // Batch creation time
        string labTestUrl;          // Lab test results URL
        bool active;                // Whether batch is active
    }

    mapping(string => ProductBatch) public productBatches;
    string[] public batchIds;

    // Staking integration (utility token approach)
    address public stakingContract;         // Staking rewards contract address

    // Events for traceability and compliance
    event InventoryUpdated(
        uint256 newInventoryWeight,
        uint256 timestamp,
        address updatedBy,
        string batchId,
        string labTestUrl
    );
    event TokenRedeemed(
        address indexed redeemer,
        uint256 amount,
        uint256 timestamp,
        string batchId
    );
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);
    event BatchCreated(
        string indexed batchId,
        uint256 hempWeight,
        uint256 tokensIssued,
        string labTestUrl
    );
    event BatchDeactivated(string indexed batchId, uint256 timestamp);
    event StakingContractSet(address indexed stakingContract);
    event TreasuryAddressUpdated(address indexed oldTreasury, address indexed newTreasury);

    /**
     * @dev Constructor mints initial supply to deployer
     * @param _pricingOracle Address of the pricing oracle for dynamic redemption rates
     */
    constructor(address _pricingOracle) ERC20("DELTA8", "DELTA8") {
        require(_pricingOracle != address(0), "Invalid oracle address");

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(ORACLE_ROLE, msg.sender);
        _grantRole(ORACLE_ROLE, _pricingOracle);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(REDEEMER_ROLE, msg.sender);

        pricingOracle = _pricingOracle;

        // Mint initial supply to deployer
        _mint(msg.sender, INITIAL_SUPPLY);

        // Initialize inventory data (starts at 0, updated via oracle or batch creation)
        inventoryData = InventoryData({
            totalWeight: 0, // No physical inventory at genesis
            lastUpdateTime: block.timestamp,
            batchId: "GENESIS",
            labTestUrl: ""
        });

        emit InventoryUpdated(
            0,
            block.timestamp,
            msg.sender,
            "GENESIS",
            ""
        );
    }

    /**
     * @dev Create new product batch and mint tokens
     * @param batchId Unique batch identifier (e.g., "D8G-2024-001")
     * @param distillateWeight Weight in grams of Delta-8 distillate
     * @param labTestUrl URL to lab test results (IPFS or web link)
     */
    function createBatch(
        string memory batchId,
        uint256 distillateWeight,
        string memory labTestUrl
    ) external onlyRole(MINTER_ROLE) {
        require(bytes(batchId).length > 0, "Invalid batch ID");
        require(distillateWeight > 0, "Weight must be positive");
        require(!productBatches[batchId].active, "Batch already exists");

        uint256 tokensToMint = distillateWeight * 10**18; // Tokens minted for batch tracking
        require(tokensToMint <= MAX_BATCH_SIZE, "Batch size exceeds maximum limit");

        // Create batch record
        productBatches[batchId] = ProductBatch({
            batchId: batchId,
            distillateWeight: distillateWeight,
            tokensIssued: tokensToMint,
            timestamp: block.timestamp,
            labTestUrl: labTestUrl,
            active: true
        });

        batchIds.push(batchId);

        // Mint tokens and add to inventory
        _mint(msg.sender, tokensToMint);
        inventoryData.totalWeight += distillateWeight;

        emit BatchCreated(batchId, distillateWeight, tokensToMint, labTestUrl);
    }

    /**
     * @dev Mint tokens for utility distribution (admin only)
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be positive");
        _mint(to, amount);
    }

    /**
     * @dev Redeem tokens for product redemption (purchase Delta-8 gummies at member pricing)
     * @notice Tokens are transferred to treasury for recycling, NOT burned
     * @param amount Amount of tokens to redeem for product
     * @param batchId Batch ID for redemption tracking
     */
    function redeemForPhysical(
        uint256 amount,
        string memory batchId
    ) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        require(treasuryAddress != address(0), "Treasury address not set");

        // Validate inventory availability
        uint256 gramsRedeemed = amount / 10**18;
        require(inventoryData.totalWeight >= gramsRedeemed, "Insufficient inventory for redemption");

        // Transfer tokens to treasury (sustainable circular economy)
        _transfer(msg.sender, treasuryAddress, amount);

        // Update inventory tracking
        inventoryData.totalWeight -= gramsRedeemed;

        emit TokenRedeemed(msg.sender, amount, block.timestamp, batchId);
        emit InventoryUpdated(
            inventoryData.totalWeight,
            block.timestamp,
            msg.sender,
            batchId,
            ""
        );
    }

    /**
     * @dev Authorized redemption (by admin/redeemer role)
     * @notice Tokens are transferred to treasury for recycling, NOT burned
     * @param from Address to redeem from
     * @param amount Amount to redeem
     * @param batchId Batch ID for tracking
     */
    function burnFrom(
        address from,
        uint256 amount,
        string memory batchId
    ) public onlyRole(REDEEMER_ROLE) {
        require(amount > 0, "Amount must be positive");
        require(balanceOf(from) >= amount, "Insufficient balance");
        require(treasuryAddress != address(0), "Treasury address not set");

        // Validate inventory availability
        uint256 gramsRedeemed = amount / 10**18;
        require(inventoryData.totalWeight >= gramsRedeemed, "Insufficient inventory for redemption");

        // Transfer tokens to treasury (sustainable circular economy)
        _transfer(from, treasuryAddress, amount);
        inventoryData.totalWeight -= gramsRedeemed;

        emit TokenRedeemed(from, amount, block.timestamp, batchId);
    }

    /**
     * @dev Update inventory data via oracle (for dynamic pricing and redemption rates)
     * @param newInventoryWeight New total weight in grams
     * @param batchId Reference batch ID
     * @param labTestUrl URL to lab test results
     */
    function updateInventory(
        uint256 newInventoryWeight,
        string memory batchId,
        string memory labTestUrl
    ) external onlyRole(ORACLE_ROLE) {
        // Inventory can be 0 or positive (tracks physical inventory, not token supply)
        // No requirement that inventory >= circulating supply since tokens can be held without redemption

        inventoryData.totalWeight = newInventoryWeight;
        inventoryData.lastUpdateTime = block.timestamp;
        inventoryData.batchId = batchId;
        inventoryData.labTestUrl = labTestUrl;

        emit InventoryUpdated(
            newInventoryWeight,
            block.timestamp,
            msg.sender,
            batchId,
            labTestUrl
        );
    }

    /**
     * @dev Deactivate a product batch (for completed batches)
     * @param batchId Batch ID to deactivate
     */
    function deactivateBatch(string memory batchId) external onlyRole(MINTER_ROLE) {
        require(productBatches[batchId].active, "Batch not active");

        productBatches[batchId].active = false;

        emit BatchDeactivated(batchId, block.timestamp);
    }

    /**
     * @dev Update pricing oracle address (admin only)
     * @param newOracle New oracle address
     */
    function updateOracle(address newOracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newOracle != address(0), "Invalid oracle address");

        address oldOracle = pricingOracle;
        pricingOracle = newOracle;

        // Grant oracle role to new address
        _grantRole(ORACLE_ROLE, newOracle);

        // Revoke from old address if different
        if (oldOracle != newOracle) {
            _revokeRole(ORACLE_ROLE, oldOracle);
        }

        emit OracleUpdated(oldOracle, newOracle);
    }

    /**
     * @dev Get inventory availability ratio (inventory / circulating supply)
     * @return ratio Inventory ratio in basis points (10000 = 100%)
     */
    function getInventoryRatio() external view returns (uint256 ratio) {
        uint256 circulatingSupplyGrams = totalSupply() / 10**18;
        if (circulatingSupplyGrams == 0) return 0;

        ratio = (inventoryData.totalWeight * 10000) / circulatingSupplyGrams;
    }

    /**
     * @dev Set treasury address for token recycling (admin only)
     * @notice Redeemed tokens are transferred to treasury instead of being burned
     * @param _treasuryAddress New treasury address
     */
    function setTreasuryAddress(address _treasuryAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_treasuryAddress != address(0), "Invalid treasury address");
        
        address oldTreasury = treasuryAddress;
        treasuryAddress = _treasuryAddress;
        
        emit TreasuryAddressUpdated(oldTreasury, _treasuryAddress);
    }

    /**
     * @dev Emergency function to recover accidentally sent ERC20 tokens
     * @param tokenAddress Address of the ERC20 token to recover
     * @param amount Amount to recover
     */
    function emergencyWithdrawERC20(
        address tokenAddress,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(tokenAddress != address(this), "Cannot withdraw DELTA8 tokens");
        require(tokenAddress != address(0), "Invalid token address");
        
        IERC20(tokenAddress).transfer(msg.sender, amount);
    }

    /**
     * @dev Get batch information
     * @param batchId Batch ID to query
     */
    function getBatchInfo(string memory batchId)
        external
        view
        returns (
            uint256 distillateWeight,
            uint256 tokensIssued,
            uint256 timestamp,
            string memory labTestUrl,
            bool active
        )
    {
        ProductBatch memory batch = productBatches[batchId];
        return (
            batch.distillateWeight,
            batch.tokensIssued,
            batch.timestamp,
            batch.labTestUrl,
            batch.active
        );
    }

    /**
     * @dev Get total number of batches
     */
    function getBatchCount() external view returns (uint256) {
        return batchIds.length;
    }

    /**
     * @dev Pause token transfers (emergency only)
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause token transfers
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Set the staking contract address for reward distributions
     * @param _stakingContract Address of the staking rewards contract
     *
     * This function links the token to a staking contract where holders can
     * stake their tokens to earn rewards for network participation.
     */
    function setStakingContract(address _stakingContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_stakingContract != address(0), "Invalid staking contract address");
        stakingContract = _stakingContract;
        emit StakingContractSet(_stakingContract);
    }

    /**
     * @dev Check if an address is eligible for the 50% VIP membership discount
     * @param account Address to check eligibility
     * @return eligible True if account holds 100+ tokens, false otherwise
     *
     * This function is called by the delta8gummies.com website at checkout
     * to verify token holder status and automatically apply the 50% discount.
     * The discount applies to all gummy products in the cart.
     */
    function isEligibleForDiscount(address account) external view returns (bool eligible) {
        return balanceOf(account) >= DISCOUNT_THRESHOLD;
    }

    /**
     * @dev Get the exact token balance and discount eligibility for an address
     * @param account Address to check
     * @return balance Token balance (in wei)
     * @return eligible Discount eligibility status
     * @return tokensNeeded Tokens needed to reach discount threshold (0 if eligible)
     */
    function getDiscountStatus(address account)
        external
        view
        returns (
            uint256 balance,
            bool eligible,
            uint256 tokensNeeded
        )
    {
        balance = balanceOf(account);
        eligible = balance >= DISCOUNT_THRESHOLD;
        tokensNeeded = eligible ? 0 : (DISCOUNT_THRESHOLD - balance);
    }

    // Required overrides for multiple inheritance
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }
}
