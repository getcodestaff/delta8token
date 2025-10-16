# DELTA8 Token - Loyalty & Membership Protocol

**Utility token powering transparent loyalty programs on Polygon blockchain.**

## 🏗️ Deployed Contracts

| Contract | Address | Description |
|----------|---------|-------------|
| **DELTA8 Token** | `0x2612c0fAA69ACfA78e5318A03D86109D765BAf20` | Main ERC-20 utility token |
| **VIP Staking** | `0x4700455DAF96dAc11B8d5Eed706062dCD7A338dE` | Dynamic membership staking |
| **Pricing Manager** | `0xB08171B43c6e1633ba66D0aCb2d19cc8bD865F43` | Dynamic redemption pricing |
| **Treasury** | `0x68DCcac967E91Fc0e37F8089F7164Dce9C82f79e` | Multi-sig fund management |

**Network:** Polygon Mainnet  
**Chain ID:** 137

## 📋 Overview

DELTA8 is a utility token designed to create transparent, blockchain-based loyalty and membership programs. The protocol enables:

- **Token-Based Loyalty**: Earn and redeem tokens for real-world products
- **VIP Membership Tiers**: Stake tokens to unlock membership benefits
- **Dynamic Pricing**: Fair market-based redemption rates
- **Transparent Treasury**: Multi-signature wallet for fund security

## 🛠️ Development

### Prerequisites

```bash
node >= 16.x
npm >= 8.x
```

### Installation

```bash
npm install
```

### Compile Contracts

```bash
npx hardhat compile
```

### Run Tests

```bash
npx hardhat test
```

### Deploy to Testnet (Polygon Amoy)

```bash
npx hardhat run scripts/deployUpgradeable.js --network amoy
```

## 📁 Repository Structure

```
delta8token/
├── contracts/              # Smart contract source files
│   ├── Delta8TokenUpgradeable.sol
│   ├── VIPStakingUpgradeable.sol
│   ├── PricingManagerUpgradeable.sol
│   └── BatchManagerUpgradeable.sol
├── scripts/               # Deployment and utility scripts
│   ├── deployUpgradeable.js
│   └── upgradeVIPStaking.js
├── test/                  # Contract test suites
│   └── upgradeable.test.js
└── docs/                  # Documentation
    └── CONTRACT_ADDRESSES.md
```

## 🔍 Contract Details

### DELTA8 Token
- **Type**: ERC-20 Upgradeable
- **Features**: Pausable, burnable, role-based access control
- **Total Supply**: Variable based on minting
- **Verified Contract**: [View on PolygonScan](https://polygonscan.com/address/0x2612c0fAA69ACfA78e5318A03D86109D765BAf20)

### VIP Staking
- **Type**: Upgradeable staking contract
- **Features**: Tiered membership, dynamic benefits
- **Verified Contract**: [View on PolygonScan](https://polygonscan.com/address/0x4700455DAF96dAc11B8d5Eed706062dCD7A338dE)

### Pricing Manager
- **Type**: Upgradeable pricing oracle
- **Features**: Dynamic token redemption rates
- **Verified Contract**: [View on PolygonScan](https://polygonscan.com/address/0xB08171B43c6e1633ba66D0aCb2d19cc8bD865F43)

## 🌐 Networks

### Polygon Mainnet (Production)
- **RPC**: https://polygon-rpc.com
- **Chain ID**: 137
- **Explorer**: https://polygonscan.com

### Polygon Amoy (Testnet)
- **RPC**: https://rpc-amoy.polygon.technology
- **Chain ID**: 80002
- **Explorer**: https://amoy.polygonscan.com

## 🔐 Security

- All contracts are upgradeable using OpenZeppelin's transparent proxy pattern
- Multi-signature wallet controls for treasury operations
- Role-based access control for administrative functions
- Pausable functionality for emergency situations

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details

## 🔗 Links

- **Website**: [Coming Soon]
- **Documentation**: See [docs/](docs/) folder
- **PolygonScan**: [Token Contract](https://polygonscan.com/address/0x2612c0fAA69ACfA78e5318A03D86109D765BAf20)

## 📞 Support

For questions and support, please open an issue in this repository.

---

**Built with ❤️ on Polygon**

