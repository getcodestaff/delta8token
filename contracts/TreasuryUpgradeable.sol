// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title TreasuryUpgradeable
 * @dev Treasury contract for managing DELTA8 ecosystem funds (Upgradeable)
 *
 * PURPOSE:
 * - Receive VIP membership payments (100 DELTA8 per member)
 * - Fund staking rewards pool with USDC
 * - Allocate tokens for marketing, liquidity, team
 * - Track all fund movements on-chain
 * - UPGRADEABLE for future enhancements
 *
 * FUND SOURCES:
 * - VIP membership fees (100 DELTA8 per year per member)
 * - Token sale proceeds (USDC)
 * - Product sales revenue (future)
 *
 * FUND USES:
 * - Staking rewards (USDC paid to stakers)
 * - Marketing campaigns
 * - DEX liquidity provision
 * - Team incentives
 * - Operational expenses
 */
contract TreasuryUpgradeable is 
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    // Tokens
    IERC20 public delta8Token;  // DELTA8 token
    IERC20 public usdcToken;    // USDC for rewards

    // Authorized contracts that can interact with treasury
    mapping(address => bool) public authorizedContracts;

    // Fund allocation tracking
    struct FundAllocation {
        uint256 stakingRewards;    // USDC allocated for staking rewards
        uint256 marketing;         // DELTA8 allocated for marketing
        uint256 liquidity;         // DELTA8 allocated for DEX liquidity
        uint256 team;              // DELTA8 allocated for team
        uint256 operations;        // USDC allocated for operations
    }

    FundAllocation public allocations;

    // Revenue tracking
    struct RevenueStats {
        uint256 membershipRevenue; // Total DELTA8 from memberships
        uint256 tokenSaleRevenue;  // Total USDC from token sales
        uint256 productRevenue;    // Total USDC from product sales
    }

    RevenueStats public revenue;

    // Expense tracking
    struct ExpenseStats {
        uint256 rewardsPaid;       // Total USDC paid as rewards
        uint256 marketingSpent;    // Total DELTA8 spent on marketing
        uint256 liquidityAdded;    // Total DELTA8 added to liquidity
        uint256 teamPayments;      // Total DELTA8 paid to team
        uint256 operationsSpent;   // Total USDC spent on operations
    }

    ExpenseStats public expenses;

    // Events
    event FundsReceived(
        address indexed token,
        address indexed from,
        uint256 amount,
        string category
    );
    event FundsAllocated(
        string category,
        uint256 amount,
        address indexed token
    );
    event FundsWithdrawn(
        address indexed token,
        address indexed to,
        uint256 amount,
        string purpose
    );
    event ContractAuthorized(address indexed contractAddress, bool authorized);
    event RewardPoolFunded(uint256 amount, address indexed rewardContract);
    event ProductPurchased(
        address indexed buyer,
        uint256 indexed orderId,
        uint256 tokenAmount,
        string encryptedShipping,
        uint256 timestamp
    );

    // Storage gap for future upgrades
    uint256[49] private __gap; // Reduced by 1 to account for new event

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract (replaces constructor)
     * @param _delta8Token DELTA8 token address
     * @param _usdcToken USDC token address
     */
    function initialize(
        address _delta8Token,
        address _usdcToken
    ) public initializer {
        require(_delta8Token != address(0), "Invalid DELTA8 address");
        require(_usdcToken != address(0), "Invalid USDC address");

        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        delta8Token = IERC20(_delta8Token);
        usdcToken = IERC20(_usdcToken);
    }

    /**
     * @dev Record VIP membership payment
     * Called automatically when VIPMembership contract transfers tokens
     * @param amount Amount of DELTA8 received
     */
    function recordMembershipPayment(uint256 amount) external {
        require(authorizedContracts[msg.sender], "Not authorized");

        revenue.membershipRevenue += amount;

        emit FundsReceived(
            address(delta8Token),
            msg.sender,
            amount,
            "VIP Membership"
        );
    }

    /**
     * @dev Receive token sale proceeds (USDC)
     * @param amount Amount of USDC
     */
    function receiveTokenSaleProceeds(uint256 amount)
        external
        onlyOwner
        nonReentrant
    {
        require(amount > 0, "Amount must be greater than zero");

        usdcToken.safeTransferFrom(msg.sender, address(this), amount);
        revenue.tokenSaleRevenue += amount;

        emit FundsReceived(
            address(usdcToken),
            msg.sender,
            amount,
            "Token Sale"
        );
    }

    /**
     * @dev Receive product sale revenue (USDC)
     * @param amount Amount of USDC
     */
    function receiveProductRevenue(uint256 amount)
        external
        onlyOwner
        nonReentrant
    {
        require(amount > 0, "Amount must be greater than zero");

        usdcToken.safeTransferFrom(msg.sender, address(this), amount);
        revenue.productRevenue += amount;

        emit FundsReceived(
            address(usdcToken),
            msg.sender,
            amount,
            "Product Sales"
        );
    }

    /**
     * @dev Allocate funds to staking rewards pool
     * @param amount Amount of USDC to allocate
     */
    function allocateToStakingRewards(uint256 amount)
        external
        onlyOwner
    {
        require(amount > 0, "Amount must be greater than zero");
        require(
            usdcToken.balanceOf(address(this)) >= amount,
            "Insufficient USDC balance"
        );

        allocations.stakingRewards += amount;

        emit FundsAllocated("Staking Rewards", amount, address(usdcToken));
    }

    /**
     * @dev Fund staking rewards contract
     * @param rewardContract Address of staking rewards contract
     * @param amount Amount of USDC to transfer
     */
    function fundRewardsPool(address rewardContract, uint256 amount)
        external
        onlyOwner
        nonReentrant
    {
        require(rewardContract != address(0), "Invalid contract address");
        require(amount > 0, "Amount must be greater than zero");
        require(
            amount <= allocations.stakingRewards,
            "Exceeds allocated amount"
        );
        require(
            usdcToken.balanceOf(address(this)) >= amount,
            "Insufficient USDC balance"
        );

        allocations.stakingRewards -= amount;
        expenses.rewardsPaid += amount;

        usdcToken.safeTransfer(rewardContract, amount);

        emit RewardPoolFunded(amount, rewardContract);
        emit FundsWithdrawn(
            address(usdcToken),
            rewardContract,
            amount,
            "Staking Rewards"
        );
    }

    /**
     * @dev Allocate DELTA8 tokens for marketing
     * @param amount Amount of DELTA8 to allocate
     */
    function allocateToMarketing(uint256 amount)
        external
        onlyOwner
    {
        require(amount > 0, "Amount must be greater than zero");
        require(
            delta8Token.balanceOf(address(this)) >= amount,
            "Insufficient DELTA8 balance"
        );

        allocations.marketing += amount;

        emit FundsAllocated("Marketing", amount, address(delta8Token));
    }

    /**
     * @dev Spend marketing allocation
     * @param recipient Address to send tokens to
     * @param amount Amount of DELTA8
     * @param purpose Description of marketing spend
     */
    function spendMarketing(
        address recipient,
        uint256 amount,
        string calldata purpose
    )
        external
        onlyOwner
        nonReentrant
    {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be greater than zero");
        require(
            amount <= allocations.marketing,
            "Exceeds marketing allocation"
        );

        allocations.marketing -= amount;
        expenses.marketingSpent += amount;

        delta8Token.safeTransfer(recipient, amount);

        emit FundsWithdrawn(address(delta8Token), recipient, amount, purpose);
    }

    /**
     * @dev Allocate DELTA8 for DEX liquidity
     * @param amount Amount of DELTA8
     */
    function allocateToLiquidity(uint256 amount)
        external
        onlyOwner
    {
        require(amount > 0, "Amount must be greater than zero");
        require(
            delta8Token.balanceOf(address(this)) >= amount,
            "Insufficient DELTA8 balance"
        );

        allocations.liquidity += amount;

        emit FundsAllocated("Liquidity", amount, address(delta8Token));
    }

    /**
     * @dev Add liquidity to DEX
     * @param recipient DEX router or LP address
     * @param amount Amount of DELTA8
     */
    function addLiquidity(address recipient, uint256 amount)
        external
        onlyOwner
        nonReentrant
    {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be greater than zero");
        require(
            amount <= allocations.liquidity,
            "Exceeds liquidity allocation"
        );

        allocations.liquidity -= amount;
        expenses.liquidityAdded += amount;

        delta8Token.safeTransfer(recipient, amount);

        emit FundsWithdrawn(
            address(delta8Token),
            recipient,
            amount,
            "DEX Liquidity"
        );
    }

    /**
     * @dev Allocate DELTA8 for team payments
     * @param amount Amount of DELTA8
     */
    function allocateToTeam(uint256 amount)
        external
        onlyOwner
    {
        require(amount > 0, "Amount must be greater than zero");
        require(
            delta8Token.balanceOf(address(this)) >= amount,
            "Insufficient DELTA8 balance"
        );

        allocations.team += amount;

        emit FundsAllocated("Team", amount, address(delta8Token));
    }

    /**
     * @dev Pay team member
     * @param teamMember Address of team member
     * @param amount Amount of DELTA8
     */
    function payTeam(address teamMember, uint256 amount)
        external
        onlyOwner
        nonReentrant
    {
        require(teamMember != address(0), "Invalid team member");
        require(amount > 0, "Amount must be greater than zero");
        require(amount <= allocations.team, "Exceeds team allocation");

        allocations.team -= amount;
        expenses.teamPayments += amount;

        delta8Token.safeTransfer(teamMember, amount);

        emit FundsWithdrawn(
            address(delta8Token),
            teamMember,
            amount,
            "Team Payment"
        );
    }

    /**
     * @dev Allocate USDC for operations
     * @param amount Amount of USDC
     */
    function allocateToOperations(uint256 amount)
        external
        onlyOwner
    {
        require(amount > 0, "Amount must be greater than zero");
        require(
            usdcToken.balanceOf(address(this)) >= amount,
            "Insufficient USDC balance"
        );

        allocations.operations += amount;

        emit FundsAllocated("Operations", amount, address(usdcToken));
    }

    /**
     * @dev Spend operations allocation
     * @param recipient Address to send USDC to
     * @param amount Amount of USDC
     * @param purpose Description of operational expense
     */
    function spendOperations(
        address recipient,
        uint256 amount,
        string calldata purpose
    )
        external
        onlyOwner
        nonReentrant
    {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be greater than zero");
        require(
            amount <= allocations.operations,
            "Exceeds operations allocation"
        );

        allocations.operations -= amount;
        expenses.operationsSpent += amount;

        usdcToken.safeTransfer(recipient, amount);

        emit FundsWithdrawn(address(usdcToken), recipient, amount, purpose);
    }

    /**
     * @dev Authorize contract to interact with treasury
     * @param contractAddress Address of contract (e.g., VIPMembership)
     * @param authorized True to authorize, false to revoke
     */
    function authorizeContract(address contractAddress, bool authorized)
        external
        onlyOwner
    {
        require(contractAddress != address(0), "Invalid contract address");

        authorizedContracts[contractAddress] = authorized;

        emit ContractAuthorized(contractAddress, authorized);
    }

    /**
     * @dev Get treasury balances
     */
    function getBalances()
        external
        view
        returns (
            uint256 delta8Balance,
            uint256 usdcBalance
        )
    {
        return (
            delta8Token.balanceOf(address(this)),
            usdcToken.balanceOf(address(this))
        );
    }

    /**
     * @dev Get revenue summary
     */
    function getRevenue()
        external
        view
        returns (
            uint256 membershipRevenue,
            uint256 tokenSaleRevenue,
            uint256 productRevenue,
            uint256 totalRevenue
        )
    {
        return (
            revenue.membershipRevenue,
            revenue.tokenSaleRevenue,
            revenue.productRevenue,
            revenue.membershipRevenue + revenue.tokenSaleRevenue + revenue.productRevenue
        );
    }

    /**
     * @dev Get expense summary
     */
    function getExpenses()
        external
        view
        returns (
            uint256 rewardsPaid,
            uint256 marketingSpent,
            uint256 liquidityAdded,
            uint256 teamPayments,
            uint256 operationsSpent
        )
    {
        return (
            expenses.rewardsPaid,
            expenses.marketingSpent,
            expenses.liquidityAdded,
            expenses.teamPayments,
            expenses.operationsSpent
        );
    }

    /**
     * @dev Get allocation summary
     */
    function getAllocations()
        external
        view
        returns (
            uint256 stakingRewards,
            uint256 marketing,
            uint256 liquidity,
            uint256 team,
            uint256 operations
        )
    {
        return (
            allocations.stakingRewards,
            allocations.marketing,
            allocations.liquidity,
            allocations.team,
            allocations.operations
        );
    }

    /**
     * @dev Record a product purchase with encrypted shipping info
     * @param orderId Unique order identifier
     * @param tokenAmount Amount of DELTA8 tokens spent
     * @param encryptedShipping AES-256 encrypted shipping data
     * 
     * NOTE: This function only records the purchase event on-chain.
     * The actual token transfer must happen separately (direct transfer to merchant).
     * This allows customers' shipping info to be stored encrypted on-chain.
     */
    function recordProductPurchase(
        uint256 orderId,
        uint256 tokenAmount,
        string calldata encryptedShipping
    ) external {
        require(orderId > 0, "Invalid order ID");
        require(tokenAmount > 0, "Invalid token amount");
        require(bytes(encryptedShipping).length > 0, "Encrypted shipping required");
        require(bytes(encryptedShipping).length <= 500, "Shipping data too long");

        revenue.productRevenue += tokenAmount;

        emit ProductPurchased(
            msg.sender,
            orderId,
            tokenAmount,
            encryptedShipping,
            block.timestamp
        );
    }

    /**
     * @dev Emergency withdrawal (only for critical situations)
     * @param token Token address (DELTA8 or USDC)
     * @param recipient Recipient address
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(
        address token,
        address recipient,
        uint256 amount
    )
        external
        onlyOwner
        nonReentrant
    {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be greater than zero");

        IERC20(token).safeTransfer(recipient, amount);

        emit FundsWithdrawn(token, recipient, amount, "Emergency Withdrawal");
    }
}

