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
