import hre from 'hardhat'

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  const factory = await hre.ethers.deployContract("contracts/InscriptionFactory.sol:InscriptionFactory");

  console.log("factory address:", await factory.getAddress());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
});
