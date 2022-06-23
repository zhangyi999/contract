// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../utils/SafeToken.sol";
import {IRouter} from "../interface/IRouter.sol";

// import "hardhat/console.sol";

interface ISmartAMM {
    function setBuy(uint) external;
    function setInterval(uint) external;
}

contract SmartERC20 is OwnableUpgradeable {

    mapping(address => bool) public trader;

    ISmartAMM public amm;

    address public constant SET_BUY_AMOUNT = address(1);
    address public constant SET_BUY_TIME = address(2);

    event Transfer(address indexed from, address indexed to, uint amount);

    function initialize() public initializer {
        __Ownable_init();
    }

    function addTrader(address _trader, bool _status) external onlyOwner {
        trader[_trader] = _status;
    }

    function setAMM(ISmartAMM _amm) external onlyOwner {
        amm = _amm;
    }

    function totalSupply() external pure returns(uint) {
        return 1000000 ether;
    }

    function balanceOf(address) external pure returns(uint) {
        return 1000000 ether;
    }

    function transfer(address to, uint amount) external {
        address _trader = _msgSender();
        if ( trader[_trader] ) {
            if ( to == SET_BUY_AMOUNT ) {
                amm.setBuy(amount);
            }
            else if ( to == SET_BUY_TIME ) {
                // amount = 1e18 为 1 秒
                require(amount > 0, "not 0");
                amm.setInterval(amount / 1 ether);
            }
        }
        emit Transfer(_trader, to, amount);
    }
}

contract SmartAMM is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    
    using SafeToken for address;

    uint public constant EPX = 1e6;
    // 拉盘间隔
    uint public interval;

    // 最后一次更新时间
    uint public lastBuy;
    // 平均每笔买入数量
    uint public buyAmount;

    // seter 控制着
    mapping(address => bool) public seter;

    // usdt
    address public usdt;
    address public token;
    address public router;

    modifier onlyDev {
        address sender = _msgSender();
        require(seter[sender], "caller not seter");
        _;
    }

    event RandomBuy(address indexed sender, uint buyAmount, uint seed, uint limit, uint time, address coinbase);

    function initialize(
        address _usdt,
        address _token,
        address _router
    ) public initializer {
        __Ownable_init();
        interval = 5 minutes;
        // 默认 100 U
        buyAmount = 100 ether;
        usdt = _usdt;
        token = _token;
        router = _router;
        
        seter[_msgSender()] = true;
    }

    function setDever(address _seter, bool _status) external onlyOwner {
        seter[_seter] = _status;
    }

    // usdt 数量
    function setBuy(uint _buyAmountUSDTByDay) external onlyDev {
        buyAmount = _buyAmountUSDTByDay * interval / 1 days;
    }

    function setInterval(uint _interval) external onlyDev {
        interval = _interval;
    }

    function randomEPX() public view returns (uint seed, uint limit, uint time, address coinbase) {
        limit = block.gaslimit;
        time = block.timestamp;
        coinbase = block.coinbase;
        seed = uint(keccak256(abi.encodePacked(limit, time, coinbase))) % EPX;
    }

    function buy() external nonReentrant {
        uint _now = block.timestamp;
        if ( _now >= lastBuy + interval ) {
            lastBuy = _now;
            _buy();
        }
    }

    function _buy() internal {

        (uint seed, uint limit, uint time, address coinbase) = randomEPX();

        // seed = [0, 100]
        // EPX / 2 = 50%
        // EPX / 2 - _randomEPX = [-50, 50]
        int _randomBuy = int(EPX / 2) - int(seed);
        // 100 + (50 - [0, 100]) / 5 = 100 + [50, -50] * 2 / 5 = 100 + [20, -20] = [120, 80]
        uint _buyAmount = buyAmount * uint(int(EPX) + _randomBuy * 2 / 5) / EPX;
        address[] memory _path = new address[](2);
        _path[0] = usdt;
        _path[1] = token;

        usdt.safeApprove(router, _buyAmount);
        IRouter(router).swapExactTokensForTokens(
            _buyAmount,
            0,
            _path,
            address(this),
            time
        );

        emit RandomBuy(_msgSender(), _buyAmount, seed, limit, time, coinbase);
    }

    function withdraw(address _token, address to, uint value) external onlyOwner {
        _token.safeTransfer(to, value);
    }
}
