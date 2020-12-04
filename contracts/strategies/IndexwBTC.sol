// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";
import "@openzeppelinV3/contracts/math/Math.sol";
import "@openzeppelinV3/contracts/utils/Address.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";
import {BaseStrategy, StrategyParams} from "@yearnvaults/contracts/BaseStrategy.sol";

import "../../interfaces/yearn/Vault.sol";
import "../../interfaces/uniswap/Uni.sol";

contract IndexwBTC is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public weth;
    address public wBTC;
    address public ywBTC;
    address public unirouter;
    string public constant override name = "IndexBTC";

    constructor(
        address _vault,
        address _weth,
        address _wBTC,
        address _ywBTC,
        address _unirouter
    ) public BaseStrategy(_vault) {
        weth = _weth;
        wBTC = _wBTC;
        crvBTC = _ywBTC;
        unirouter = _unirouter;

        // I assume this is the section that approves the contract for transactions on
        // uniswap for these tokens. But not clear 
        IERC20(weth).safeApprove(unirouter, uint256(-1));
        IERC20(wBTC).safeApprove(unirouter, uint256(-1));
        
    }

    function protectedTokens() internal override view returns (address[] memory) {
        address[] memory protected = new address[](2);
        // want is weth, which is protected by default
        protected[0] = wBTC;
        protected[1] = ywBTC;
        return protected;
    }

    function estimatedTotalAssets() public override view returns (uint256) {
        return balanceOfWant().add(balanceOfStake()).add(balanceOfAsset());
    }

    function prepareReturn(uint256 _debtOutstanding) internal override returns (uint256 _profit, uint256 _loss, uint256 _debtPayment) {
        // We might need to return want to the vault
        if (_debtOutstanding > 0) {
            uint256 _amountFreed = liquidatePosition(_debtOutstanding);
            _debtPayment = Math.min(_amountFreed, _debtOutstanding);
        }

        uint256 balanceOfWantBefore = balanceOfWant();

        // in case there's any stray wBTC, this will sweep for want
        uint256 assetBalance = IERC20(wBTC).balanceOf(address(this));
        if (assetBalance > 0) {
            assetToWant(assetBalance);
        }

        _profit = balanceOfWant().sub(balanceOfWantBefore);
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        //emergency exit is dealt with in prepareReturn
        if (emergencyExit) {
            return;
        }

        uint256 _wantAvailable = balanceOfWant().sub(_debtOutstanding);
        wantToAsset(_wantAvailable);
        uint256 assetBalance = IERC20(wBTC).balanceOf(address(this));

        if (assetBalance > 0) {
            Vault(ywBTC).deposit(assetBalance);
        }
    }

    function exitPosition(uint256 _debtOutstanding)
        internal
        override
        returns (
          uint256 _profit,
          uint256 _loss,
          uint256 _debtPayment
        )
    {

        Vault(ywBTC).withdrawAll();
        uint256 assetBalance = IERC20(wBTC).balanceOf(address(this));
        assetToWant(assetBalance);
        return prepareReturn(_debtOutstanding);
    }

    function liquidatePosition(uint256 _amountNeeded) internal override returns (uint256 _amountFreed) {
        if (balanceOfWant() < _amountNeeded) {
            // We need to sell stakes to get back more want 
            _withdrawSome(_amountNeeded.sub(balanceOfWant()));
        }

        _amountFreed = balanceOfWant();
    }

    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        uint256 wantValue = wethConvert(_amount);
        uint256 vaultShare = Vault(ywBTC).getPricePerFullShare();
        uint256 vaultWithdraw = wantValue.div(vaultShare);
        Vault(ywBTC).withdraw(vaultWithdraw);
        uint256 assetBalance = IERC20(wBTC).balanceOf(address(this));
        assetToWant(assetBalance);
        return balanceOfWant();
    }

    function prepareMigration(address _newStrategy) internal override {
        want.transfer(_newStrategy, balanceOfWant());
        IERC20(wBTC).transfer(_newStrategy, IERC20(wBTC).balanceOf(address(this)));
        IERC20(ywBTC).transfer(_newStrategy, IERC20(ywBTC).balanceOf(address(this)));
    }

    // trades want for asset
    function wantToAsset(uint256 _amountIn) internal returns (uint256[] memory amounts) {
        address[] memory path = new address[](2);
        path[0] = address(want);
        path[1] = address(0x2260fac5e5542a773aa44fbcfedf7c193bc2c599); // wBTC

        Uni(unirouter).swapExactTokensForTokens(_amountIn, uint256(0), path, address(this), now.add(1 days));
    }

    // trades asset for want
    function assetToWant(uint256 _amountIn) internal returns (uint256[] memory amounts) {
        address[] memory path = new address[](2);
        path[0] = address(0x2260fac5e5542a773aa44fbcfedf7c193bc2c599); // wBTC
        path[1] = address(want);

        Uni(unirouter).swapExactTokensForTokens(_amountIn, uint256(0), path, address(this), now.add(1 days));
    }

    // returns value of asset in terms of weth
    function assetConvert(uint256 value) public view returns (uint256) {
        if (value == 0) {
            return 0;
        }

        else {
        address[] memory path = new address[](2);
        path[0] = address(0x2260fac5e5542a773aa44fbcfedf7c193bc2c599); // wBTC
        path[1] = address(want);
        uint256[] memory amounts = Uni(unirouter).getAmountsOut(value, path);

        return amounts[amounts.length - 1];
        }
    }

    // returns value of weth in terms of asset
    function wethConvert(uint256 value) public view returns (uint256) {
        if (value == 0) {
            return 0;
        }

        else {
        address[] memory path = new address[](2);
        path[0] = address(want);
        path[1] = address(0x2260fac5e5542a773aa44fbcfedf7c193bc2c599); // wBTC
        uint256[] memory amounts = Uni(unirouter).getAmountsOut(value, path);

        return amounts[amounts.length - 1];
        }
    }

    function balanceOfAsset() public view returns (uint256) {
        uint256 assetBalance = IERC20(wBTC).balanceOf(address(this));
        return assetConvert(assetBalance);
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfStake() public view returns (uint256) {
        uint256 vaultShares = IERC20(ywBTC).balanceOf(address(this));
        uint256 vaultPrice = Vault(ywBTC).getPricePerFullShare();
        uint256 vaultBalance = vaultShares.mul(vaultPrice);
        return assetConvert(vaultBalance);
    }
}