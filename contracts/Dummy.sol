// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Dummy {
    uint256 public value;

    constructor() {
        value = 42;
    }

    function setValue(uint256 _value) public {
        value = _value;
    }
}