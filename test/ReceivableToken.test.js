const { expect } = require("chai");
const { ethers, network } = require("hardhat");

describe("ReceivableToken", function () {
    let receivableToken;
    let owner, pme, investor1, investor2;

    beforeEach(async function () {
        [owner, pme, investor1, investor2] = await ethers.getSigners();

        const ReceivableToken = await ethers.getContractFactory("ReceivableToken");
        receivableToken = await ReceivableToken.deploy();
        await receivableToken.waitForDeployment();
    });

    it("Should tokenize a receivable", async function () {
        const maturityDate = Math.floor(Date.now() / 1000) + 90 * 24 * 60 * 60; // 90 dias

        const tx = await receivableToken.tokenizeReceivable(
            "REC-001",
            pme.address,
            100000000, // R$ 1.000.000,00 em centavos
            97000000,  // R$ 970.000,00 tokenizado
            maturityDate,
            180, // 1.8% a.m.
            "12345678000190",
            "B"
        );

        await tx.wait();

        const pmeTokens = await receivableToken.getPMEReceivables(pme.address);
        expect(pmeTokens.length).to.equal(1);
    });

    it("Should transfer tokens between investors", async function () {
        // Primeiro tokenizar
        const maturityDate = Math.floor(Date.now() / 1000) + 90 * 24 * 60 * 60;
        const tx = await receivableToken.tokenizeReceivable(
            "REC-002",
            pme.address,
            50000000,
            48500000,
            maturityDate,
            150,
            "12345678000190",
            "A"
        );
        await tx.wait();

        // PME transfere para investor1
        const pmeTokens = await receivableToken.getPMEReceivables(pme.address);
        const tokenId = pmeTokens[0];

        await receivableToken.connect(pme).transferReceivableTokens(
            tokenId,
            investor1.address,
            48500000
        );

        const investor1Tokens = await receivableToken.getInvestorTokens(investor1.address);
        expect(investor1Tokens.length).to.equal(1);
    });

    it("Should settle receivable after maturity", async function () {
        const block = await ethers.provider.getBlock('latest');
        const maturityDate = block.timestamp + 10; // 10 segundos no futuro

        const tx = await receivableToken.tokenizeReceivable(
            "REC-003",
            pme.address,
            20000000,
            19500000,
            maturityDate,
            200,
            "12345678000190",
            "C"
        );
        await tx.wait();

        const pmeTokens = await receivableToken.getPMEReceivables(pme.address);
        const tokenId = pmeTokens[0];

        // Esperar vencimento
        await network.provider.send("evm_increaseTime", [15]);
        await network.provider.send("evm_mine");

        // Liquidar
        await receivableToken.settleReceivable(tokenId);

        const details = await receivableToken.getReceivableDetails(tokenId);
        expect(details.isSettled).to.equal(true);
    });
});
