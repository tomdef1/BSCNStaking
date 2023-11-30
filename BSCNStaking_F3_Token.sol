// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BSCN_F3_Staking is ERC20 {
    constructor() ERC20("BSCN_F3_Staking", "BSCNF3") {
        _mint(msg.sender, 350000 * 10 ** decimals());
    }
}
