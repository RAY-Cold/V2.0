const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with:", deployer.address);

  const Factory = await hre.ethers.getContractFactory("TourSecureDigitalID");
  const contract = await Factory.deploy(deployer.address); // constructor initialOwner
  await contract.deployed();

  console.log("TourSecureDigitalID deployed to:", contract.address);
}

main().catch((e) => { console.error(e); process.exit(1); });
