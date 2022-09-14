// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../token/NFT.sol";

contract NFTMasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of Powers
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accPowerPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accPowerPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. Powers to distribute per block.
        uint256 lastRewardBlock; // Last block number that Powers distribution occurs.
        uint256 accPowerPerShare; // Accumulated Powers per share, times 1e12. See below.
    }
    //Info of each NFT that can mint
    struct NFTsInfo {
        NFT NFT; // Address of NFT Token
        uint256 power; // Power of NFT
    }
    // Array of NFT can mint
    NFTsInfo[] public nftsInfo;
    // The Power TOKEN!
    IERC20 public DDT;
    // Power tokens created per block.
    uint256 public PowerPerBlock;
    // Bonus muliplier for early Power makers.
    uint256 public BONUS_MULTIPLIER = 1;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when Power mining starts.
    uint256 public startBlock;
    // Address of NFTStake can compund
    address public NFTStakeAddress; 
    // Address of DDTFarm can compund
    address public DDTMasterchefAddress; 
    // Because power is not token store powerBalance here
    mapping(address => uint256) public powerBalance; 
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        IERC20 _DDT,
        uint256 _PowerPerBlock,
        uint256 _startBlock
    ) {
        DDT = _DDT;
        PowerPerBlock = _PowerPerBlock;
        startBlock = _startBlock;
        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: DDT,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accPowerPerShare: 0
        }));
        totalAllocPoint = 1000;
    }
    // Updtae NFTStake address can copmund
    function updateNFTStakeAddress(address _NFTStakeAddress) external onlyOwner{
        NFTStakeAddress = _NFTStakeAddress;
    }
    // Updtae DDTFaem address can copmund
    function updateDDTMasterchefAddress(address _DDTMasterchefAddress) external onlyOwner{
        DDTMasterchefAddress = _DDTMasterchefAddress;
    }
    // return user power balance from powerBalance
    function getPowerBalance(address account) external view returns(uint256) {
        return powerBalance[account];
    }
    // add new NFT user can mint
    function addNFT(NFT _NFT, uint256 _power) external onlyOwner {
        nftsInfo.push(
            NFTsInfo({
                NFT: _NFT,
                power: _power
            })
        );
    }
    // Update NFT power value
    function updateNFT(uint256 level, uint256 _power) external onlyOwner {
        nftsInfo[level].power = _power;
    }
    //user by power balance and pending power can mint NFT 
    function claimNFTReward(uint256 level, uint256 _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        NFTsInfo storage nft = nftsInfo[level];

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accPowerPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0){
            powerBalance[msg.sender] = powerBalance[msg.sender].add(pending); // store power reward on powerBalance
        }
        user.rewardDebt = user.amount.mul(pool.accPowerPerShare).div(1e12);
        require(nft.power <= powerBalance[msg.sender], "Power is not enough"); // NFT level user selected power is > USer power
        powerBalance[msg.sender] = powerBalance[msg.sender].sub(nft.power);
        uint256 tokenId = nft.NFT.mint(msg.sender);
        require(tokenId != 0, "Token id is invalid");// check if NFTFarm can mint NFT and send to user
    }
    function updateMultiplier(uint256 multiplierNumber) external onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }
    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add( uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate ) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accPowerPerShare: 0
            })
        );
    }
    // Update the given pool's Power allocation point. Can only be called by the owner.
    function set( uint256 _pid, uint256 _allocPoint, bool _withUpdate) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }
    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
         return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }
    // View function to see pending Powers on frontend.
    function pendingPower(uint256 _pid, address _user) external view returns (uint256){
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accPowerPerShare = pool.accPowerPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 PowerReward = multiplier.mul(PowerPerBlock).mul(pool.allocPoint).div(totalAllocPoint); // use safe math division by zero
            accPowerPerShare = accPowerPerShare.add(PowerReward.mul(1e12).div(lpSupply)); // use safe math division by zero
        }
        return user.amount.mul(accPowerPerShare).div(1e12).sub(user.rewardDebt);
    }
    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }
    // Update reward variables of the given pool to be up-to-date. power is not token then we have no mint
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply <= 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 PowerReward = multiplier.mul(PowerPerBlock).mul(pool.allocPoint).div(totalAllocPoint); // use safe math division by zero
        pool.accPowerPerShare = pool.accPowerPerShare.add(PowerReward.mul(1e12).div(lpSupply)); // use safe math division by zero
        pool.lastRewardBlock = block.number;
    }
    // Deposit LP tokens to MasterChef for Power allocation.
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant{
        require (_pid != 0, "deposit Power by staking");
        require(_amount > 0, "Amount is zero");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accPowerPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0){
                powerBalance[msg.sender] = powerBalance[msg.sender].add(pending); // store power reward on powerBalance
            }
        }
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount); // use safetransfer openzapplin
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accPowerPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }
    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {

        require (_pid != 0, "withdraw Power by unstaking");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accPowerPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0){
            powerBalance[msg.sender] = powerBalance[msg.sender].add(pending); // store power reward on powerBalance
        }
        if(_amount > 0){
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount); // use safetransfer openzapplin
        }
        user.rewardDebt = user.amount.mul(pool.accPowerPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }
    // Stake Power tokens to MasterChef
    function enterStaking(uint256 _amount) external nonReentrant{
        require(_amount > 0, "Amount is zero");

        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][address(msg.sender)];
        
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accPowerPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                powerBalance[address(msg.sender)] = powerBalance[address(msg.sender)].add(pending); // store power reward on powerBalance
            }
        }

        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount); // use safetransfer openzapplin

        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accPowerPerShare).div(1e12);
        emit Deposit(msg.sender, 0, _amount);
    }
    // Withdraw Power tokens from STAKING.
    function leaveStaking(uint256 _amount) external nonReentrant{
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];

        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accPowerPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            powerBalance[msg.sender] = powerBalance[msg.sender].add(pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount); // use safetransfer openzapplin
        }
        user.rewardDebt = user.amount.mul(pool.accPowerPerShare).div(1e12);
        emit Withdraw(msg.sender, 0, _amount);
    }
    // Just use for another chef enterstaking on NFTMasterchef
    function enterStakingCompund(uint256 _amount, address _account) external nonReentrant returns(bool){
        require(_amount > 0, "Amount is zero");
        require(msg.sender == NFTStakeAddress || msg.sender == DDTMasterchefAddress, "Caller is not family"); // check if caller NFTStake and DDTFarm
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][address(_account)];
        
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accPowerPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                powerBalance[address(_account)] = powerBalance[address(_account)].add(pending);// store power reward on powerBalance
            }
        }

        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount); // use safetransfer openzapplin

        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accPowerPerShare).div(1e12);

        emit Deposit(_account, 0, _amount);
        return true;
    }
    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount); // use safetransfer openzapplin
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }
    //Update Emission power per block
    function updatePowerPerBlock(uint256 newAmount) external onlyOwner {
        PowerPerBlock = newAmount;
    }
}