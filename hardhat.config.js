require("dotenv").config();

require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require("hardhat-gas-reporter");
// require("solidity-coverage");
require('@openzeppelin/hardhat-upgrades');


// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
let hardhat = {}
if ( process.env.IN_FORK === 'true' ) {
  hardhat = {
    throwOnTransactionFailures: true,
    throwOnCallFailures: true,
    allowUnlimitedContractSize: true,
    forking: {
      url: process.env.BSC_RPC, // 全节点
      blockNumber: 18905774 
    },
    // mining: {
    //   auto: true,
    //   interval: 3000
    // }
  }
}
module.exports = {
  mocha: {
    timeout: 2000000000
  },
  networks: {
    rinkeby: {
      url: `https://eth-rinkeby.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
      accounts: {
        mnemonic: process.env.MNEMONIC,
        // count: 100
      },
      chainId: 4,
      live: true,
      saveDeployments: true,
      tags: ["staging"],
    },
    bsc: {
      url: "https://bsc-dataseed2.defibit.io",
      accounts: {
        mnemonic: process.env.MNEMONIC,
        // count: 100
      },
      chainId: 56
    },
    dev: {
      url: "http://localhost:8545",
      // accounts: [process.env.PRIVATE_KEY],
      chainId: 31337
    },
    hardhat,
  },

  
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  solidity: {
    compilers: [
      {
        version: "0.8.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: '0.8.0',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      }
    ]
  },
};
