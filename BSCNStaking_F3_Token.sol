// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract BSCN_F3_Staking is ERC20 {
    constructor() ERC20("BSCNF3Staking", "BSCNF3") {
        _mint(msg.sender, 350000 * 10 ** decimals());
    }
}
