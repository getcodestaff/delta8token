// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// Interface for Treasury contract
interface ITreasury {
    function recordMembershipPayment(uint256 amount) external;
}

/**
 * @title VIPMembershipUpgradeable
 * @dev Yearly VIP membership contract for DELTA8 ecosystem (Upgradeable)
 *
 * KEY FEATURES:
 * - Pay 100 DELTA8 tokens for 1-year VIP membership (configurable via upgrade)
 * - Tokens sent to treasury (NOT burned)
 * - VIP benefits: 50% off all product purchases
 * - Renewable before expiry
 * - Separate from staking rewards
 * - UPGRADEABLE for future enhancements
 *
 * MEMBERSHIP MODEL:
 * - Cost: 100 DELTA8 tokens (fixed, no USD calculation)
 * - Duration: 365 days from purchase
 * - Benefits: 50% discount on all products
 * - Renewal: Can renew anytime (extends current expiry)
 * - Transfer: Non-transferable (tied to wallet address)
 */
contract VIPMembershipUpgradeable is 
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    // DELTA8 token
    IERC20 public delta8Token;

    // Treasury address (receives membership payments)
    address public treasury;

    // Membership constants (can be modified in future upgrades)
    uint256 public membershipCost; // 100 DELTA8 tokens initially
    uint256 public membershipDuration; // 365 days initially

    // Membership tracking
    struct Membership {
        uint256 purchaseDate;      // When membership was purchased
        uint256 expiryDate;        // When membership expires
        uint256 renewalCount;      // Number of times renewed
        bool active;               // Whether membership is active
    }

    mapping(address => Membership) public memberships;

    // Statistics
    uint256 public totalMembers;           // Total unique members (past and present)
    uint256 public activeMembers;          // Currently active members
    uint256 public totalRevenue;           // Total tokens collected (all time)
    uint256 public totalRenewals;          // Total renewal count

    // Events
    event MembershipPurchased(
        address indexed member,
        uint256 purchaseDate,
        uint256 expiryDate,
        uint256 cost,
        bool isRenewal
    );
    event MembershipExpired(address indexed member, uint256 expiryDate);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event MembershipRevoked(address indexed member, address indexed admin);
    event MembershipExtended(
        address indexed member,
        uint256 oldExpiry,
        uint256 newExpiry,
        uint256 daysAdded
    );
    event MembershipCostUpdated(uint256 oldCost, uint256 newCost);
    event MembershipDurationUpdated(uint256 oldDuration, uint256 newDuration);

    // Storage gap for future upgrades
    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract (replaces constructor)
     * @param _delta8Token DELTA8 token address
     * @param _treasury Treasury address to receive payments
     */
    function initialize(
        address _delta8Token,
        address _treasury
    ) public initializer {
        require(_delta8Token != address(0), "Invalid token address");
        require(_treasury != address(0), "Invalid treasury address");

        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();

        delta8Token = IERC20(_delta8Token);
        treasury = _treasury;
        membershipCost = 100 * 10**18; // 100 DELTA8 tokens
        membershipDuration = 365 days; // 1 year
    }

    /**
     * @dev Purchase VIP membership for 1 year
     * Transfers DELTA8 tokens to treasury
     * Can also renew existing membership (adds duration to expiry)
     */
    function purchaseMembership()
        external
        nonReentrant
        whenNotPaused
    {
        require(
            delta8Token.balanceOf(msg.sender) >= membershipCost,
            "Insufficient token balance"
        );

        Membership storage membership = memberships[msg.sender];
        bool isRenewal = membership.active && membership.expiryDate > block.timestamp;

        // Transfer tokens to treasury
        delta8Token.safeTransferFrom(msg.sender, treasury, membershipCost);
        
        // Record payment in treasury (if treasury supports it)
        try ITreasury(treasury).recordMembershipPayment(membershipCost) {
            // Successfully recorded
        } catch {
            // Treasury doesn't support recording or not authorized - that's ok
        }

        uint256 newExpiryDate;

        if (isRenewal) {
            // Renewing active membership - extend from current expiry
            newExpiryDate = membership.expiryDate + membershipDuration;
            membership.renewalCount++;
            totalRenewals++;
        } else {
            // New membership or reactivating expired membership
            newExpiryDate = block.timestamp + membershipDuration;

            if (!membership.active) {
                // Brand new member
                totalMembers++;
            }

            membership.purchaseDate = block.timestamp;
            membership.renewalCount = 0;
        }

        membership.expiryDate = newExpiryDate;
        membership.active = true;

        activeMembers++;
        totalRevenue += membershipCost;

        emit MembershipPurchased(
            msg.sender,
            membership.purchaseDate,
            newExpiryDate,
            membershipCost,
            isRenewal
        );
    }

    /**
     * @dev Check if address has active VIP membership
     * @param user Address to check
     * @return true if user has active membership
     */
    function isVIP(address user) public view returns (bool) {
        Membership memory membership = memberships[user];
        return membership.active && membership.expiryDate > block.timestamp;
    }

    /**
     * @dev Get membership expiry timestamp
     * @param user Address to check
     * @return Expiry timestamp (0 if no membership)
     */
    function getMembershipExpiry(address user) public view returns (uint256) {
        return memberships[user].expiryDate;
    }

    /**
     * @dev Get detailed membership info
     * @param user Address to check
     */
    function getMembershipInfo(address user)
        external
        view
        returns (
            bool active,
            uint256 purchaseDate,
            uint256 expiryDate,
            uint256 daysRemaining,
            uint256 renewalCount,
            bool canRenew
        )
    {
        Membership memory membership = memberships[user];

        active = isVIP(user);
        purchaseDate = membership.purchaseDate;
        expiryDate = membership.expiryDate;
        renewalCount = membership.renewalCount;
        canRenew = true; // Can always renew

        if (active) {
            daysRemaining = (membership.expiryDate - block.timestamp) / 1 days;
        } else {
            daysRemaining = 0;
        }
    }

    /**
     * @dev Get membership cost
     * @return Cost in wei
     */
    function getMembershipCost() external view returns (uint256) {
        return membershipCost;
    }

    /**
     * @dev Check if membership is expiring soon (within 30 days)
     * @param user Address to check
     * @return true if expiring within 30 days
     */
    function isExpiringSoon(address user) external view returns (bool) {
        if (!isVIP(user)) return false;

        uint256 expiryDate = memberships[user].expiryDate;
        uint256 thirtyDaysFromNow = block.timestamp + 30 days;

        return expiryDate <= thirtyDaysFromNow;
    }

    /**
     * @dev Get contract statistics
     */
    function getStats()
        external
        view
        returns (
            uint256 _totalMembers,
            uint256 _activeMembers,
            uint256 _totalRevenue,
            uint256 _totalRenewals,
            uint256 _treasuryBalance
        )
    {
        return (
            totalMembers,
            activeMembers,
            totalRevenue,
            totalRenewals,
            delta8Token.balanceOf(treasury)
        );
    }

    /**
     * @dev Admin function to extend membership (for promotions, support, etc.)
     * @param user Address to extend
     * @param daysToAdd Number of days to add
     */
    function extendMembership(address user, uint256 daysToAdd)
        external
        onlyOwner
    {
        require(daysToAdd > 0, "Must add at least 1 day");
        require(memberships[user].expiryDate > 0, "No membership exists");

        Membership storage membership = memberships[user];
        uint256 oldExpiry = membership.expiryDate;
        uint256 additionalTime = daysToAdd * 1 days;

        // If expired, extend from now. If active, extend from current expiry
        if (membership.expiryDate < block.timestamp) {
            membership.expiryDate = block.timestamp + additionalTime;
            membership.active = true;
            activeMembers++;
        } else {
            membership.expiryDate += additionalTime;
        }

        emit MembershipExtended(
            user,
            oldExpiry,
            membership.expiryDate,
            daysToAdd
        );
    }

    /**
     * @dev Admin function to revoke membership (for violations, fraud, etc.)
     * @param user Address to revoke
     */
    function revokeMembership(address user) external onlyOwner {
        require(isVIP(user), "User is not VIP");

        Membership storage membership = memberships[user];
        membership.active = false;
        membership.expiryDate = block.timestamp; // Set to now (expired)

        if (activeMembers > 0) {
            activeMembers--;
        }

        emit MembershipRevoked(user, msg.sender);
    }

    /**
     * @dev Update treasury address (owner only)
     * @param _treasury New treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury address");

        address oldTreasury = treasury;
        treasury = _treasury;

        emit TreasuryUpdated(oldTreasury, _treasury);
    }

    /**
     * @dev Update membership cost (owner only) - UPGRADEABLE FEATURE
     * @param _membershipCost New cost in wei
     */
    function setMembershipCost(uint256 _membershipCost) external onlyOwner {
        require(_membershipCost > 0, "Cost must be greater than 0");

        uint256 oldCost = membershipCost;
        membershipCost = _membershipCost;

        emit MembershipCostUpdated(oldCost, _membershipCost);
    }

    /**
     * @dev Update membership duration (owner only) - UPGRADEABLE FEATURE
     * @param _membershipDuration New duration in seconds
     */
    function setMembershipDuration(uint256 _membershipDuration) external onlyOwner {
        require(_membershipDuration > 0, "Duration must be greater than 0");

        uint256 oldDuration = membershipDuration;
        membershipDuration = _membershipDuration;

        emit MembershipDurationUpdated(oldDuration, _membershipDuration);
    }

    /**
     * @dev Pause membership purchases (owner only)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause membership purchases (owner only)
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Clean up expired memberships from activeMembers count
     * @param users Array of addresses to check
     * Can be called by anyone to keep stats accurate
     */
    function cleanupExpiredMemberships(address[] calldata users) external {
        for (uint256 i = 0; i < users.length; i++) {
            Membership storage membership = memberships[users[i]];

            // If marked active but actually expired, clean up
            if (membership.active && membership.expiryDate <= block.timestamp) {
                membership.active = false;
                if (activeMembers > 0) {
                    activeMembers--;
                }
                emit MembershipExpired(users[i], membership.expiryDate);
            }
        }
    }
}

