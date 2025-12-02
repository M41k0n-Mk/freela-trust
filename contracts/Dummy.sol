// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Dummy Contract
 * @dev Contrato simples para teste de deploy e funcionalidades básicas.
 * Este contrato é usado apenas para validar o setup do ambiente de desenvolvimento.
 */
contract Dummy {
    uint256 public value;

    /**
     * @dev Construtor que inicializa o valor padrão.
     */
    constructor() {
        value = 42;
    }

    /**
     * @dev Define um novo valor.
     * @param _value O novo valor a ser definido.
     */
    function setValue(uint256 _value) public {
        value = _value;
    }
}