// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract BSCNewsNFTStaking is ERC721Holder, ReentrancyGuard, Ownable {
    error StakingClosed();

    using SafeERC20 for IERC20;

    IERC20 public immutable rewardToken;
    IERC721 public immutable nftCollection;

    enum Status {
        OPEN,
        CLOSED
    }

    Status public currentStakingStatus;

    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public rewardsDuration;
    uint256 public lastUpdateTime;
    uint256 private rewardPerTokenStored;
    uint256 public totalStakedSupply;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) private rewards;
    mapping(uint256 => address) public stakedAssets;
    mapping(address => uint256[]) private tokensStaked;
    mapping(uint256 => uint256) public tokenIdToIndex;

    
