require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  // Configuração da versão do Solidity
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200, // Número de execuções para otimização
      },
    },
  },
  // Configuração das redes
  networks: {
    // Rede local para desenvolvimento
    localhost: {
      url: "http://127.0.0.1:8545",
    },
    // Adicionar outras redes conforme necessário (ex: sepolia, mainnet)
  },
  // Caminhos dos arquivos
  paths: {
    sources: "./contracts", // Contratos Solidity
    tests: "./test", // Arquivos de teste
    cache: "./cache", // Cache do Hardhat
    artifacts: "./artifacts", // Artefatos de compilação
  },
};