// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BSCN_F3_Staking is ERC20, Ownable {
    constructor(address initialOwner)
        ERC20("BSCN_F3_Staking", "BSCNF3")
        Ownable(initialOwner)
    {
        _mint(msg.sender, 350000 * 10 ** decimals());
    }
}
