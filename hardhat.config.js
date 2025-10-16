require("@nomicfoundation/hardhat-toolbox");
require("@openzeppelin/hardhat-upgrades");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      viaIR: true
    }
  },
  networks: {
    hardhat: {
      chainId: 1337,
      forking: process.env.FORK_MAINNET ? {
        url: process.env.POLYGON_RPC_URL || "https://polygon-rpc.com"
      } : undefined
    },
    mumbai: {
      url: process.env.MUMBAI_RPC_URL || "https://polygon-mumbai.g.alchemy.com/v2/demo",
      accounts: (process.env.PRIVATE_KEY && process.env.PRIVATE_KEY.length === 64) ? [process.env.PRIVATE_KEY] : ["0000000000000000000000000000000000000000000000000000000000000001"],
      chainId: 80001,
      gasPrice: 20000000000, // 20 gwei
      timeout: 60000
    },
    amoy: {
      url: process.env.AMOY_RPC_URL || "https://rpc-amoy.polygon.technology",
      accounts: (process.env.PRIVATE_KEY && process.env.PRIVATE_KEY.length === 64) ? [process.env.PRIVATE_KEY] : ["0000000000000000000000000000000000000000000000000000000000000001"],
      chainId: 80002,
      gasPrice: 30000000000, // 30 gwei (Amoy minimum)
      timeout: 60000
    },
    polygon: {
      url: process.env.POLYGON_RPC_URL || "https://polygon-rpc.com",
      accounts: (process.env.PRIVATE_KEY && process.env.PRIVATE_KEY.length === 64) ? [process.env.PRIVATE_KEY] : ["0000000000000000000000000000000000000000000000000000000000000001"],
      chainId: 137,
      gasPrice: 50000000000, // 50 gwei
      timeout: 60000
    }
  },
  etherscan: {
    apiKey: {
      polygon: process.env.POLYGONSCAN_API_KEY || "",
      polygonMumbai: process.env.POLYGONSCAN_API_KEY || ""
    }
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  mocha: {
    timeout: 40000
  }
};
