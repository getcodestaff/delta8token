// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title PricingManagerUpgradeable
 * @dev Central pricing contract for DELTA8 token ecosystem (Upgradeable)
 *
 * Handles:
 * - Token price tracking (manual or oracle-based)
 * - Product redemption rate calculations
 * - Margin management for different product types
 * - VIP discount calculations (50% off)
 *
 * Key Features:
 * - Manufacturing cost-based pricing
 * - Configurable margins per product type
 * - Oracle integration ready
 * - VIP discount logic (50% off regular price)
 * - UPGRADEABLE for future enhancements
 *
 * Note: VIP status is now managed by VIPMembership.sol (100 tokens/year membership)
 */
contract PricingManagerUpgradeable is 
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    // Constants
    uint256 public constant USDC_DECIMALS = 6;
    uint256 public constant TOKEN_DECIMALS = 18;
    uint256 public constant BPS_DENOMINATOR = 10000; // For basis points (100% = 10000 BPS)

    // Price limits (6 decimals - USDC format)
    uint256 public constant MIN_TOKEN_PRICE = 100000;   // $0.10 minimum
    uint256 public constant MAX_TOKEN_PRICE = 10000000; // $10.00 maximum

    // Current token price (USDC per token, 6 decimals)
    // Example: 500000 = $0.50 per token
    uint256 public currentTokenPrice;

    // Last price update timestamp
    uint256 public lastPriceUpdate;

    // Oracle address (for future automation)
    address public priceOracle;

    // Product type margins (in basis points, 10000 = 100%)
    // Example: 4000 = 40% margin
    mapping(uint256 => uint256) public productMargins;

    // Product type names for tracking
    mapping(uint256 => string) public productNames;
    uint256 public productTypeCount;

    // Events
    event TokenPriceUpdated(uint256 oldPrice, uint256 newPrice, address updatedBy);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);
    event ProductMarginUpdated(uint256 indexed productId, uint256 oldMargin, uint256 newMargin);
    event ProductTypeAdded(uint256 indexed productId, string name, uint256 margin);

    // Storage gap for future upgrades
    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract (replaces constructor)
     * @param _initialPrice Initial token price in USDC (6 decimals)
     */
    function initialize(uint256 _initialPrice) public initializer {
        require(_initialPrice >= MIN_TOKEN_PRICE, "Price below minimum");
        require(_initialPrice <= MAX_TOKEN_PRICE, "Price above maximum");

        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        currentTokenPrice = _initialPrice;
        lastPriceUpdate = block.timestamp;

        // Initialize default product types
        _addProductType(1, "Gummy Jar", 4000);      // 40% margin
        _addProductType(2, "Distillate 1kg", 3000); // 30% margin
        _addProductType(3, "Sample Pack", 5000);    // 50% margin

        emit TokenPriceUpdated(0, _initialPrice, msg.sender);
    }

    /**
     * @dev Add new product type
     * @param productId Product identifier
     * @param name Product name
     * @param marginBPS Margin in basis points
     */
    function _addProductType(uint256 productId, string memory name, uint256 marginBPS) internal {
        require(bytes(productNames[productId]).length == 0, "Product ID exists");
        require(marginBPS <= 10000, "Margin exceeds 100%");

        productNames[productId] = name;
        productMargins[productId] = marginBPS;
        productTypeCount++;

        emit ProductTypeAdded(productId, name, marginBPS);
    }

    /**
     * @dev Add new product type (admin only)
     * @param productId Product identifier
     * @param name Product name
     * @param marginBPS Margin in basis points
     */
    function addProductType(uint256 productId, string memory name, uint256 marginBPS) external onlyOwner {
        _addProductType(productId, name, marginBPS);
    }

    /**
     * @dev Calculate redemption rate for a product
     * @param manufacturingCost Manufacturing cost in USD (6 decimals)
     * @param productId Product type identifier
     * @return tokensRequired Number of tokens required for redemption (18 decimals)
     *
     * Formula: (manufacturingCost * (1 + margin)) / tokenPrice
     * Example: ($28 * 1.40) / $0.50 = 78.4 tokens
     */
    function calculateRedemptionRate(
        uint256 manufacturingCost,
        uint256 productId
    ) public view returns (uint256 tokensRequired) {
        require(productMargins[productId] > 0 || productId == 0, "Invalid product ID");

        uint256 marginBPS = productId > 0 ? productMargins[productId] : 4000; // Default 40%

        // Calculate final price with margin
        // finalPrice = manufacturingCost * (1 + marginBPS/10000)
        // finalPrice = manufacturingCost * (10000 + marginBPS) / 10000
        uint256 finalPriceUSD = (manufacturingCost * (BPS_DENOMINATOR + marginBPS)) / BPS_DENOMINATOR;

        // Calculate tokens required
        // tokensRequired = (finalPriceUSD * 10^18) / currentTokenPrice
        tokensRequired = (finalPriceUSD * 10**TOKEN_DECIMALS) / currentTokenPrice;
    }

    /**
     * @dev Calculate redemption rate with custom margin
     * @param manufacturingCost Manufacturing cost in USD (6 decimals)
     * @param marginBPS Custom margin in basis points
     * @return tokensRequired Number of tokens required (18 decimals)
     */
    function calculateRedemptionRateWithMargin(
        uint256 manufacturingCost,
        uint256 marginBPS
    ) public view returns (uint256 tokensRequired) {
        require(marginBPS <= 10000, "Margin exceeds 100%");

        // Calculate final price with margin
        uint256 finalPriceUSD = (manufacturingCost * (BPS_DENOMINATOR + marginBPS)) / BPS_DENOMINATOR;

        // Calculate tokens required
        tokensRequired = (finalPriceUSD * 10**TOKEN_DECIMALS) / currentTokenPrice;
    }

    /**
     * @dev Calculate VIP discount (50% off)
     * @param regularTokens Regular redemption rate
     * @return vipTokens Discounted token amount for VIP
     */
    function calculateVIPDiscount(uint256 regularTokens) public pure returns (uint256 vipTokens) {
        vipTokens = regularTokens / 2;
    }

    /**
     * @dev Update token price (owner or oracle)
     * @param newPrice New token price in USDC (6 decimals)
     */
    function updateTokenPrice(uint256 newPrice) external {
        require(
            msg.sender == owner() || msg.sender == priceOracle,
            "Not authorized"
        );
        require(newPrice >= MIN_TOKEN_PRICE, "Price below minimum");
        require(newPrice <= MAX_TOKEN_PRICE, "Price above maximum");

        uint256 oldPrice = currentTokenPrice;
        currentTokenPrice = newPrice;
        lastPriceUpdate = block.timestamp;

        emit TokenPriceUpdated(oldPrice, newPrice, msg.sender);
    }

    /**
     * @dev Set margin for a product type
     * @param productId Product type identifier
     * @param marginBPS New margin in basis points
     */
    function setProductMargin(uint256 productId, uint256 marginBPS) external onlyOwner {
        require(bytes(productNames[productId]).length > 0, "Product not found");
        require(marginBPS <= 10000, "Margin exceeds 100%");

        uint256 oldMargin = productMargins[productId];
        productMargins[productId] = marginBPS;

        emit ProductMarginUpdated(productId, oldMargin, marginBPS);
    }

    /**
     * @dev Set price oracle address
     * @param _oracle New oracle address
     */
    function setPriceOracle(address _oracle) external onlyOwner {
        address oldOracle = priceOracle;
        priceOracle = _oracle;

        emit OracleUpdated(oldOracle, _oracle);
    }

    /**
     * @dev Get current token price
     * @return price Current price in USDC (6 decimals)
     */
    function getCurrentTokenPrice() external view returns (uint256 price) {
        return currentTokenPrice;
    }

    /**
     * @dev Get product information
     * @param productId Product type identifier
     * @return name Product name
     * @return marginBPS Product margin
     */
    function getProductInfo(uint256 productId) external view returns (
        string memory name,
        uint256 marginBPS
    ) {
        return (productNames[productId], productMargins[productId]);
    }

    /**
     * @dev Calculate USD value of token amount
     * @param tokenAmount Token amount (18 decimals)
     * @return usdValue USD value (6 decimals)
     */
    function getTokenValueUSD(uint256 tokenAmount) external view returns (uint256 usdValue) {
        // usdValue = (tokenAmount * currentTokenPrice) / 10^18
        usdValue = (tokenAmount * currentTokenPrice) / 10**TOKEN_DECIMALS;
    }

    /**
     * @dev Calculate token amount for USD value
     * @param usdValue USD value (6 decimals)
     * @return tokenAmount Token amount (18 decimals)
     */
    function getTokensForUSD(uint256 usdValue) external view returns (uint256 tokenAmount) {
        // tokenAmount = (usdValue * 10^18) / currentTokenPrice
        tokenAmount = (usdValue * 10**TOKEN_DECIMALS) / currentTokenPrice;
    }

    /**
     * @dev Get comprehensive pricing info
     * @return tokenPrice Current token price
     * @return lastUpdate Last price update timestamp
     */
    function getPricingInfo() external view returns (
        uint256 tokenPrice,
        uint256 lastUpdate
    ) {
        return (
            currentTokenPrice,
            lastPriceUpdate
        );
    }
}

