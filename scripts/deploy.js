const hre = require("hardhat");
const fs = require("fs");

async function main() {
    console.log("Deploying ReceivableToken...");

    const ReceivableToken = await hre.ethers.getContractFactory("ReceivableToken");
    const receivableToken = await ReceivableToken.deploy();

    await receivableToken.waitForDeployment();

    const address = await receivableToken.getAddress();
    console.log("ReceivableToken deployed to:", address);

    // Salvar endereço para o backend
    const addresses = {
        receivableToken: address,
        network: hre.network.name,
        deployedAt: new Date().toISOString()
    };

    // Ensure backend directory exists
    const backendDir = '../Day-Tokeniza-Back-End';
    if (!fs.existsSync(backendDir)) {
        console.warn("Backend directory not found, skipping address save.");
        return;
    }

    fs.writeFileSync(
        '../Day-Tokeniza-Back-End/contract-addresses.json',
        JSON.stringify(addresses, null, 2)
    );

    console.log("Contract address saved to ../Day-Tokeniza-Back-End/contract-addresses.json");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
