const { ethers, upgrades } = require("hardhat");
const fs = require("fs");
const path = require("path");

/**
 * Deploy all upgradeable DELTA8 contracts
 * 
 * This script deploys:
 * - VIPMembershipUpgradeable
 * - PricingManagerUpgradeable
 * - BatchManagerUpgradeable
 * - TreasuryUpgradeable
 * 
 * All contracts use transparent proxies for upgradeability
 */
async function main() {
  console.log("\n🚀 Deploying Upgradeable DELTA8 Ecosystem Contracts...\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "POL\n");

  // Get existing contract addresses (from previous deployments)
  const DELTA8_TOKEN = process.env.DELTA8_TOKEN || "0x9f79ad35Ba50dcAA7eD1f857E3287779cD64bcd6";
  const USDC_TOKEN = process.env.USDC_TOKEN || "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359";

  console.log("Using existing deployed contracts:");
  console.log("DELTA8 Token:", DELTA8_TOKEN);
  console.log("USDC Token:", USDC_TOKEN);
  console.log();

  const network = await ethers.provider.getNetwork();
  const deployedAddresses = {
    network: network.name,
    chainId: Number(network.chainId), // Convert BigInt to Number
    deployer: deployer.address,
    existingContracts: {
      delta8Token: DELTA8_TOKEN,
      usdcToken: USDC_TOKEN,
    },
    upgradeable: {}
  };

  // 1. Deploy PricingManager (needed by BatchManager)
  console.log("📊 Deploying PricingManagerUpgradeable...");
  const PricingManager = await ethers.getContractFactory("PricingManagerUpgradeable");
  const initialPrice = 500000; // $0.50 (6 decimals)
  
  const pricingManager = await upgrades.deployProxy(
    PricingManager,
    [initialPrice],
    { 
      initializer: "initialize",
      kind: "transparent"
    }
  );
  await pricingManager.waitForDeployment();
  
  const pricingManagerAddress = await pricingManager.getAddress();
  const pricingManagerImpl = await upgrades.erc1967.getImplementationAddress(pricingManagerAddress);
  console.log("✅ PricingManager Proxy:", pricingManagerAddress);
  console.log("   Implementation:", pricingManagerImpl);
  
  deployedAddresses.upgradeable.pricingManager = {
    proxy: pricingManagerAddress,
    implementation: pricingManagerImpl
  };

  // 2. Deploy Treasury
  console.log("\n💰 Deploying TreasuryUpgradeable...");
  const Treasury = await ethers.getContractFactory("TreasuryUpgradeable");
  
  const treasury = await upgrades.deployProxy(
    Treasury,
    [DELTA8_TOKEN, USDC_TOKEN],
    { 
      initializer: "initialize",
      kind: "transparent"
    }
  );
  await treasury.waitForDeployment();
  
  const treasuryAddress = await treasury.getAddress();
  const treasuryImpl = await upgrades.erc1967.getImplementationAddress(treasuryAddress);
  console.log("✅ Treasury Proxy:", treasuryAddress);
  console.log("   Implementation:", treasuryImpl);
  
  deployedAddresses.upgradeable.treasury = {
    proxy: treasuryAddress,
    implementation: treasuryImpl
  };

  // 3. Deploy VIPMembership
  console.log("\n👑 Deploying VIPMembershipUpgradeable...");
  const VIPMembership = await ethers.getContractFactory("VIPMembershipUpgradeable");
  
  const vipMembership = await upgrades.deployProxy(
    VIPMembership,
    [DELTA8_TOKEN, treasuryAddress],
    { 
      initializer: "initialize",
      kind: "transparent"
    }
  );
  await vipMembership.waitForDeployment();
  
  const vipMembershipAddress = await vipMembership.getAddress();
  const vipMembershipImpl = await upgrades.erc1967.getImplementationAddress(vipMembershipAddress);
  console.log("✅ VIPMembership Proxy:", vipMembershipAddress);
  console.log("   Implementation:", vipMembershipImpl);
  
  deployedAddresses.upgradeable.vipMembership = {
    proxy: vipMembershipAddress,
    implementation: vipMembershipImpl
  };

  // 4. Deploy BatchManager
  console.log("\n📦 Deploying BatchManagerUpgradeable...");
  const BatchManager = await ethers.getContractFactory("BatchManagerUpgradeable");
  
  const batchManager = await upgrades.deployProxy(
    BatchManager,
    [pricingManagerAddress],
    { 
      initializer: "initialize",
      kind: "transparent"
    }
  );
  await batchManager.waitForDeployment();
  
  const batchManagerAddress = await batchManager.getAddress();
  const batchManagerImpl = await upgrades.erc1967.getImplementationAddress(batchManagerAddress);
  console.log("✅ BatchManager Proxy:", batchManagerAddress);
  console.log("   Implementation:", batchManagerImpl);
  
  deployedAddresses.upgradeable.batchManager = {
    proxy: batchManagerAddress,
    implementation: batchManagerImpl
  };

  // Configure Treasury to accept VIPMembership
  console.log("\n⚙️  Configuring contracts...");
  console.log("Authorizing VIPMembership contract in Treasury...");
  await treasury.authorizeContract(vipMembershipAddress, true);
  console.log("✅ Treasury configuration complete");

  // Save deployment addresses
  const outputDir = path.join(__dirname, "..", "deployments");
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const filename = `upgradeable-${deployedAddresses.network}-${timestamp}.json`;
  const filepath = path.join(outputDir, filename);

  fs.writeFileSync(filepath, JSON.stringify(deployedAddresses, null, 2));
  console.log("\n📄 Deployment addresses saved to:", filepath);

  // Also save as latest
  const latestFile = path.join(outputDir, "upgradeable-latest.json");
  fs.writeFileSync(latestFile, JSON.stringify(deployedAddresses, null, 2));
  console.log("📄 Also saved as:", latestFile);

  // Print summary
  console.log("\n" + "=".repeat(80));
  console.log("🎉 DEPLOYMENT COMPLETE!");
  console.log("=".repeat(80));
  console.log("\n📋 Deployed Contracts:\n");
  console.log("PricingManager (Proxy):", deployedAddresses.upgradeable.pricingManager.proxy);
  console.log("Treasury (Proxy):", deployedAddresses.upgradeable.treasury.proxy);
  console.log("VIPMembership (Proxy):", deployedAddresses.upgradeable.vipMembership.proxy);
  console.log("BatchManager (Proxy):", deployedAddresses.upgradeable.batchManager.proxy);
  
  console.log("\n💡 To upgrade a contract:");
  console.log("   npx hardhat run scripts/upgradeContract.js --network <network>");
  
  console.log("\n🔗 Update frontend/.env with these addresses:");
  console.log(`REACT_APP_PRICING_MANAGER=${deployedAddresses.upgradeable.pricingManager.proxy}`);
  console.log(`REACT_APP_TREASURY=${deployedAddresses.upgradeable.treasury.proxy}`);
  console.log(`REACT_APP_VIP_MEMBERSHIP=${deployedAddresses.upgradeable.vipMembership.proxy}`);
  console.log(`REACT_APP_BATCH_MANAGER=${deployedAddresses.upgradeable.batchManager.proxy}`);
  console.log();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Deployment failed:", error);
    process.exit(1);
  });

