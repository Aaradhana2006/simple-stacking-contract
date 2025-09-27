
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Simple ERC20 Token for Testing
 * @dev A basic ERC20 token implementation for staking and rewards
 */
contract SimpleERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    constructor(string memory _name, string memory _symbol, uint256 _totalSupply) {
        name = _name;
        symbol = _symbol;
        totalSupply = _totalSupply * 10**decimals;
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        
        emit Transfer(from, to, amount);
        return true;
    }
    
    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }
}

/**
 * @title Staking Contract
 * @dev A complete token staking contract that allows users to stake tokens and earn rewards over time
 * @author Staking Platform Team
 */
contract StakingContract {
    // Token contracts
    SimpleERC20 public stakingToken;
    SimpleERC20 public rewardToken;
    
    // Staking information structure
    struct StakeInfo {
        uint256 amount;              // Amount of tokens staked
        uint256 rewardDebt;          // Reward debt for accurate calculation
        uint256 lastStakeTime;       // Last time user staked tokens
        uint256 totalRewardsClaimed; // Total rewards claimed by user
    }
    
    // State variables
    mapping(address => StakeInfo) public stakeInfo;
    mapping(address => uint256) public userRewardPerTokenPaid;
    
    uint256 public totalStaked;
    uint256 public rewardRate = 1000000000000000000; // 1 token per second
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public stakingDuration = 1 minutes; // 1 minute for easy testing
    
    address public owner;
    bool public stakingPaused = false;
    
    // Events
    event TokensStaked(address indexed user, uint256 amount, uint256 timestamp);
    event TokensUnstaked(address indexed user, uint256 amount, uint256 timestamp);
    event RewardsClaimed(address indexed user, uint256 reward, uint256 timestamp);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);
    event StakingPaused(bool paused);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier notPaused() {
        require(!stakingPaused, "Staking is currently paused");
        _;
    }
    
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        
        if (account != address(0)) {
            stakeInfo[account].rewardDebt = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }
    
    modifier hasStaked() {
        require(stakeInfo[msg.sender].amount > 0, "No tokens staked");
        _;
    }
    
    /**
     * @dev Constructor - Deploys staking and reward tokens automatically
     */
    constructor() {
        owner = msg.sender;
        
        // Deploy staking token (STAKE)
        stakingToken = new SimpleERC20("StakeToken", "STAKE", 1000000);
        
        // Deploy reward token (REWARD) 
        rewardToken = new SimpleERC20("RewardToken", "REWARD", 1000000);
        
        lastUpdateTime = block.timestamp;
        
        // Mint additional reward tokens to contract for distribution
        rewardToken.mint(address(this), 500000 * 10**18);
    }
    
    /**
     * @dev Core Function 1: Stake tokens to earn rewards
     * @param _amount Amount of tokens to stake
     */
    function stakeTokens(uint256 _amount) external notPaused updateReward(msg.sender) {
        require(_amount > 0, "Cannot stake 0 tokens");
        require(
            stakingToken.balanceOf(msg.sender) >= _amount,
            "Insufficient token balance"
        );
        require(
            stakingToken.allowance(msg.sender, address(this)) >= _amount,
            "Token allowance too low - please approve tokens first"
        );
        
        // Transfer tokens from user to contract
        require(
            stakingToken.transferFrom(msg.sender, address(this), _amount),
            "Token transfer failed"
        );
        
        // Update user's stake info
        stakeInfo[msg.sender].amount += _amount;
        stakeInfo[msg.sender].lastStakeTime = block.timestamp;
        totalStaked += _amount;
        
        emit TokensStaked(msg.sender, _amount, block.timestamp);
    }
    
    /**
     * @dev Core Function 2: Unstake tokens and claim all rewards
     * @param _amount Amount of tokens to unstake (0 means unstake all)
     */
    function unstakeTokens(uint256 _amount) external hasStaked updateReward(msg.sender) {
        StakeInfo storage userStake = stakeInfo[msg.sender];
        
        // Check minimum staking duration
        require(
            block.timestamp >= userStake.lastStakeTime + stakingDuration,
            "Minimum staking duration not met"
        );
        
        uint256 amountToUnstake = _amount;
        if (_amount == 0 || _amount > userStake.amount) {
            amountToUnstake = userStake.amount;
        }
        
        require(amountToUnstake > 0, "No tokens to unstake");
        
        // Calculate and transfer rewards
        uint256 reward = userStake.rewardDebt;
        if (reward > 0) {
            userStake.rewardDebt = 0;
            userStake.totalRewardsClaimed += reward;
            
            // Check if contract has enough reward tokens
            if (rewardToken.balanceOf(address(this)) >= reward) {
                require(
                    rewardToken.transfer(msg.sender, reward),
                    "Reward transfer failed"
                );
                emit RewardsClaimed(msg.sender, reward, block.timestamp);
            }
        }
        
        // Update stake info
        userStake.amount -= amountToUnstake;
        totalStaked -= amountToUnstake;
        
        // Transfer staked tokens back to user
        require(
            stakingToken.transfer(msg.sender, amountToUnstake),
            "Token transfer failed"
        );
        
        emit TokensUnstaked(msg.sender, amountToUnstake, block.timestamp);
    }
    
    /**
     * @dev Core Function 3: Claim earned rewards without unstaking
     */
    function claimRewards() external hasStaked updateReward(msg.sender) {
        uint256 reward = stakeInfo[msg.sender].rewardDebt;
        require(reward > 0, "No rewards to claim");
        
        stakeInfo[msg.sender].rewardDebt = 0;
        stakeInfo[msg.sender].totalRewardsClaimed += reward;
        
        // Check if contract has enough reward tokens
        require(
            rewardToken.balanceOf(address(this)) >= reward,
            "Insufficient reward tokens in contract"
        );
        
        require(
            rewardToken.transfer(msg.sender, reward),
            "Reward transfer failed"
        );
        
        emit RewardsClaimed(msg.sender, reward, block.timestamp);
    }
    
    /**
     * @dev Calculate reward per token
     * @return Reward per token value
     */
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        
        return rewardPerTokenStored + 
            (((block.timestamp - lastUpdateTime) * rewardRate * 1e18) / totalStaked);
    }
    
    /**
     * @dev Calculate earned rewards for a user
     * @param account User address
     * @return Earned reward amount
     */
    function earned(address account) public view returns (uint256) {
        return ((stakeInfo[account].amount * 
            (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) + 
            stakeInfo[account].rewardDebt;
    }
    
    /**
     * @dev Get comprehensive staking information for a user
     * @param user User address
     * @return stakedAmount Amount of tokens staked
     * @return earnedRewards Current earned rewards
     * @return lastStakeTimestamp Last time user staked tokens
     * @return totalClaimedRewards Total rewards claimed by user
     * @return timeUntilUnlock Time until tokens can be unstaked
     */
    function getUserStakingInfo(address user) external view returns (
        uint256 stakedAmount,
        uint256 earnedRewards,
        uint256 lastStakeTimestamp,
        uint256 totalClaimedRewards,
        uint256 timeUntilUnlock
    ) {
        StakeInfo memory userStake = stakeInfo[user];
        stakedAmount = userStake.amount;
        earnedRewards = earned(user);
        lastStakeTimestamp = userStake.lastStakeTime;
        totalClaimedRewards = userStake.totalRewardsClaimed;
        
        uint256 unlockTime = userStake.lastStakeTime + stakingDuration;
        timeUntilUnlock = block.timestamp >= unlockTime ? 0 : unlockTime - block.timestamp;
    }
    
    /**
     * @dev Get contract statistics
     * @return totalTokensStaked Total tokens staked in the contract
     * @return currentRewardRate Current reward rate per second
     * @return contractRewardBalance Available reward tokens in contract
     * @return minimumStakingPeriod Minimum time tokens must be staked
     */
    function getContractInfo() external view returns (
        uint256 totalTokensStaked,
        uint256 currentRewardRate,
        uint256 contractRewardBalance,
        uint256 minimumStakingPeriod
    ) {
        totalTokensStaked = totalStaked;
        currentRewardRate = rewardRate;
        contractRewardBalance = rewardToken.balanceOf(address(this));
        minimumStakingPeriod = stakingDuration;
    }
    
    /**
     * @dev Calculate Annual Percentage Yield (APY) based on current conditions
     * @return APY as a percentage (multiplied by 100)
     */
    function calculateAPY() external view returns (uint256) {
        if (totalStaked == 0) return 0;
        
        uint256 yearlyRewards = rewardRate * 365 days;
        uint256 apy = (yearlyRewards * 10000) / totalStaked;
        return apy;
    }
    
    // Utility functions for easy testing
    
    /**
     * @dev Get free staking tokens for testing (only works once per address)
     */
    function getFreeStakeTokens() external {
        require(stakingToken.balanceOf(msg.sender) == 0, "You already have stake tokens");
        stakingToken.mint(msg.sender, 1000 * 10**18); // 1000 STAKE tokens
    }
    
    /**
     * @dev Approve staking contract to spend your tokens
     * @param amount Amount to approve
     */
    function approveStaking(uint256 amount) external {
        stakingToken.approve(address(this), amount);
    }
    
    /**
     * @dev Get token addresses for frontend integration
     * @return stakingTokenAddress Address of the staking token
     * @return rewardTokenAddress Address of the reward token
     */
    function getTokenAddresses() external view returns (address stakingTokenAddress, address rewardTokenAddress) {
        stakingTokenAddress = address(stakingToken);
        rewardTokenAddress = address(rewardToken);
    }
    
    // Owner functions
    function setRewardRate(uint256 _rewardRate) external onlyOwner updateReward(address(0)) {
        uint256 oldRate = rewardRate;
        rewardRate = _rewardRate;
        emit RewardRateUpdated(oldRate, _rewardRate);
    }
    
    function setStakingDuration(uint256 _duration) external onlyOwner {
        require(_duration <= 365 days, "Duration too long");
        stakingDuration = _duration;
    }
    
    function pauseStaking() external onlyOwner {
        stakingPaused = !stakingPaused;
        emit StakingPaused(stakingPaused);
    }
    
    function emergencyWithdraw() external onlyOwner {
        uint256 rewardBalance = rewardToken.balanceOf(address(this));
        if (rewardBalance > 0) {
            rewardToken.transfer(owner, rewardBalance);
        }
        
        uint256 stakingBalance = stakingToken.balanceOf(address(this));
        if (stakingBalance > 0) {
            stakingToken.transfer(owner, stakingBalance);
        }
    }
    
    function addRewards(uint256 _amount) external onlyOwner {
        rewardToken.mint(address(this), _amount);
    }
}
