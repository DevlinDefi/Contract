// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface INFTMasterchef {
    function enterStakingCompund(uint256 _amount, address _account) external returns(bool);

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
}