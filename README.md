
# Foundry Starter Kit

This is a custom Foundry starter kit for daily use in smart contract development.

## Usage

### Deploying and Verifying a Contract

1. Source your environment variables:

   ```
   source .env
   ```
2. Run the deployment script:

   ```
   forge script --account dev --chain sepolia script/deployer.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify -vvvv --sender 0x2cf56496f155914d84e6eda6e2c0076aeae5b0f0
   ```

### Verifying an Already Deployed Contract

```
forge verify-contract 0x50c56eb8e5c30992cba712246b72b94968263bb9 TradeDevil --chain sepolia
```

### Common Imports

```solidity
import {Test} from "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";
```
