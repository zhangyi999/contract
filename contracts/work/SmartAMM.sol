// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRouter {

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    )
    external
    returns (
        uint amountA,
        uint amountB,
        uint liquidity
    );

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    )
    external
    payable
    returns (
        uint amountToken,
        uint amountETH,
        uint liquidity
    );

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);

    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint amountA, uint amountB);

    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint amountToken, uint amountETH);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    function swapTokensForExactETH(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapETHForExactTokens(
        uint amountOut,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    function quote(
        uint amountA,
        uint reserveA,
        uint reserveB
    ) external pure returns (uint amountB);

    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) external pure returns (uint amountOut);

    function getAmountIn(
        uint amountOut,
        uint reserveIn,
        uint reserveOut
    ) external pure returns (uint amountIn);

    function getAmountsOut(uint amountIn, address[] calldata path)
    external
    view
    returns (uint[] memory amounts);

    function getAmountsIn(uint amountOut, address[] calldata path)
    external
    view
    returns (uint[] memory amounts);
}

interface ISmartAMM {
    function setBuy(uint) external;
    function setInterval(uint) external;
}

contract SmartAMM {
    
    using SafeToken for address;

    uint public constant EPX = 1e6;
    // 拉盘间隔
    uint public interval;

    // 最后一次更新时间
    uint public lastBuy;
    // 平均每笔买入数量
    uint public buyAmount;

    address public owner;

    // seter 控制着
    mapping(address => bool) public seter;

    // usdt
    address public usdt;
    address public token;
    address public router;

    modifier onlyOwner {
        require(msg.sender == owner, "caller only owner");
        _;
    }

    modifier onlyDev {
        require(seter[msg.sender], "caller not seter");
        _;
    }

    event RandomBuy(address indexed sender, uint buyAmount, uint seed, uint limit, uint time, address coinbase);

    constructor(
        address _usdt,
        address _token,
        address _router
    ) {
        owner = msg.sender;
        interval = 5 minutes;
        // 默认 100 U
        buyAmount = 100 ether;
        usdt = _usdt;
        token = _token;
        router = _router;
        
        seter[owner] = true;
    }

    function setOwner(address _newOwner) external onlyOwner {
        owner = _newOwner;
    }

    function setDever(address _seter, bool _status) external onlyOwner {
        seter[_seter] = _status;
    }

    // usdt 数量
    function setBuy(uint _buyAmountUSDTByDay) external onlyDev {
        buyAmount = _buyAmountUSDTByDay * interval / 1 days;
    }

    function setInterval(uint _interval) external onlyDev {
        uint _newBuy = buyAmount * 1 days / interval;
        interval = _interval;
        buyAmount = _newBuy * interval / 1 days;
        lastBuy = block.timestamp + interval;
    }

    function random256() public view returns (uint seed, uint limit, uint time, address coinbase) {
        limit = block.gaslimit;
        time = block.timestamp;
        coinbase = block.coinbase;
        seed = uint(keccak256(abi.encodePacked(limit, time, coinbase)));
    }

    function buy() external {
        uint _now = block.timestamp;
        if ( _now >= lastBuy ) {
            _buy();
        }
    }

    function _buy() internal {

        (uint seed, uint limit, uint time, address coinbase) = random256();

        // [0, interval /2]
        // interval - interval /2[ ]
        uint _randomTime = (seed % interval) + interval / 2;
        // interval - _randomTime
        lastBuy = block.timestamp + _randomTime;

        // seed = [0, 100]
        // EPX / 2 = 50%
        // EPX / 2 - _randomEPX = [-50, 50]
        int _randomBuy = int(EPX / 2) - int(seed % EPX);

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

        emit RandomBuy(msg.sender, _buyAmount, seed, limit, time, coinbase);
    }

    function withdraw(address _token, address to, uint value) external onlyOwner {
        _token.safeTransfer(to, value);
    }
}

library SafeToken {
    function safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "!safeTransfer");
    }

    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "!safeTransferFrom");
    }

    function safeApprove(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "!safeApprove");
    }
}
