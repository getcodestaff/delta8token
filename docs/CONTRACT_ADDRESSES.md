# Contract Addresses

## Polygon Mainnet (Chain ID: 137)

### Core Contracts

| Contract | Address | Verified |
|----------|---------|----------|
| **DELTA8 Token** | `0x2612c0fAA69ACfA78e5318A03D86109D765BAf20` | ✅ |
| **VIP Staking** | `0x4700455DAF96dAc11B8d5Eed706062dCD7A338dE` | ✅ |
| **Pricing Manager** | `0xB08171B43c6e1633ba66D0aCb2d19cc8bD865F43` | ✅ |
| **Treasury** | `0x68DCcac967E91Fc0e37F8089F7164Dce9C82f79e` | ✅ |

### Contract Details

#### DELTA8 Token
- **Address**: `0x2612c0fAA69ACfA78e5318A03D86109D765BAf20`
- **Type**: ERC-20 Upgradeable
- **Symbol**: DELTA8
- **Decimals**: 18
- **PolygonScan**: [View Contract](https://polygonscan.com/address/0x2612c0fAA69ACfA78e5318A03D86109D765BAf20)

#### VIP Staking Contract
- **Address**: `0x4700455DAF96dAc11B8d5Eed706062dCD7A338dE`
- **Type**: Upgradeable Staking
- **Features**: Tiered membership, dynamic rewards
- **PolygonScan**: [View Contract](https://polygonscan.com/address/0x4700455DAF96dAc11B8d5Eed706062dCD7A338dE)

#### Pricing Manager
- **Address**: `0xB08171B43c6e1633ba66D0aCb2d19cc8bD865F43`
- **Type**: Upgradeable Oracle
- **Features**: Dynamic pricing for token redemptions
- **PolygonScan**: [View Contract](https://polygonscan.com/address/0xB08171B43c6e1633ba66D0aCb2d19cc8bD865F43)

#### Treasury
- **Address**: `0x68DCcac967E91Fc0e37F8089F7164Dce9C82f79e`
- **Type**: Multi-signature Wallet
- **Features**: Secure fund management
- **PolygonScan**: [View Contract](https://polygonscan.com/address/0x68DCcac967E91Fc0e37F8089F7164Dce9C82f79e)

---

## Polygon Amoy Testnet (Chain ID: 80002)

Testnet deployment addresses will be listed here when available.

---

## Verification

All mainnet contracts are verified on PolygonScan and available for public audit:

1. Visit [PolygonScan](https://polygonscan.com)
2. Search for any contract address above
3. View the "Contract" tab to see verified source code
4. Review the "Read Contract" and "Write Contract" tabs for interaction

## Deployment History

- **Initial Deployment**: October 2024
- **Network**: Polygon Mainnet
- **Deployer**: Multi-sig controlled deployment

## Security Notes

- All contracts use OpenZeppelin's upgradeable contract patterns
- Transparent proxy pattern for upgradeability
- Role-based access control (RBAC)
- Emergency pause functionality
- Multi-signature requirements for critical operations

---

**Last Updated**: October 16, 2024

