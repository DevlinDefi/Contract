// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../token/DDTToken.sol";
import "../interface/INFTMasterchef.sol";

contract NFTStake is Ownable, IERC721Receiver, ReentrancyGuard {
    using SafeMath for uint256;
    // Info of each user.
    struct UserInfo {
        uint256[] tokenIds; //User NFTs tokenid
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
        IERC721 NFTToken; // Address of NFT token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. DDTs to distribute per block.
        uint256 lastRewardBlock; // Last block number that DDTs distribution occurs.
        uint256 accDDTPerShare; // Accumulated DDTs per share, times 1e12. See below.
    }
    //NFTChef address for compund
    INFTMasterchef public NFTMasterChef;
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
        NFTMasterChef = _NFTMasterChef;
        devaddr = _devaddr;
        DDTPerBlock = _DDTPerBlock;
        startBlock = _startBlock;
    }

    /**
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(address, address, uint256, bytes memory) external  virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
    function updateMultiplier(uint256 multiplierNumber) external onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }
    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add( uint256 _allocPoint, IERC721 _NFTToken, bool _withUpdate ) external  onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                NFTToken: _NFTToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accDDTPerShare: 0
            })
        );
    }
    // Update the given pool's DDT allocation point. Can only be called by the owner.
    function set( uint256 _pid, uint256 _allocPoint, bool _withUpdate) external  onlyOwner {
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
    // Return array of user NFTs
    function getUserTokenIds(uint256 _pid, address _user) public view returns (uint256[] memory) {
        UserInfo storage user = userInfo[_pid][_user];
        return user.tokenIds;
    }
    // View function to see pending DDTs on frontend.
    function pendingDDT(uint256 _pid, address _user) external view returns (uint256){
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accDDTPerShare = pool.accDDTPerShare;
        uint256 NFTSupply = pool.NFTToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && NFTSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 DDTReward = multiplier.mul(DDTPerBlock).mul(pool.allocPoint).div(totalAllocPoint); // use safe math division by zero
            accDDTPerShare = accDDTPerShare.add(DDTReward.mul(1e12).div(NFTSupply)); // use safe math division by zero
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
        uint256 NFTSupply = pool.NFTToken.balanceOf(address(this));
        if (NFTSupply <= 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 DDTReward = multiplier.mul(DDTPerBlock).mul(pool.allocPoint).div(totalAllocPoint); // use safe math division by zero
        DDT.mint(address(this), DDTReward);
        pool.accDDTPerShare = pool.accDDTPerShare.add(DDTReward.mul(1e12).div(NFTSupply)); // use safe math division by zero
        pool.lastRewardBlock = block.number;
    }
    // Deposit NFT tokens to MasterChef for DDT allocation.
    function deposit(uint256 _pid, uint256 _tokenId) external nonReentrant {
        require(_tokenId != 0, "Token id is not good"); // check if nft id is not zero

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accDDTPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0){
                bool succes = safeDDTTransfer(msg.sender, pending);
                require(succes, "Transfer failed"); // check if transfer succes
            }
        }
        pool.NFTToken.safeTransferFrom(address(msg.sender), address(this), _tokenId); // use safetransfer openzapplin
        user.amount = user.amount.add(1);
        user.rewardDebt = user.amount.mul(pool.accDDTPerShare).div(1e12);
        user.tokenIds.push(_tokenId);
        emit Deposit(msg.sender, _pid, _tokenId);
    }
    // Withdraw NFT tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _tokenId) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount > 0, "withdraw: not good");
        updatePool(_pid);
        uint256   pending = user.amount.mul(pool.accDDTPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0){
            bool succes = safeDDTTransfer(msg.sender, pending);
            require(succes, "Transfer failed"); // check if transfer succes
        }
        if(_tokenId == 0){
            user.rewardDebt = user.amount.mul(pool.accDDTPerShare).div(1e12);
        }
        else {
            uint256 hasTokenId = 0;
            uint256 tokenIdIndex;
            for(uint256 i; i<user.tokenIds.length; i++){
                if(user.tokenIds[i] == _tokenId){
                    hasTokenId = 1;
                    tokenIdIndex = i;
                }
            }
            require(hasTokenId == 1, "You are not Owner of token id"); // check if user owner of NFT
            user.amount = user.amount.sub(1);
            user.rewardDebt = user.amount.mul(pool.accDDTPerShare).div(1e12);
            delete user.tokenIds[tokenIdIndex];
            pool.NFTToken.safeTransferFrom(address(this), address(msg.sender), _tokenId); // use safetransfer openzapplin
        }
        emit Withdraw(msg.sender, _pid, _tokenId);
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
    // update dev address
    function setDevAddress(address _devaddr) public onlyOwner {
        devaddr = _devaddr;
    }
    // update DDT emission rate
    function updateDDTPerBlock(uint256 newAmount) public onlyOwner {
        DDTPerBlock = newAmount;
    }
}