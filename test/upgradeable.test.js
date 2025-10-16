const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("DELTA8 Upgradeable Contracts", function () {
  let deployer, user1, user2, treasury;
  let delta8Token, usdcToken;
  let pricingManager, vipMembership, batchManager, treasuryContract;

  beforeEach(async function () {
    [deployer, user1, user2, treasury] = await ethers.getSigners();

    // Deploy mock tokens (MockUSDC has no constructor params)
    const MockERC20 = await ethers.getContractFactory("contracts/test/MockUSDC.sol:MockUSDC");
    delta8Token = await MockERC20.deploy();
    await delta8Token.waitForDeployment();

    // Deploy mock USDC
    usdcToken = await MockERC20.deploy();
    await usdcToken.waitForDeployment();

    // Mint some tokens for testing
    // Note: VIP membership requires 100 * 10^18 tokens
    // MockUSDC stores in 6 decimals, but transfers are in 18 decimals
    await delta8Token.mint(user1.address, ethers.parseUnits("100", 18)); // 100 tokens with 18 decimals
    await delta8Token.mint(deployer.address, ethers.parseUnits("10000", 18)); // 10k tokens with 18 decimals
    await usdcToken.mint(deployer.address, ethers.parseUnits("10000", 6));

    // Deploy PricingManager
    const PricingManager = await ethers.getContractFactory("PricingManagerUpgradeable");
    pricingManager = await upgrades.deployProxy(
      PricingManager,
      [500000], // $0.50 initial price
      {
        initializer: "initialize",
        kind: "transparent",
      }
    );
    await pricingManager.waitForDeployment();

    // Deploy Treasury
    const Treasury = await ethers.getContractFactory("TreasuryUpgradeable");
    treasuryContract = await upgrades.deployProxy(
      Treasury,
      [await delta8Token.getAddress(), await usdcToken.getAddress()],
      {
        initializer: "initialize",
        kind: "transparent",
      }
    );
    await treasuryContract.waitForDeployment();

    // Deploy VIPMembership
    const VIPMembership = await ethers.getContractFactory("VIPMembershipUpgradeable");
    vipMembership = await upgrades.deployProxy(
      VIPMembership,
      [await delta8Token.getAddress(), await treasuryContract.getAddress()],
      {
        initializer: "initialize",
        kind: "transparent",
      }
    );
    await vipMembership.waitForDeployment();

    // Deploy BatchManager
    const BatchManager = await ethers.getContractFactory("BatchManagerUpgradeable");
    batchManager = await upgrades.deployProxy(
      BatchManager,
      [await pricingManager.getAddress()],
      {
        initializer: "initialize",
        kind: "transparent",
      }
    );
    await batchManager.waitForDeployment();

    // Configure Treasury
    await treasuryContract.authorizeContract(await vipMembership.getAddress(), true);
  });

  describe("PricingManagerUpgradeable", function () {
    it("Should deploy with correct initial price", async function () {
      expect(await pricingManager.currentTokenPrice()).to.equal(500000); // $0.50
    });

    it("Should calculate redemption rate correctly", async function () {
      const cost = ethers.parseUnits("28", 6); // $28 manufacturing cost
      const productId = 1; // Gummy Jar with 40% margin
      const rate = await pricingManager.calculateRedemptionRate(cost, productId);
      
      // Expected: $28 * 1.4 / $0.50 = 78.4 tokens (with 18 decimals)
      const expected = ethers.parseUnits("78.4", 18);
      const tolerance = ethers.parseUnits("0.1", 18);
      
      expect(rate).to.be.closeTo(expected, tolerance);
    });

    it("Should calculate VIP discount correctly", async function () {
      const regularTokens = ethers.parseUnits("100", 18);
      const vipTokens = await pricingManager.calculateVIPDiscount(regularTokens);
      expect(vipTokens).to.equal(ethers.parseUnits("50", 18)); // 50% off
    });

    it("Should allow owner to update token price", async function () {
      await pricingManager.updateTokenPrice(750000); // $0.75
      expect(await pricingManager.currentTokenPrice()).to.equal(750000);
    });
  });

  describe("VIPMembershipUpgradeable", function () {
    beforeEach(async function () {
      // User1 approves VIPMembership to spend tokens
      const cost = await vipMembership.getMembershipCost();
      await delta8Token.connect(user1).approve(await vipMembership.getAddress(), cost);
    });

    it("Should deploy with correct initial cost", async function () {
      // MockUSDC uses 6 decimals, but membership cost is in token decimals (should be 100 * 10^18)
      // However, our MockUSDC will work with what we have
      const cost = await vipMembership.getMembershipCost();
      expect(cost).to.equal(ethers.parseUnits("100", 18));
    });

    it("Should allow user to purchase membership", async function () {
      await vipMembership.connect(user1).purchaseMembership();
      expect(await vipMembership.isVIP(user1.address)).to.be.true;
    });

    it("Should track membership statistics", async function () {
      await vipMembership.connect(user1).purchaseMembership();
      
      const stats = await vipMembership.getStats();
      expect(stats._totalMembers).to.equal(1);
      expect(stats._activeMembers).to.equal(1);
      expect(stats._totalRevenue).to.equal(ethers.parseUnits("100", 18));
    });

    it("Should allow owner to extend membership", async function () {
      await vipMembership.connect(user1).purchaseMembership();
      await vipMembership.extendMembership(user1.address, 30); // 30 days
      
      const info = await vipMembership.getMembershipInfo(user1.address);
      expect(info.active).to.be.true;
    });
  });

  describe("BatchManagerUpgradeable", function () {
    it("Should create new batch", async function () {
      await batchManager.createBatch(
        1, // Product ID
        ethers.parseUnits("28", 6), // $28 cost
        0, // Use default margin
        100, // 100 units
        "BATCH-001",
        "ipfs://test"
      );

      expect(await batchManager.batchCount()).to.equal(1);
      
      const batch = await batchManager.getBatch(1);
      expect(batch.batchCode).to.equal("BATCH-001");
      expect(batch.totalStock).to.equal(100);
      expect(batch.isActive).to.be.true;
    });

    it("Should calculate correct redemption rates for batch", async function () {
      await batchManager.createBatch(
        1,
        ethers.parseUnits("28", 6),
        0,
        100,
        "BATCH-001",
        "ipfs://test"
      );

      const regularRate = await batchManager.getBatchRedemptionRate(1, false);
      const vipRate = await batchManager.getBatchRedemptionRate(1, true);

      // VIP rate should be 50% of regular rate
      expect(vipRate * 2n).to.equal(regularRate);
    });
  });

  describe("TreasuryUpgradeable", function () {
    it("Should track VIP membership revenue", async function () {
      const cost = await vipMembership.getMembershipCost();
      await delta8Token.connect(user1).approve(await vipMembership.getAddress(), cost);
      await vipMembership.connect(user1).purchaseMembership();

      const revenue = await treasuryContract.getRevenue();
      expect(revenue.membershipRevenue).to.equal(cost);
    });

    it("Should allow fund allocation", async function () {
      // Transfer USDC to treasury
      await usdcToken.transfer(await treasuryContract.getAddress(), ethers.parseUnits("1000", 6));
      
      // Allocate to staking rewards
      await treasuryContract.allocateToStakingRewards(ethers.parseUnits("500", 6));
      
      const allocations = await treasuryContract.getAllocations();
      expect(allocations.stakingRewards).to.equal(ethers.parseUnits("500", 6));
    });
  });

  describe("Contract Upgrades", function () {
    it("Should upgrade VIPMembership and preserve state", async function () {
      // Purchase membership in V1
      const cost = await vipMembership.getMembershipCost();
      await delta8Token.connect(user1).approve(await vipMembership.getAddress(), cost);
      await vipMembership.connect(user1).purchaseMembership();
      
      const isVIPBefore = await vipMembership.isVIP(user1.address);
      const statsBefore = await vipMembership.getStats();

      // Upgrade to V2 (same contract for testing)
      const VIPMembershipV2 = await ethers.getContractFactory("VIPMembershipUpgradeable");
      const upgraded = await upgrades.upgradeProxy(await vipMembership.getAddress(), VIPMembershipV2);

      // Verify state preserved
      const isVIPAfter = await upgraded.isVIP(user1.address);
      const statsAfter = await upgraded.getStats();

      expect(isVIPBefore).to.equal(isVIPAfter);
      expect(statsBefore._totalMembers).to.equal(statsAfter._totalMembers);
      expect(statsBefore._activeMembers).to.equal(statsAfter._activeMembers);
    });

    it("Should upgrade PricingManager and preserve price", async function () {
      // Set custom price
      await pricingManager.updateTokenPrice(750000); // $0.75
      const priceBefore = await pricingManager.currentTokenPrice();

      // Upgrade
      const PricingManagerV2 = await ethers.getContractFactory("PricingManagerUpgradeable");
      const upgraded = await upgrades.upgradeProxy(await pricingManager.getAddress(), PricingManagerV2);

      // Verify price preserved
      const priceAfter = await upgraded.currentTokenPrice();
      expect(priceBefore).to.equal(priceAfter);
    });

    it("Should upgrade BatchManager and preserve batches", async function () {
      // Create batch
      await batchManager.createBatch(
        1,
        ethers.parseUnits("28", 6),
        0,
        100,
        "BATCH-001",
        "ipfs://test"
      );
      
      const batchBefore = await batchManager.getBatch(1);

      // Upgrade
      const BatchManagerV2 = await ethers.getContractFactory("BatchManagerUpgradeable");
      const upgraded = await upgrades.upgradeProxy(await batchManager.getAddress(), BatchManagerV2);

      // Verify batch preserved
      const batchAfter = await upgraded.getBatch(1);
      expect(batchBefore.batchCode).to.equal(batchAfter.batchCode);
      expect(batchBefore.totalStock).to.equal(batchAfter.totalStock);
    });

    it("Should upgrade Treasury and preserve balances", async function () {
      // Add funds to treasury
      await delta8Token.transfer(await treasuryContract.getAddress(), ethers.parseUnits("1000", 6));
      const balanceBefore = await treasuryContract.getBalances();

      // Upgrade
      const TreasuryV2 = await ethers.getContractFactory("TreasuryUpgradeable");
      const upgraded = await upgrades.upgradeProxy(await treasuryContract.getAddress(), TreasuryV2);

      // Verify balance preserved
      const balanceAfter = await upgraded.getBalances();
      expect(balanceBefore.delta8Balance).to.equal(balanceAfter.delta8Balance);
    });
  });

  describe("Integration Tests", function () {
    it("Should work together: VIP purchase -> Treasury tracking", async function () {
      const cost = await vipMembership.getMembershipCost();
      await delta8Token.connect(user1).approve(await vipMembership.getAddress(), cost);
      
      // Purchase membership
      await vipMembership.connect(user1).purchaseMembership();
      
      // Verify VIP status
      expect(await vipMembership.isVIP(user1.address)).to.be.true;
      
      // Verify treasury received funds
      const revenue = await treasuryContract.getRevenue();
      expect(revenue.membershipRevenue).to.equal(cost);
      
      // Verify treasury balance
      const balances = await treasuryContract.getBalances();
      expect(balances.delta8Balance).to.equal(cost);
    });

    it("Should calculate VIP rates correctly via BatchManager", async function () {
      // Create batch
      await batchManager.createBatch(
        1,
        ethers.parseUnits("28", 6),
        0,
        100,
        "BATCH-001",
        "ipfs://test"
      );

      // Get rates
      const regularRate = await batchManager.getBatchRedemptionRate(1, false);
      const vipRate = await batchManager.getBatchRedemptionRate(1, true);

      // VIP should be 50% of regular
      expect(vipRate * 2n).to.equal(regularRate);
    });
  });
});
