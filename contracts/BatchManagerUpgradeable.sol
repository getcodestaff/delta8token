// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// Import interface for PricingManager
interface IPricingManager {
    function calculateRedemptionRate(uint256 manufacturingCost, uint256 productId) external view returns (uint256);
    function calculateRedemptionRateWithMargin(uint256 manufacturingCost, uint256 marginBPS) external view returns (uint256);
    function calculateVIPDiscount(uint256 regularTokens) external pure returns (uint256);
    function getProductInfo(uint256 productId) external view returns (string memory name, uint256 marginBPS);
}

/**
 * @title BatchManagerUpgradeable
 * @dev Manages product batches with dynamic pricing for DELTA8 ecosystem (Upgradeable)
 *
 * Features:
 * - Batch-based product inventory
 * - Dynamic redemption rates based on manufacturing costs
 * - Multi-product support (gummies, distillate, sample packs)
 * - Integration with PricingManager for margin calculations
 * - Batch lifecycle management (active/inactive)
 * - Stock tracking per batch
 * - UPGRADEABLE for future enhancements
 *
 * Batch Flow:
 * 1. Admin creates batch with cost data
 * 2. System calculates redemption rate via PricingManager
 * 3. Customers redeem tokens for products from specific batches
 * 4. Stock depletes until batch is exhausted
 */
contract BatchManagerUpgradeable is 
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    // Reference to pricing manager
    IPricingManager public pricingManager;

    // Batch structure
    struct Batch {
        uint256 batchId;                // Unique batch identifier
        uint256 productId;              // Product type (1=jar, 2=distillate, etc.)
        uint256 manufacturingCost;      // Cost per unit in USD (6 decimals)
        uint256 marginBPS;              // Margin in basis points (10000 = 100%)
        uint256 redemptionRate;         // Tokens required per unit (18 decimals)
        uint256 vipRedemptionRate;      // VIP discounted rate (18 decimals)
        uint256 totalStock;             // Total units in batch
        uint256 remainingStock;         // Remaining units available
        string batchCode;               // Physical batch code/ID
        string labTestUrl;              // IPFS/URL to lab test results
        bool isActive;                  // Whether batch accepts redemptions
        uint256 createdAt;              // Creation timestamp
        uint256 deactivatedAt;          // Deactivation timestamp
    }

    // Storage
    mapping(uint256 => Batch) public batches;
    uint256 public batchCount;

    // Product ID to active batch IDs
    mapping(uint256 => uint256[]) public productBatches;

    // Redemption tracking
    mapping(address => mapping(uint256 => uint256)) public userRedemptions; // user => batchId => quantity
    mapping(uint256 => uint256) public totalRedemptions; // batchId => total redeemed

    // Events
    event BatchCreated(
        uint256 indexed batchId,
        uint256 indexed productId,
        uint256 manufacturingCost,
        uint256 marginBPS,
        uint256 redemptionRate,
        uint256 vipRate,
        uint256 totalStock,
        string batchCode
    );
    event BatchUpdated(
        uint256 indexed batchId,
        uint256 newCost,
        uint256 newMargin,
        uint256 newRedemptionRate,
        uint256 newVipRate
    );
    event BatchDeactivated(uint256 indexed batchId, uint256 timestamp);
    event BatchReactivated(uint256 indexed batchId);
    event StockAdjusted(uint256 indexed batchId, uint256 oldStock, uint256 newStock);
    event ProductRedeemed(
        address indexed user,
        uint256 indexed batchId,
        uint256 quantity,
        uint256 tokensUsed,
        bool isVIP
    );
    event PricingManagerUpdated(address indexed oldManager, address indexed newManager);

    // Storage gap for future upgrades
    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract (replaces constructor)
     * @param _pricingManager Address of PricingManager contract
     */
    function initialize(address _pricingManager) public initializer {
        require(_pricingManager != address(0), "Invalid pricing manager");

        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        pricingManager = IPricingManager(_pricingManager);
    }

    /**
     * @dev Create new product batch
     * @param productId Product type identifier
     * @param manufacturingCost Cost per unit in USD (6 decimals)
     * @param marginBPS Margin in basis points (optional, 0 = use product default)
     * @param totalStock Total units in batch
     * @param batchCode Physical batch code
     * @param labTestUrl Lab test results URL
     * @return batchId Created batch ID
     */
    function createBatch(
        uint256 productId,
        uint256 manufacturingCost,
        uint256 marginBPS,
        uint256 totalStock,
        string memory batchCode,
        string memory labTestUrl
    ) external onlyOwner returns (uint256 batchId) {
        require(manufacturingCost > 0, "Invalid cost");
        require(totalStock > 0, "Invalid stock");
        require(bytes(batchCode).length > 0, "Batch code required");
        require(marginBPS <= 10000, "Margin exceeds 100%");

        batchId = ++batchCount;

        // Calculate redemption rates
        uint256 redemptionRate;
        if (marginBPS > 0) {
            redemptionRate = pricingManager.calculateRedemptionRateWithMargin(
                manufacturingCost,
                marginBPS
            );
        } else {
            redemptionRate = pricingManager.calculateRedemptionRate(
                manufacturingCost,
                productId
            );
            // Get margin from pricing manager
            (, marginBPS) = pricingManager.getProductInfo(productId);
        }

        uint256 vipRate = pricingManager.calculateVIPDiscount(redemptionRate);

        // Create batch
        batches[batchId] = Batch({
            batchId: batchId,
            productId: productId,
            manufacturingCost: manufacturingCost,
            marginBPS: marginBPS,
            redemptionRate: redemptionRate,
            vipRedemptionRate: vipRate,
            totalStock: totalStock,
            remainingStock: totalStock,
            batchCode: batchCode,
            labTestUrl: labTestUrl,
            isActive: true,
            createdAt: block.timestamp,
            deactivatedAt: 0
        });

        // Add to product batches
        productBatches[productId].push(batchId);

        emit BatchCreated(
            batchId,
            productId,
            manufacturingCost,
            marginBPS,
            redemptionRate,
            vipRate,
            totalStock,
            batchCode
        );
    }

    /**
     * @dev Update batch pricing (recalculates redemption rates)
     * @param batchId Batch to update
     * @param newCost New manufacturing cost
     * @param newMargin New margin (0 = keep existing)
     */
    function updateBatchPricing(
        uint256 batchId,
        uint256 newCost,
        uint256 newMargin
    ) external onlyOwner {
        require(batchId > 0 && batchId <= batchCount, "Invalid batch");
        Batch storage batch = batches[batchId];
        require(batch.isActive, "Batch not active");

        if (newCost > 0) {
            batch.manufacturingCost = newCost;
        }

        if (newMargin > 0 && newMargin <= 10000) {
            batch.marginBPS = newMargin;
        }

        // Recalculate redemption rates with current token price
        uint256 newRedemptionRate;
        if (batch.marginBPS > 0) {
            newRedemptionRate = pricingManager.calculateRedemptionRateWithMargin(
                batch.manufacturingCost,
                batch.marginBPS
            );
        } else {
            newRedemptionRate = pricingManager.calculateRedemptionRate(
                batch.manufacturingCost,
                batch.productId
            );
        }

        uint256 newVipRate = pricingManager.calculateVIPDiscount(newRedemptionRate);

        batch.redemptionRate = newRedemptionRate;
        batch.vipRedemptionRate = newVipRate;

        emit BatchUpdated(batchId, newCost, batch.marginBPS, newRedemptionRate, newVipRate);
    }

    /**
     * @dev Deactivate batch
     * @param batchId Batch to deactivate
     */
    function deactivateBatch(uint256 batchId) external onlyOwner {
        require(batchId > 0 && batchId <= batchCount, "Invalid batch");
        Batch storage batch = batches[batchId];
        require(batch.isActive, "Already inactive");

        batch.isActive = false;
        batch.deactivatedAt = block.timestamp;

        emit BatchDeactivated(batchId, block.timestamp);
    }

    /**
     * @dev Reactivate batch
     * @param batchId Batch to reactivate
     */
    function reactivateBatch(uint256 batchId) external onlyOwner {
        require(batchId > 0 && batchId <= batchCount, "Invalid batch");
        Batch storage batch = batches[batchId];
        require(!batch.isActive, "Already active");
        require(batch.remainingStock > 0, "No stock remaining");

        batch.isActive = true;
        batch.deactivatedAt = 0;

        emit BatchReactivated(batchId);
    }

    /**
     * @dev Adjust batch stock
     * @param batchId Batch to update
     * @param newStock New total stock
     */
    function adjustStock(uint256 batchId, uint256 newStock) external onlyOwner {
        require(batchId > 0 && batchId <= batchCount, "Invalid batch");
        Batch storage batch = batches[batchId];

        uint256 redeemed = batch.totalStock - batch.remainingStock;
        require(newStock >= redeemed, "Stock below redeemed amount");

        uint256 oldRemaining = batch.remainingStock;
        batch.totalStock = newStock;
        batch.remainingStock = newStock - redeemed;

        emit StockAdjusted(batchId, oldRemaining, batch.remainingStock);
    }

    /**
     * @dev Record product redemption (called by redemption contract)
     * @param user User redeeming
     * @param batchId Batch to redeem from
     * @param quantity Number of units
     * @param isVIP Whether user has VIP status
     * @return tokensRequired Tokens needed for redemption
     */
    function recordRedemption(
        address user,
        uint256 batchId,
        uint256 quantity,
        bool isVIP
    ) external onlyOwner returns (uint256 tokensRequired) {
        require(batchId > 0 && batchId <= batchCount, "Invalid batch");
        Batch storage batch = batches[batchId];
        require(batch.isActive, "Batch not active");
        require(batch.remainingStock >= quantity, "Insufficient stock");

        // Calculate tokens required
        uint256 ratePerUnit = isVIP ? batch.vipRedemptionRate : batch.redemptionRate;
        tokensRequired = ratePerUnit * quantity;

        // Update stock and tracking
        batch.remainingStock -= quantity;
        userRedemptions[user][batchId] += quantity;
        totalRedemptions[batchId] += quantity;

        // Auto-deactivate if out of stock
        if (batch.remainingStock == 0) {
            batch.isActive = false;
            batch.deactivatedAt = block.timestamp;
            emit BatchDeactivated(batchId, block.timestamp);
        }

        emit ProductRedeemed(user, batchId, quantity, tokensRequired, isVIP);
    }

    /**
     * @dev Get batch redemption rate
     * @param batchId Batch ID
     * @param isVIP Whether to get VIP rate
     * @return rate Redemption rate in tokens (18 decimals)
     */
    function getBatchRedemptionRate(uint256 batchId, bool isVIP) external view returns (uint256 rate) {
        require(batchId > 0 && batchId <= batchCount, "Invalid batch");
        Batch memory batch = batches[batchId];
        rate = isVIP ? batch.vipRedemptionRate : batch.redemptionRate;
    }

    /**
     * @dev Get batch details
     * @param batchId Batch ID
     * @return batch Batch struct
     */
    function getBatch(uint256 batchId) external view returns (Batch memory batch) {
        require(batchId > 0 && batchId <= batchCount, "Invalid batch");
        return batches[batchId];
    }

    /**
     * @dev Get active batches for product
     * @param productId Product type
     * @return activeBatchIds Array of active batch IDs
     */
    function getActiveBatches(uint256 productId) external view returns (uint256[] memory activeBatchIds) {
        uint256[] memory allBatches = productBatches[productId];
        uint256 activeCount = 0;

        // Count active batches
        for (uint256 i = 0; i < allBatches.length; i++) {
            if (batches[allBatches[i]].isActive && batches[allBatches[i]].remainingStock > 0) {
                activeCount++;
            }
        }

        // Create result array
        activeBatchIds = new uint256[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < allBatches.length; i++) {
            uint256 batchId = allBatches[i];
            if (batches[batchId].isActive && batches[batchId].remainingStock > 0) {
                activeBatchIds[index] = batchId;
                index++;
            }
        }
    }

    /**
     * @dev Get user redemption history
     * @param user User address
     * @param batchId Batch ID
     * @return quantity Quantity redeemed
     */
    function getUserRedemptions(address user, uint256 batchId) external view returns (uint256 quantity) {
        return userRedemptions[user][batchId];
    }

    /**
     * @dev Update pricing manager reference
     * @param _newManager New PricingManager address
     */
    function setPricingManager(address _newManager) external onlyOwner {
        require(_newManager != address(0), "Invalid address");
        address oldManager = address(pricingManager);
        pricingManager = IPricingManager(_newManager);

        emit PricingManagerUpdated(oldManager, _newManager);
    }

    /**
     * @dev Get comprehensive batch info with current pricing
     * @param batchId Batch ID
     * @return batchCode Batch code
     * @return productId Product type
     * @return regularRate Regular redemption rate
     * @return vipRate VIP redemption rate
     * @return remainingStock Available stock
     * @return isActive Active status
     */
    function getBatchInfo(uint256 batchId) external view returns (
        string memory batchCode,
        uint256 productId,
        uint256 regularRate,
        uint256 vipRate,
        uint256 remainingStock,
        bool isActive
    ) {
        require(batchId > 0 && batchId <= batchCount, "Invalid batch");
        Batch memory batch = batches[batchId];

        return (
            batch.batchCode,
            batch.productId,
            batch.redemptionRate,
            batch.vipRedemptionRate,
            batch.remainingStock,
            batch.isActive
        );
    }

    /**
     * @dev Recalculate all active batch rates (after token price update)
     * @param startBatch Start batch ID
     * @param endBatch End batch ID
     */
    function recalculateBatchRates(uint256 startBatch, uint256 endBatch) external onlyOwner {
        require(startBatch > 0 && startBatch <= batchCount, "Invalid start");
        require(endBatch <= batchCount && endBatch >= startBatch, "Invalid end");

        for (uint256 i = startBatch; i <= endBatch; i++) {
            Batch storage batch = batches[i];
            if (batch.isActive) {
                // Recalculate with current token price
                uint256 newRate;
                if (batch.marginBPS > 0) {
                    newRate = pricingManager.calculateRedemptionRateWithMargin(
                        batch.manufacturingCost,
                        batch.marginBPS
                    );
                } else {
                    newRate = pricingManager.calculateRedemptionRate(
                        batch.manufacturingCost,
                        batch.productId
                    );
                }

                uint256 newVipRate = pricingManager.calculateVIPDiscount(newRate);

                batch.redemptionRate = newRate;
                batch.vipRedemptionRate = newVipRate;

                emit BatchUpdated(i, batch.manufacturingCost, batch.marginBPS, newRate, newVipRate);
            }
        }
    }
}

