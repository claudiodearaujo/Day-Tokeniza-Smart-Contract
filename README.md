# Day Tokeniza — Receivables Tokenization PoC

Experimental smart-contract proof of concept for representing and managing receivables on-chain.

The project explores how a financial workflow can be modeled with **Solidity, ERC-20 primitives, explicit receivable metadata and controlled settlement states**.

> This repository is an experimental proof of concept. It is not production financial infrastructure and has not been presented as an audited smart-contract system.

## What this project demonstrates

The core contract, `ReceivableToken.sol`, models a receivable lifecycle with:

- tokenization of a receivable;
- ERC-20 minting;
- on-chain metadata for each receivable;
- controlled token transfers;
- maturity and settlement state;
- default state;
- pause controls;
- ownership restrictions;
- reentrancy protection;
- emitted events for lifecycle changes.

## Architecture boundary

The PoC deliberately separates on-chain and off-chain responsibilities.

```text
Business / Backoffice
        ↓
Receivable validation
        ↓
Smart Contract
        ↓
Token lifecycle + state
        ↓
Investors / holders

Settlement distribution
and broader financial controls
remain off-chain in the MVP
```

The contract records and enforces important lifecycle state, while the broader financial process remains an application responsibility.

## Stack

- Solidity `0.8.20`
- Hardhat
- OpenZeppelin Contracts
- Ethers.js
- Chai
- TypeChain
- Solidity Coverage

## Main contract

`contracts/ReceivableToken.sol`

Key concepts represented in the contract include:

- receivable ID;
- PME wallet;
- original amount;
- tokenized amount;
- maturity date;
- discount rate;
- payer identifier;
- rating;
- settled/default state.

## Local development

```bash
npm install
npx hardhat compile
npx hardhat test
```

Deploy script:

```bash
npm run deploy
```

Network configuration and private keys should be supplied through environment variables. Never commit private keys.

## What I wanted to explore

This project was created to study the intersection of:

- financial-system architecture;
- tokenization;
- smart contracts;
- lifecycle modeling;
- on-chain/off-chain boundaries;
- governance and operational risk.

The interesting engineering question is not simply “can this be put on a blockchain?”, but **which responsibilities belong on-chain and which should remain in controlled application infrastructure**.

## Related

- [Interactive tokenization presentation](https://github.com/claudiodearaujo/Apresenta-o)
- [Cláudio Araújo](https://claudiodearaujo.dev.br)

---

Experimental engineering work focused on architecture and system design, not production financial advice or infrastructure.
