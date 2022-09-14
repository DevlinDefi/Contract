// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../token/DDTToken.sol";
import "../interface/IMasterChef.sol";
import "../interface/INFTMasterchef.sol";

contract DDTMasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of DDTs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accDDTPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accDDTPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. DDTs to distribute per block.
        uint256 lastRewardBlock; // Last block number that DDTs distribution occurs.
        uint256 accDDTPerShare; // Accumulated DDTs per share, times 1e12. See below.
        IMasterChef poolMasterChef; // Address of Otherchef
        uint256 fee; // pool deposit fee  
        uint256 method; // 0 for enterstaking & leavestaking 1 for deposid & withdraw
    }
    // Info of each emergency pool 
    struct EmergencyPool {
        uint256 pid; 
        IERC20 lpToken; 
    }
    // store  pool Info  emergencyWithdraw Happened
    EmergencyPool[] public emergencyPoolHappened;
    // The DDT TOKEN!
    DDTToken public DDT;
    // Dev address.
    address public devaddr;
    // DDT tokens created per block.
    uint256 public DDTPerBlock;
    // Bonus muliplier for early DDT makers.
    uint256 public BONUS_MULTIPLIER = 1;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when DDT mining starts.
    uint256 public startBlock;
    //Because transfer LP and token ppolBalance store poolBalance
    mapping (uint256 => uint256) public poolBalance;
     // 100 % for diveded
    uint256 percent = 100*(1e18);
    // adreess of NFTmasterchef for compund
    INFTMasterchef public NFTMasterChef; 

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        DDTToken _DDT,
        INFTMasterchef _NFTMasterChef,
        address _devaddr,
        uint256 _DDTPerBlock,
        uint256 _startBlock
    ) {
        DDT = _DDT;
        devaddr = _devaddr;
        DDTPerBlock = _DDTPerBlock;
        startBlock = _startBlock;
        NFTMasterChef = _NFTMasterChef;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function getUserBalance(uint256 _pid, address _user) external view returns (uint256){
        UserInfo storage user = userInfo[_pid][_user];
        return user.amount;
    }
    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add( uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate, IMasterChef _poolMasterChef, uint256 _fee, uint256 _method) external onlyOwner {
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
                accDDTPerShare: 0,
                poolMasterChef: _poolMasterChef,
                fee: _fee,
                method: _method
            })
        );
    }
    // Update the given pool's DDT allocation point. Can only be called by the owner.
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
    // View function to see pending DDTs on frontend.
    function pendingDDT(uint256 _pid, address _user) external view returns (uint256){
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accDDTPerShare = pool.accDDTPerShare;
        uint256 lpSupply = poolBalance[_pid];
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 DDTReward = multiplier.mul(DDTPerBlock).mul(pool.allocPoint).div(totalAllocPoint); // use safe math division by zero
            accDDTPerShare = accDDTPerShare.add(DDTReward.mul(1e12).div(lpSupply)); // use safe math division by zero
        }
        return user.amount.mul(accDDTPerShare).div(1e12).sub(user.rewardDebt);
    }
    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }
    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = poolBalance[_pid];
        if (lpSupply <= 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 DDTReward = multiplier.mul(DDTPerBlock).mul(pool.allocPoint).div(totalAllocPoint); // use safe math division by zero
        pool.accDDTPerShare = pool.accDDTPerShare.add(DDTReward.mul(1e12).div(lpSupply)); // use safe math division by zero
        pool.lastRewardBlock = block.number;
        DDT.mint(address(this), DDTReward);
    }
    //Approve another chef by spender this contrcat if succes return true
    function enablePool(uint256 _pid, uint256 _amount) internal returns (bool){
        PoolInfo storage pool = poolInfo[_pid];
        bool approved = pool.lpToken.approve(address(pool.poolMasterChef),_amount);
        require(approved, "Approve failed");
        return true;
    }
    // Deposit LP tokens to MasterChef for DDT allocation.
    function deposit(uint256 _pid,uint256 _otherChefPid, uint256 _amount) external nonReentrant{
        require(_amount > 0,"Amount is zero");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accDDTPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0){
                bool transfered = safeDDTTransfer(address(msg.sender), pending);
                require(transfered,"transfer failed");// check if transfer DDT reward succes
            }
        }

        bool approved = enablePool(_pid, _amount);
        require(approved, "Approve failed"); // check if approve succes

        uint256 fee = _amount.mul(pool.fee).div(percent);
        uint256 newAmount = _amount.sub(fee);
        // external call then function use nonReentrant openzapplin security and safetransfer openzapplin
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), newAmount);
        pool.lpToken.safeTransferFrom(address(msg.sender), address(devaddr), fee);

        if(pool.method == 0){ // check otherchef method and select method
            pool.poolMasterChef.enterStaking(newAmount);
        }else{
            pool.poolMasterChef.deposit(_otherChefPid, newAmount);
        }
        user.amount = user.amount.add(newAmount);
        poolBalance[_pid] = poolBalance[_pid].add(newAmount);
        user.rewardDebt = user.amount.mul(pool.accDDTPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, newAmount);
    }
    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _otherChefPid, uint256 _amount) external nonReentrant{

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accDDTPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0){
            bool transfered = safeDDTTransfer(address(msg.sender), pending);
            require(transfered, "Transfer failed"); // check if transfer succes
        }
        // external call then function use nonReentrant openzapplin security
        if(pool.method == 0){ // check otherchef method and select method
            pool.poolMasterChef.leaveStaking(_amount);
        }else{
            pool.poolMasterChef.withdraw(_otherChefPid, _amount);
        }
        pool.lpToken.safeTransfer(address(msg.sender), _amount);// use safetransfer openzapplin
        user.amount = user.amount.sub(_amount);
        poolBalance[_pid] = poolBalance[_pid].sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accDDTPerShare).div(1e12);

        emit Withdraw(msg.sender, _pid, _amount);
    }
    // Enterstaking user DDT reward to NFTChecf
    function compundDDT(uint256 _pid) external nonReentrant{
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accDDTPerShare).div(1e12).sub(user.rewardDebt);
        require(pending > 0, "Amount is zero"); // check if user DDT reward is not zero
        user.rewardDebt = user.amount.mul(pool.accDDTPerShare).div(1e12);
        bool succes = DDT.approve(address(NFTMasterChef), pending);
        require(succes, "Approve failed");// check if approve NFTChef failed
        //for security use nonReentrant openzapplin
        succes = NFTMasterChef.enterStakingCompund(pending, msg.sender);
        require(succes, "Enterstaking failed"); // result of calling externall contrcat
        emit Withdraw(msg.sender, _pid, pending);
    }
    // Call Withdraw without caring about rewards Otherchef. EMERGENCY ONLY. Because our prototcol onlyOwner
    function emergencyWithdrawFromOtherChef(uint256 _pid) external nonReentrant onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];
        bool approved = enablePool(_pid, poolBalance[_pid]);
        require(approved, "Approve failed"); // check if approve succes
        emergencyPoolHappened.push(
            EmergencyPool({
                pid : _pid,
                lpToken : pool.lpToken
            })
        ); // store  pool address  emergencyWithdraw Happened
        pool.poolMasterChef.emergencyWithdraw(_pid);
    }
    // Withdraw without caring about rewards. EMERGENCY ONLY. after dev call otherchef emergency withdraw
    function emergencyWithdraw(uint256 _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
    }
    // whitdraw reward earned from otherchef
    function withdrawReward(uint256 _amount, IERC20 _token) external onlyOwner {
        for (uint256 i=0; i< emergencyPoolHappened.length; i++){
            if(address(emergencyPoolHappened[i].lpToken) == address(_token)){
                require((emergencyPoolHappened[i].lpToken.balanceOf(address(this)).sub(poolBalance[emergencyPoolHappened[i].pid])) > _amount,"_amount is incorrect");
            }
        }
        _token.safeTransfer(devaddr, _amount);
    }
    // Safe DDT transfer function, just in case if rounding error causes pool to not have enough DDTs.
    function safeDDTTransfer(address _to, uint256 _amount) internal returns(bool){
        uint256 DDTBal = DDT.balanceOf(address(this));
        bool sent = false;
        if (_amount > DDTBal) {
            sent = DDT.transfer(_to, DDTBal);
            require(sent,"Transfer Failed");
            return sent;
        } else {
            sent = DDT.transfer(_to, _amount);
            require(sent,"Transfer Failed");
            return sent;
        }
    }
    //set developer address
    function setDevAddress(address _devaddr) external onlyOwner {
        devaddr = _devaddr;
    }
    //update emision rate
    function updateDDTPerBlock(uint256 newAmount) external onlyOwner {
        DDTPerBlock = newAmount;
    }
    //update NFTMasterchef address
    function updateNFTFarmAddress(INFTMasterchef _newNFTchef) external onlyOwner {
        NFTMasterChef = _newNFTchef;
    }
}