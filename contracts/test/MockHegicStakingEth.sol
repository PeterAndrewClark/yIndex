// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/ERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";

contract MockHegicStakingEth is ERC20 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    uint256 public LOT_PRICE = 888e21;
    IERC20 public token;
    uint256 public totalProfit;

    event Claim(address account, uint256 profit);

    constructor(IERC20 _token) public ERC20("Hegic ETH Staking Lot", "hlETH") {
        totalProfit = 0;
        token = _token;
        _mint(msg.sender, 100);
    }

    function sendProfit() external payable {
        totalProfit = totalProfit.add(msg.value);
    }

    function claimProfit() external returns (uint256 _profit) {
        _profit = totalProfit;
        require(_profit > 0, "Zero profit");
        emit Claim(msg.sender, _profit);
        _transferProfit(_profit);
        totalProfit = totalProfit.sub(_profit);
    }

    function _transferProfit(uint256 _profit) internal {
        msg.sender.transfer(_profit);
    }

    function buy(uint256 _amount) external {
        require(_amount > 0, "Amount is zero");
        _mint(msg.sender, _amount);
        token.safeTransferFrom(msg.sender, address(this), _amount.mul(LOT_PRICE));
    }

    function sell(uint256 _amount) external {
        _burn(msg.sender, _amount);
        token.safeTransfer(msg.sender, _amount.mul(LOT_PRICE));
    }

    function profitOf(address) public view returns (uint256 _totalProfit) {
        _totalProfit = totalProfit;
    }

    function lastBoughtTimestamp(address) external view returns (uint256) {
        return block.timestamp.sub(1 days);
    }

    // Added test method
    function mintTo(address account, uint256 amount) public {
        _mint(account, amount);
    }
}
