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

    // Mapping tracks tokens a user has been paid already
    mapping(address user => uint256 token) public userRewardPerTokenPaid;
    mapping(address user => uint256 rewardValue) private rewards;
    // Mapping returns who owns a particular token ID
    mapping(uint256 tokenId => address user) public stakedAssets;
    mapping(address user => uint256[] tokens) private tokensStaked;
    mapping(uint256 tokenId => uint256 tokenIndex) public tokenIdToIndex;

    /// @param _nftCollection the address of the ERC721 Contract
    /// @param _rewardToken the address of the ERC20 token used for rewards
    constructor(address _nftCollection, address _rewardToken) payable {
        nftCollection = IERC721(_nftCollection);
        rewardToken = IERC20(_rewardToken);
    }

    /// @notice Function to recover wrongly sent tokens
    /// @param _token the address of the ERC20 token to recover
    /// @dev Staking period must be over if the tokens are reward tokens
    function recoverTokens(address _token) external onlyOwner {
        uint256 bal = IERC20(_token).balanceOf(address(this));
        require(bal > 0, "Staking: No tokens to recover");
        if (_token == address(rewardToken)) {
            require(block.timestamp > periodFinish, "Staking: Period not finished");
        }
        IERC20(_token).safeTransfer(msg.sender, bal);
    }

    /// @notice functon called by the users to Stake NFTs
    /// @param tokenIds array of Token IDs of the NFTs to be staked
    /// @dev the Token IDs have to be prevoiusly approved for transfer in the
    /// ERC721 contract with the address of this contract
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

    /// @notice function called by the user to Withdraw NFTs from staking
    /// @param tokenIds array of Token IDs of the NFTs to be withdrawn
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

    /// @notice function called by the user to claim his accumulated rewards
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

    /// @notice function called by the user to withdraw all NFTs and claim the rewards in one transaction
    function withdrawAll() external {
        uint256[] memory toWithdraw = tokensStaked[msg.sender];
        uint256 amount = toWithdraw.length;
        require(amount != 0, "Staking: No tokens staked");

        for (uint256 i = 0; i < amount; i += 1) {
            uint256 tokenId = toWithdraw[i];
            // Redundant check??
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

    /// @notice function useful for Front End to see the stake and rewards for users
    /// @param _user the address of the user to get informations for
    /// @return _tokensStaked an array of NFT Token IDs that are staked by the user
    function userStakedTokens(address _user) public view returns (uint256[] memory _tokensStaked) {
        _tokensStaked = tokensStaked[_user];
    }

    /// @notice function useful for Front End to see the stake and rewards for users
    /// @param _user the address of the user to get informations for
    /// @return _availableRewards the rewards accumulated by the user
    function userStakeRewards(address _user) public view returns (uint256 _availableRewards) {
        _availableRewards = calculateRewards(_user);
    }

    /// @notice getter function to get the reward per second for staking one NFT
    /// @return _rewardPerToken the amount of token per second rewarded for staking one NFT
    function getRewardPerToken() external view returns (uint256 _rewardPerToken) {
        return rewardRate / totalStakedSupply;
    }

    /// @notice function for the Owner of the Contract to start a Staking period and set the
    /// amount of ERC20 Tokens to be distributed as rewards in said period
    /// @param _amount the amount of Reward Tokens to be distributed
    /// @param _duration the duration in with the rewards will be distributed, in seconds
    /// @dev  the Staking Contract have to already own enough Rewards Tokens to distribute all the rewards,
    /// so make sure to send all the tokens to the contract before calling this function
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

    /// @return _lastRewardsApplicable the last time the rewards were applicable,
    /// returns block.timestamp if the rewards period is not ended
    function lastTimeRewardApplicable() public view returns (uint256 _lastRewardsApplicable) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /// @notice calculates the rewards per token for the current time whenever a new deposit/withdraw
    /// is made to keep track of the correct token distribution between stakers
    function rewardPerToken() public view returns (uint256) {
        uint256 reward = rewardPerTokenStored;
        if (totalStakedSupply == 0) {
            return reward;
        }
        return reward + (((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / totalStakedSupply);
    }

    /// @notice used to calculate the earned rewards for a user
    /// @param _user the address of the user to calculate available rewards for
    /// @return _rewards the amount of tokens available as rewards for the passed address
    function calculateRewards(address _user) public view returns (uint256 _rewards) {
        return
            ((tokensStaked[_user].length * (rewardPerToken() - userRewardPerTokenPaid[_user])) / 1e18) + rewards[_user];
    }

    /// @return _distributedTokens the total amount of ERC20 Tokens distributed as rewards for the set staking period
    function getRewardForDuration() external view returns (uint256 _distributedTokens) {
        return rewardRate * rewardsDuration;
    }

    /// @notice modifier used to keep track of the dynamic rewards for user each time a deposit or withdrawal is made
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
}
