require('@nomiclabs/hardhat-waffle');
require('@nomiclabs/hardhat-web3');
require('hardhat-deploy');
require('hardhat-abi-exporter');

extendEnvironment(require('./utils/snapshopHelper.js'));

module.exports = {
  solidity: {
    version: '0.8.14',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },

  abiExporter: {
    path: './abi',
    runOnCompile: false,
    clear: true,
    flat: true,
    spacing: 2,
    pretty: false
  }
};
