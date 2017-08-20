var FounderToken = artifacts.require('./FounderToken.sol');
var CrowdsaleController = artifacts.require('./CrowdsaleController.sol');

let startTime = Math.floor(Date.now() / 1000) + 15 * 24 * 60 * 60; // activation hasn't started
let inMinutes = Math.floor(Date.now() / 1000) + 2 * 60; // activation hasn't started
var beneficiary = '0xA86929f2722B1929dcFe935Ad8C3b90ccda411fd';

module.exports = async (deployer) => {
  await deployer.deploy(FounderToken, 'DAB Founder Token', 'DFT', 18);
  await deployer.deploy(CrowdsaleController, FounderToken.address, inMinutes, beneficiary);

  await FounderToken.deployed().then(async (instance) => {
    await instance.transferOwnership(CrowdsaleController.address);
  });

  await CrowdsaleController.deployed().then(async (instance) => {
    await instance.acceptTokenOwnership();
  });

};
