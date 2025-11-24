const { ethers } = require("hardhat");

async function main() {
    try {
        console.log("Iniciando deploy...");
        const ReceivableToken = await ethers.getContractFactory("ReceivableToken");
        const receivableToken = await ReceivableToken.deploy();
        await receivableToken.waitForDeployment();
        console.log("ReceivableToken deployed to:", await receivableToken.getAddress());

        const [owner, pme] = await ethers.getSigners();
        console.log("Owner:", owner.address);
        console.log("PME:", pme.address);

        const maturityDate = Math.floor(Date.now() / 1000) + 90 * 24 * 60 * 60;
        console.log("Tokenizing receivable...");
        const tx = await receivableToken.tokenizeReceivable(
            "REC-TEST-001",
            pme.address,
            100000000,
            97000000,
            maturityDate,
            180,
            "12345678000190",
            "B"
        );
        await tx.wait();
        console.log("Tokenized successfully.");

        const pmeTokens = await receivableToken.getPMEReceivables(pme.address);
        console.log("PME Tokens count:", pmeTokens.length);

    } catch (error) {
        console.error("Erro:", error);
        process.exit(1);
    }
}

main();
