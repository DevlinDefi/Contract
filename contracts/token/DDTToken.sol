// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract DDTToken is ERC20Capped ,ERC20Burnable, ERC20Pausable, Ownable, AccessControl{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(string memory name_, string memory symbol_, uint256 cap_) ERC20(name_, symbol_) ERC20Capped(cap_){
        _setupRole(MINTER_ROLE, _msgSender());
    }

    function setupRole(address account) external onlyOwner {
        _setupRole(MINTER_ROLE, account);
    }

    function _mint(address account, uint256 amount) internal override (ERC20Capped,ERC20) {
        super._mint(account, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override(ERC20Pausable,ERC20) {
        super._beforeTokenTransfer(from, to, amount);
    }

    function mint(address account, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(account, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}