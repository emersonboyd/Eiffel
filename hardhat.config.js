// hardhat.config.js
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-waffle");
let secret = require('./secrets.json');

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

module.exports = {
  solidity: "0.8.11",

  // do not set a default network, or that will mess up unit tests
  networks: {
    moralisBscTestnet: {
      url: secret.moralisBscTestnetUrl,
      accounts: [secret.key],
    },
    moralisBscMainnet: {
      url: secret.moralisBscMainnetUrl,
      accounts: [secret.key],
    },
    moralisRinkeby: {
      url: secret.moralisRinkebyUrl,
      accounts: [secret.key],
    },
    harmonyTestnet: {
      url: secret.harmonyTestnetUrl,
      accounts: [secret.key],
    },
    harmonyMainnet: {
      url: secret.harmonyMainnetUrl,
      accounts: [secret.key],
    },
  }
};
