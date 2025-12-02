const { ethers } = require("hardhat");

async function main() {
  console.log("Deploying dummy contract...");

  // Dummy contract for testing
  const Dummy = await ethers.getContractFactory("Dummy");
  const dummy = await Dummy.deploy();

  await dummy.waitForDeployment();

  console.log("Dummy deployed to:", await dummy.getAddress());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });