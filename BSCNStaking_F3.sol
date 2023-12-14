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

constructor(address _nftCollection, address _rewardToken, address _owner) Ownable(_owner) payable {
    nftCollection = IERC721(_nftCollection);
    rewardToken = IERC20(_rewardToken);
}

    function recoverTokens(address _token) external onlyOwner {
        uint256 bal = IERC20(_token).balanceOf(address(this));
        require(bal > 0, "Staking: No tokens to recover");
        if (_token == address(rewardToken)) {
            require(block.timestamp > periodFinish, "Staking: Period not finished");
        }
        IERC20(_token).safeTransfer(msg.sender, bal);
    }

    function stake(uint256[] memory tokenIds) external updateReward(msg.sender) {
        uint256 amount = tokenIds.length;
        require(amount != 0, "Staking: No tokenIds provided");
        if (currentStakingStatus != Status.OPEN) {
            revert StakingClosed();
        }

        for (uint256 i = 0; i < amount; ++i) {
            uint256 tokenId = tokenIds[i];
            tokensStaked[msg.sender].push(tokenId);
            uint256 tokenLen = tokensStaked[msg.sender].length;
            nftCollection.safeTransferFrom(msg.sender, address(this), tokenId);

            stakedAssets[tokenId] = msg.sender;
            tokenIdToIndex[tokenId] = tokenLen - 1;
        }
        totalStakedSupply = totalStakedSupply + amount;

        emit Staked(msg.sender, tokenIds);
    }

    function withdraw(uint256[] memory tokenIds) external nonReentrant updateReward(msg.sender) {
        uint256 amount = tokenIds.length;
        require(amount != 0, "Staking: No tokenIds provided");

        for (uint256 i = 0; i < amount; ++i) {
            uint256 tokenId = tokenIds[i];
            require(stakedAssets[tokenId] == msg.sender, "Staking: Not the staker of the token");

            nftCollection.safeTransferFrom(address(this), msg.sender, tokenId);

            stakedAssets[tokenId] = address(0);

            uint256[] storage userTokens = tokensStaked[msg.sender];

            uint256 index = tokenIdToIndex[tokenId];

            uint256 lastTokenIdIndex = userTokens.length - 1;
            if (index != lastTokenIdIndex) {
                uint256 lastTokenId = userTokens[lastTokenIdIndex];
                userTokens[index] = lastTokenId;
                tokenIdToIndex[lastTokenId] = index;
            }
            userTokens.pop();
            delete tokenIdToIndex[tokenId];
        }
        totalStakedSupply = totalStakedSupply - amount;

        emit Withdrawn(msg.sender, tokenIds);
    }

    function claimRewards() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        require(rewardToken.balanceOf(address(this)) >= reward, "Staking: Not enough balance");
        if (reward != 0) {
            rewards[msg.sender] = 0;

            rewardToken.safeTransfer(msg.sender, reward);

            emit RewardPaid(msg.sender, reward);
        } else {
            return;
        }
    }

    function withdrawAll() external {
        uint256[] memory toWithdraw = tokensStaked[msg.sender];
        uint256 amount = toWithdraw.length;
        require(amount != 0, "Staking: No tokens staked");

        for (uint256 i = 0; i < amount; i += 1) {
            uint256 tokenId = toWithdraw[i];
            require(stakedAssets[tokenId] == msg.sender, "Staking: Not the staker of the token");

            nftCollection.safeTransferFrom(address(this), msg.sender, tokenId);

            stakedAssets[tokenId] = address(0);

            uint256[] storage userTokens = tokensStaked[msg.sender];

            uint256 index = tokenIdToIndex[tokenId];

            uint256 lastTokenIdIndex = userTokens.length - 1;
            if (index != lastTokenIdIndex) {
                uint256 lastTokenId = userTokens[lastTokenIdIndex];
                userTokens[index] = lastTokenId;
                tokenIdToIndex[lastTokenId] = index;
            }
            userTokens.pop();
            delete tokenIdToIndex[tokenId];
        }
        totalStakedSupply -= amount;
        claimRewards();

        emit Withdrawn(msg.sender, toWithdraw);
    }

    function userStakedTokens(address _user) public view returns (uint256[] memory _tokensStaked) {
        _tokensStaked = tokensStaked[_user];
    }

    function userStakeRewards(address _user) public view returns (uint256 _availableRewards) {
        _availableRewards = calculateRewards(_user);
    }

    function getRewardPerToken() external view returns (uint256 _rewardPerToken) {
        return rewardRate / totalStakedSupply;
    }

    function startStakingPeriod(uint256 _amount, uint256 _duration) external onlyOwner {
        require(_amount != 0, "Staking: Amount must > 0");
        require(_duration != 0, "Staking: Duration must > 0");
        uint256 endOfPeriod = periodFinish;
        require(block.timestamp > endOfPeriod, "Staking: Period not finished");

        rewardsDuration = _duration;

        emit RewardsDurationUpdated(_duration);

        rewardRate = _amount / _duration;

        uint256 balance = rewardToken.balanceOf(address(this));
        require(rewardRate <= balance / _duration, "Staking: Reward too high");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + _duration;
        currentStakingStatus = Status.OPEN;

        emit RewardAdded(_amount);
    }

    /// @notice function for the Owner of the Contract to end the Staking period early
    function endStakingPeriodEarly() external onlyOwner {
        require(block.timestamp < periodFinish, "Staking: Period already finished");
        periodFinish = block.timestamp;
        currentStakingStatus = Status.CLOSED;
        emit StakingPeriodEndedEarly();
    }

    function lastTimeRewardApplicable() public view returns (uint256 _lastRewardsApplicable) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        uint256 reward = rewardPerTokenStored;
        if (totalStakedSupply == 0) {
            return reward;
        }
        return reward + (((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / totalStakedSupply);
    }

    function calculateRewards(address _user) public view returns (uint256 _rewards) {
        return
            ((tokensStaked[_user].length * (rewardPerToken() - userRewardPerTokenPaid[_user])) / 1e18) + rewards[_user];
    }

    function getRewardForDuration() external view returns (uint256 _distributedTokens) {
        return rewardRate * rewardsDuration;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = calculateRewards(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        if (block.timestamp > periodFinish) {
            currentStakingStatus = Status.CLOSED;
        }
        _;
    }

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256[] tokenIds);
    event Withdrawn(address indexed user, uint256[] tokenIds);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event StakingPeriodEndedEarly();
}
