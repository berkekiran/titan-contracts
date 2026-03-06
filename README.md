<p align="center">
  <img src="https://raw.githubusercontent.com/berkekiran/titan-app/main/public/titan-app.png" alt="Titan" width="200" />
</p>

<p align="center">
  Smart contracts for Titan DeFi protocol with Uniswap V4 integration.
</p>

<p align="center">
  <a href="https://titandefi.org"><img src="https://img.shields.io/badge/app-titandefi.org-blue" alt="Live App" /></a>
  <a href="https://book.getfoundry.sh/"><img src="https://img.shields.io/badge/Foundry-1C1C1C?logo=ethereum&logoColor=white" alt="Foundry" /></a>
  <a href="https://soliditylang.org/"><img src="https://img.shields.io/badge/Solidity-363636?logo=solidity&logoColor=white" alt="Solidity" /></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT" /></a>
</p>

## Contracts

- **TitanToken** - ERC-20 token with 100M supply
- **Earn** - Deposit ETH, earn TITAN rewards
- **StakedTitan** - Stake TITAN, receive sTITAN
- **Farm** - Yield farming with multiple pools
- **Governor** - On-chain governance
- **Faucet** - Testnet token distribution
- **SwapRouter** - Uniswap V4 swap integration
- **LiquidityRouter** - Uniswap V4 liquidity management

## Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Solidity 0.8.26+

## Installation

```bash
git clone https://github.com/berkekiran/titan-contracts.git
cd titan-contracts
forge install
```

## Build

```bash
forge build
```

## Test

```bash
forge test
forge test -vvv          # Verbose
forge test --gas-report  # Gas reporting
forge coverage           # Coverage
```

## Deployment

Create `.env` file:

```env
PRIVATE_KEY=your_private_key
SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
```

Deploy:

```bash
source .env
forge script script/DeployV4.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast
```

## Network

Contracts are deployed on **Ethereum Sepolia** testnet.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contact

Project Link: [https://github.com/berkekiran/titan-contracts](https://github.com/berkekiran/titan-contracts)
