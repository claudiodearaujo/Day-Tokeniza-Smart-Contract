# PROJETO: Daycoval Tokeniza - Smart Contract

Crie um smart contract em Solidity para tokenização de recebíveis. O contrato deve permitir mint de tokens (PME tokeniza), transfer (investidor compra) e settlement (pagamento no vencimento).

## ESPECIFICAÇÃO TÉCNICA
- Solidity ^0.8.20
- Standard: ERC-1400 (Security Token)
- Network: Polygon (Mumbai testnet para dev)
- Ownable (só Daycoval pode fazer certas operações)
- Pausable (emergency stop)
- ReentrancyGuard (segurança)

## ARQUIVO: ReceivableToken.sol
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1400/ERC1400.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title ReceivableToken
 * @dev Contrato para tokenização de recebíveis de PMEs
 * 
 * Funcionalidades:
 * - Mint de tokens (PME tokeniza recebível)
 * - Transfer entre investidores (mercado secundário)
 * - Settlement no vencimento (pagamento automatizado)
 * - Metadata do recebível on-chain
 */
contract ReceivableToken is ERC1400, Ownable, Pausable, ReentrancyGuard {
    
    // Estrutura de dados do recebível
    struct Receivable {
        string receivableId;       // ID no backend
        address pmeAddress;        // Endereço wallet da PME
        uint256 originalAmount;    // Valor original em centavos (BRL)
        uint256 tokenizedAmount;   // Valor tokenizado
        uint256 maturityDate;      // Data vencimento (timestamp)
        uint256 discountRate;      // Taxa desconto (basis points: 180 = 1.8%)
        string sacadoCNPJ;         // CNPJ do pagador
        string rating;             // Rating: A, B, C, D
        bool isSettled;            // Se já foi pago
        bool isDefaulted;          // Se entrou em default
    }
    
    // Storage
    mapping(bytes32 => Receivable) public receivables;  // tokenId => Receivable
    mapping(address => bytes32[]) public pmeReceivables; // PME => seus tokens
    mapping(address => bytes32[]) public investorTokens; // Investor => seus tokens
    
    uint256 public totalReceivablesTokenized;
    uint256 public totalValueLocked;
    
    // Events
    event ReceivableTokenized(
        bytes32 indexed tokenId,
        string receivableId,
        address indexed pmeAddress,
        uint256 amount,
        uint256 maturityDate
    );
    
    event TokenTransferred(
        bytes32 indexed tokenId,
        address indexed from,
        address indexed to,
        uint256 amount
    );
    
    event ReceivableSettled(
        bytes32 indexed tokenId,
        uint256 settledAmount,
        uint256 timestamp
    );
    
    event ReceivableDefaulted(
        bytes32 indexed tokenId,
        uint256 timestamp
    );
    
    constructor() ERC1400("Daycoval Receivable Token", "DRT", new address ) Ownable(msg.sender) {
        // Partition padrão
        _defaultPartitions.push(bytes32("default"));
    }
    
    /**
     * @dev Tokeniza um recebível (mint de novos tokens)
     * @param _receivableId ID do recebível no backend
     * @param _pmeAddress Endereço da PME
     * @param _originalAmount Valor original
     * @param _tokenizedAmount Valor após desconto
     * @param _maturityDate Data de vencimento
     * @param _discountRate Taxa de desconto (basis points)
     * @param _sacadoCNPJ CNPJ do pagador
     * @param _rating Rating do recebível
     */
    function tokenizeReceivable(
        string memory _receivableId,
        address _pmeAddress,
        uint256 _originalAmount,
        uint256 _tokenizedAmount,
        uint256 _maturityDate,
        uint256 _discountRate,
        string memory _sacadoCNPJ,
        string memory _rating
    ) external onlyOwner whenNotPaused returns (bytes32) {
        require(_pmeAddress != address(0), "Invalid PME address");
        require(_originalAmount > 0, "Amount must be positive");
        require(_maturityDate > block.timestamp, "Maturity date must be in future");
        require(_tokenizedAmount <= _originalAmount, "Tokenized amount exceeds original");
        
        // Gerar tokenId único
        bytes32 tokenId = keccak256(
            abi.encodePacked(
                _receivableId,
                _pmeAddress,
                block.timestamp,
                totalReceivablesTokenized
            )
        );
        
        // Criar recebível
        receivables[tokenId] = Receivable({
            receivableId: _receivableId,
            pmeAddress: _pmeAddress,
            originalAmount: _originalAmount,
            tokenizedAmount: _tokenizedAmount,
            maturityDate: _maturityDate,
            discountRate: _discountRate,
            sacadoCNPJ: _sacadoCNPJ,
            rating: _rating,
            isSettled: false,
            isDefaulted: false
        });
        
        // Mintar tokens para PME (partition padrão)
        _issue(_pmeAddress, _tokenizedAmount, bytes32("default"), "");
        
        // Registrar
        pmeReceivables[_pmeAddress].push(tokenId);
        totalReceivablesTokenized++;
        totalValueLocked += _tokenizedAmount;
        
        emit ReceivableTokenized(
            tokenId,
            _receivableId,
            _pmeAddress,
            _tokenizedAmount,
            _maturityDate
        );
        
        return tokenId;
    }
    
    /**
     * @dev Transferir tokens (investidor compra)
     * @param _tokenId ID do token
     * @param _to Endereço do comprador
     * @param _amount Quantidade a transferir
     */
    function transferReceivableTokens(
        bytes32 _tokenId,
        address _to,
        uint256 _amount
    ) external whenNotPaused nonReentrant {
        require(_to != address(0), "Invalid recipient");
        require(receivables[_tokenId].pmeAddress != address(0), "Token does not exist");
        require(!receivables[_tokenId].isSettled, "Receivable already settled");
        require(!receivables[_tokenId].isDefaulted, "Receivable defaulted");
        
        // Transferir via ERC1400
        _operatorTransferByPartition(
            bytes32("default"),
            msg.sender,
            msg.sender,
            _to,
            _amount,
            "",
            ""
        );
        
        // Registrar no mapping do investidor
        bool alreadyOwns = false;
        for (uint i = 0; i < investorTokens[_to].length; i++) {
            if (investorTokens[_to][i] == _tokenId) {
                alreadyOwns = true;
                break;
            }
        }
        if (!alreadyOwns) {
            investorTokens[_to].push(_tokenId);
        }
        
        emit TokenTransferred(_tokenId, msg.sender, _to, _amount);
    }
    
    /**
     * @dev Liquidar recebível (pagamento no vencimento)
     * @param _tokenId ID do token
     */
    function settleReceivable(bytes32 _tokenId) external onlyOwner nonReentrant {
        Receivable storage receivable = receivables[_tokenId];
        
        require(receivable.pmeAddress != address(0), "Token does not exist");
        require(!receivable.isSettled, "Already settled");
        require(!receivable.isDefaulted, "Receivable defaulted");
        require(block.timestamp >= receivable.maturityDate, "Not matured yet");
        
        // Marcar como liquidado
        receivable.isSettled = true;
        
        // Aqui seria a lógica de distribuição de pagamento para holders
        // No MVP, apenas marcamos como settled e backend processa off-chain
        
        emit ReceivableSettled(_tokenId, receivable.originalAmount, block.timestamp);
    }
    
    /**
     * @dev Marcar recebível como inadimplente
     * @param _tokenId ID do token
     */
    function markAsDefaulted(bytes32 _tokenId) external onlyOwner {
        Receivable storage receivable = receivables[_tokenId];
        
        require(receivable.pmeAddress != address(0), "Token does not exist");
        require(!receivable.isSettled, "Already settled");
        require(block.timestamp > receivable.maturityDate + 30 days, "Grace period not over");
        
        receivable.isDefaulted = true;
        
        emit ReceivableDefaulted(_tokenId, block.timestamp);
    }
    
    /**
     * @dev Consultar detalhes de um recebível
     */
    function getReceivableDetails(bytes32 _tokenId) 
        external 
        view 
        returns (
            string memory receivableId,
            address pmeAddress,
            uint256 originalAmount,
            uint256 tokenizedAmount,
            uint256 maturityDate,
            uint256 discountRate,
            string memory rating,
            bool isSettled,
            bool isDefaulted
        ) 
    {
        Receivable memory r = receivables[_tokenId];
        return (
            r.receivableId,
            r.pmeAddress,
            r.originalAmount,
            r.tokenizedAmount,
            r.maturityDate,
            r.discountRate,
            r.rating,
            r.isSettled,
            r.isDefaulted
        );
    }
    
    /**
     * @dev Listar tokens de uma PME
     */
    function getPMEReceivables(address _pmeAddress) 
        external 
        view 
        returns (bytes32[] memory) 
    {
        return pmeReceivables[_pmeAddress];
    }
    
    /**
     * @dev Listar tokens de um investidor
     */
    function getInvestorTokens(address _investorAddress) 
        external 
        view 
        returns (bytes32[] memory) 
    {
        return investorTokens[_investorAddress];
    }
    
    /**
     * @dev Pausar contrato (emergency)
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Despausar contrato
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Calcular retorno esperado
     */
    function calculateExpectedReturn(bytes32 _tokenId, uint256 _investmentAmount)
        external
        view
        returns (uint256)
    {
        Receivable memory r = receivables[_tokenId];
        require(r.pmeAddress != address(0), "Token does not exist");
        
        // Cálculo simplificado: (amount * discountRate * daysToMaturity) / (10000 * 30)
        uint256 daysToMaturity = (r.maturityDate - block.timestamp) / 1 days;
        uint256 returnAmount = (_investmentAmount * r.discountRate * daysToMaturity) / (10000 * 30);
        
        return returnAmount;
    }
}
```

## DEPLOY SCRIPT (scripts/deploy.js)
```javascript
const hre = require("hardhat");

async function main() {
  console.log("Deploying ReceivableToken...");
  
  const ReceivableToken = await hre.ethers.getContractFactory("ReceivableToken");
  const receivableToken = await ReceivableToken.deploy();
  
  await receivableToken.waitForDeployment();
  
  const address = await receivableToken.getAddress();
  console.log("ReceivableToken deployed to:", address);
  
  // Salvar endereço para o backend
  const fs = require('fs');
  const addresses = {
    receivableToken: address,
    network: hre.network.name,
    deployedAt: new Date().toISOString()
  };
  
  fs.writeFileSync(
    '../backend/contract-addresses.json',
    JSON.stringify(addresses, null, 2)
  );
  
  console.log("Contract address saved to backend/contract-addresses.json");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
```

## HARDHAT CONFIG (hardhat.config.js)
```javascript
require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    mumbai: {
      url: process.env.POLYGON_RPC_URL || "https://rpc-mumbai.maticvigil.com",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 80001
    },
    polygon: {
      url: process.env.POLYGON_MAINNET_RPC_URL || "https://polygon-rpc.com",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 137
    }
  },
  etherscan: {
    apiKey: process.env.POLYGONSCAN_API_KEY
  }
};
```

## TESTES (test/ReceivableToken.test.js)
```javascript
const { expect } = require("chai");
const { ethers } = require("hardhat");

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
    const maturityDate = Math.floor(Date.now() / 1000) + 1; // 1 segundo (para teste)
    
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
    await ethers.provider.send("evm_increaseTime", [2]);
    await ethers.provider.send("evm_mine");
    
    // Liquidar
    await receivableToken.settleReceivable(tokenId);
    
    const details = await receivableToken.getReceivableDetails(tokenId);
    expect(details.isSettled).to.equal(true);
  });
});
```

## COMANDOS
```json
{
  "scripts": {
    "compile": "hardhat compile",
    "test": "hardhat test",
    "deploy:mumbai": "hardhat run scripts/deploy.js --network mumbai",
    "deploy:polygon": "hardhat run scripts/deploy.js --network polygon",
    "verify": "hardhat verify --network mumbai"
  }
}
```

## OBSERVAÇÕES
- Usar OpenZeppelin para segurança (ERC1400, Ownable, etc)
- Gas optimization (view functions, storage vs memory)
- Events para cada operação importante (indexing)
- Modifiers para validações (onlyOwner, whenNotPaused)
- Comentários NatSpec para documentação
- Testes cobrem cenários principais (tokenize, transfer, settle)
- Deploy script salva endereço para backend usar

---

GERE O SMART CONTRACT COMPLETO, SEGURO E TESTADO.
USE SOLIDITY BEST PRACTICES E OPENZEPPELIN LIBRARIES.
CONTRATO DEVE SER AUDITÁVEL E GAS-EFFICIENT.