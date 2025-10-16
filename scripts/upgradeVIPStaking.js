const { ethers, upgrades } = require("hardhat");
const fs = require("fs");
const path = require("path");

/**
 * Upgrade a specific upgradeable contract
 * 
 * Usage:
 * npx hardhat run scripts/upgradeContract.js --network polygon
 * 
 * Then follow the prompts to select which contract to upgrade
 */
async function main() {
  console.log("\n🔄 DELTA8 Contract Upgrade Tool\n");

  const [deployer] = await ethers.getSigners();
  console.log("Upgrading with account:", deployer.address);
  console.log("Account balance:", ethers.utils.formatEther(await deployer.getBalance()), "POL\n");

  // Load latest deployment addresses
  const deploymentsDir = path.join(__dirname, "..", "deployments");
  const latestFile = path.join(deploymentsDir, "upgradeable-latest.json");

  if (!fs.existsSync(latestFile)) {
    console.error("❌ No deployment file found. Please deploy contracts first.");
    console.log("   Run: npx hardhat run scripts/deployUpgradeable.js --network <network>");
    process.exit(1);
  }

  const deploymentData = JSON.parse(fs.readFileSync(latestFile, "utf8"));
  const contracts = deploymentData.upgradeable;

  console.log("Available contracts to upgrade:\n");
  console.log("1. PricingManager");
  console.log("   Current Proxy:", contracts.pricingManager?.proxy);
  console.log("   Current Implementation:", contracts.pricingManager?.implementation);
  console.log();
  console.log("2. Treasury");
  console.log("   Current Proxy:", contracts.treasury?.proxy);
  console.log("   Current Implementation:", contracts.treasury?.implementation);
  console.log();
  console.log("3. VIPMembership");
  console.log("   Current Proxy:", contracts.vipMembership?.proxy);
  console.log("   Current Implementation:", contracts.vipMembership?.implementation);
  console.log();
  console.log("4. BatchManager");
  console.log("   Current Proxy:", contracts.batchManager?.proxy);
  console.log("   Current Implementation:", contracts.batchManager?.implementation);
  console.log();

  // For this example, let's upgrade VIPMembership
  // In production, you'd use readline to prompt the user
  const contractToUpgrade = process.env.UPGRADE_CONTRACT || "VIPMembership";
  
  console.log(`\n🎯 Upgrading ${contractToUpgrade}...\n`);

  let proxyAddress;
  let ContractFactory;

  switch (contractToUpgrade) {
    case "PricingManager":
      proxyAddress = contracts.pricingManager.proxy;
      ContractFactory = await ethers.getContractFactory("PricingManagerUpgradeable");
      break;
    case "Treasury":
      proxyAddress = contracts.treasury.proxy;
      ContractFactory = await ethers.getContractFactory("TreasuryUpgradeable");
      break;
    case "VIPMembership":
      proxyAddress = contracts.vipMembership.proxy;
      ContractFactory = await ethers.getContractFactory("VIPMembershipUpgradeable");
      break;
    case "BatchManager":
      proxyAddress = contracts.batchManager.proxy;
      ContractFactory = await ethers.getContractFactory("BatchManagerUpgradeable");
      break;
    default:
      console.error("❌ Invalid contract name");
      process.exit(1);
  }

  console.log("Proxy Address:", proxyAddress);
  console.log("Validating upgrade...");

  // Validate the upgrade
  try {
    await upgrades.validateUpgrade(proxyAddress, ContractFactory);
    console.log("✅ Upgrade validation passed");
  } catch (error) {
    console.error("❌ Upgrade validation failed:", error.message);
    process.exit(1);
  }

  // Perform the upgrade
  console.log("\nPerforming upgrade...");
  const upgraded = await upgrades.upgradeProxy(proxyAddress, ContractFactory);
  await upgraded.deployed();

  // Get new implementation address
  const newImplementation = await upgrades.erc1967.getImplementationAddress(proxyAddress);
  console.log("✅ Upgrade complete!");
  console.log("   Proxy Address:", proxyAddress);
  console.log("   New Implementation:", newImplementation);

  // Update deployment file
  const contractKey = contractToUpgrade.charAt(0).toLowerCase() + contractToUpgrade.slice(1);
  deploymentData.upgradeable[contractKey].implementation = newImplementation;
  deploymentData.upgradeable[contractKey].lastUpgraded = new Date().toISOString();

  // Save updated deployment data
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const filename = `upgradeable-${deploymentData.network}-${timestamp}.json`;
  const filepath = path.join(deploymentsDir, filename);

  fs.writeFileSync(filepath, JSON.stringify(deploymentData, null, 2));
  fs.writeFileSync(latestFile, JSON.stringify(deploymentData, null, 2));

  console.log("\n📄 Updated deployment file saved");

  console.log("\n" + "=".repeat(80));
  console.log("🎉 UPGRADE COMPLETE!");
  console.log("=".repeat(80));
  console.log("\n⚠️  IMPORTANT: Test the upgraded contract thoroughly!");
  console.log("   - Check that old data is still accessible");
  console.log("   - Verify new functions work correctly");
  console.log("   - Test on testnet before mainnet upgrade");
  console.log();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Upgrade failed:", error);
    process.exit(1);
  });

