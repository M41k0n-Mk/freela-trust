# Freela Trust

Projeto para gerenciar contratos de freela com escrow em blockchain usando Ethereum e Hardhat.

## Pré-requisitos

- Node.js >= 16.0.0
- npm >= 7.0.0

## Instalação

```bash
npm install
```

## Uso

### Compilar contratos

```bash
npm run compile
```

### Executar testes

```bash
npm run test
```

### Iniciar nó local

```bash
npm run node
```

### Deploy local

```bash
npm run deploy-local
```

## Estrutura do projeto

- `contracts/`: Contratos Solidity
- `scripts/`: Scripts de deploy e utilitários
- `test/`: Testes dos contratos
- `artifacts/`: Artefatos de compilação (gerado automaticamente)

## Desenvolvimento

1. Instale as dependências: `npm install`
2. Inicie o nó local: `npm run node`
3. Em outro terminal, compile: `npm run compile`
4. Execute deploy: `npm run deploy-local`

## Licença

MIT
