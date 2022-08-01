// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../utils/SafeToken.sol";


interface IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address) external view returns(uint);
}

interface IMToken {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address) external view returns(uint);
    function mint(address to, uint amount) external;
    function burnFrom(address from, uint amount) external;
    function init(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _tokenReserve
    ) external;
}

interface IFlashBorrower {
    /// @notice The flashloan callback. `amount` + `fee` needs to repayed to msg.sender before this call returns.
    /// @param sender The address of the invoker of this flashloan.
    /// @param token The address of the token that is loaned.
    /// @param amount of the `token` that is loaned.
    /// @param fee The fee that needs to be paid on top for this loan. Needs to be the same as `token`.
    /// @param data Additional data that was passed to the flashloan function.
    function onFlashLoan(
        address sender,
        IERC20 token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external;
}

interface ICheck {
    function check(address from, address to, uint amount) external;
}

contract MTokenERC20 {

    uint public totalSupply;
    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowance;

    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) public nonces;

    // token Reserve
    uint public reserve;
    // token
    address public tokenReserve;
    // factory
    address public factory;

    string public name;
    string public symbol;
    uint8 public decimals;

    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function init(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _tokenReserve
    ) public {
        require(factory == address(0), "init exists");
        factory = msg.sender;
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        tokenReserve = _tokenReserve;
        uint chainId;
        assembly {
            chainId := chainid()
        }

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    function _mint(address to, uint value) internal {
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint value) internal {
        balanceOf[from] -= value;
        totalSupply -= value;
        emit Transfer(from, address(0), value);
    }

    function _approve(
        address owner,
        address spender,
        uint value
    ) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(
        address from,
        address to,
        uint value
    ) private {
        balanceOf[from] -= value;
        balanceOf[to] += value;
        ICheck(factory).check(from, to, value);
        emit Transfer(from, to, value);
    }

    function approve(address spender, uint value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }
    
    function transferFrom(
        address from,
        address to,
        uint value
    ) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= value;
        }
        _transfer(from, to, value);
        return true;
    }

    function permit(
        address owner,
        address spender,
        uint value,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, "MToken Token: EXPIRED");
        bytes32 digest =
            keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
            );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(
            recoveredAddress != address(0) && recoveredAddress == owner,
            "MToken Token: INVALID_SIGNATURE"
        );
        _approve(owner, spender, value);
    }

    function mint(address to, uint amount) external {
        require(msg.sender == factory, "caller only factory");
        _mint(to, amount);
    }

    function burnFrom(address from, uint amount) external {
        require(msg.sender == factory, "caller only factory");
        _burn(from, amount);
    }
}



contract MTokenFactory is OwnableUpgradeable, ReentrancyGuardUpgradeable {

    using SafeToken for address;

    bytes32 private constant _RETURN_VALUE = keccak256("ERC3156FlashBorrower.onFlashLoan");
    // token prefix
    // MToken USDT
    string internal constant _NAME = "Meer@";
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint256 private constant FLASH_LOAN_FEE = 50; // 0.05%
    uint256 private constant FLASH_LOAN_FEE_PRECISION = 1e5;

    address public MTokenContract;

    // baseToken => MToken
    mapping(address => address) public baseToken;
    // MToken => baseToken
    mapping(address => address) public MToken;

    // borrow
    // user => token => amount
    mapping(address => mapping(address => uint)) private _borrowAmount;

    event CreateMToken(address indexed MToken, address indexed baseToken);
    event LogFlashLoan(address indexed borrower, address indexed token, uint256 amount, uint256 feeAmount, address indexed receiver);

    event Borrow(address indexed baseToken, address indexed borrower, uint amount);
    event Reapy(address indexed baseToken, address indexed borrower, uint amount);

    // MTokenERC20
    function initialize(address _MTokenContract) public initializer {
        MTokenContract = _MTokenContract;
        __Ownable_init();
        __ReentrancyGuard_init();
        _createMToken(
            ETH,
            "MEER",
            "MEER",
            18
        );
    }

    function _concat(string memory _a, string memory _b) internal pure returns (string memory) {
        return string(abi.encodePacked(_a, _b));
    }

    function createMToken(address _baseToken) external returns(address) {

        require(baseToken[_baseToken] == address(0), "MToken exists");
        require(MToken[_baseToken] == address(0), "baseToken exists");

        IERC20 _iBaseToken = IERC20(_baseToken);
        string memory _name = _concat(_NAME, _iBaseToken.symbol());
        string memory _symbol = _iBaseToken.symbol();
        uint8 _decimals = _iBaseToken.decimals();

        return _createMToken(_baseToken, _name, _symbol, _decimals);
    }

    function _salt(address _token) internal view returns(bytes32) {
        return keccak256(abi.encodePacked(_token, address(this)));
    }

    function _createMToken(address _baseToken, string memory _name, string memory _symbol, uint8 _decimals) internal returns(address _MToken) {
        bytes32 salt = _salt(_baseToken);
        // clone cantract
        bytes20 targetBytes = bytes20(MTokenContract);
        assembly {
            let clone := mload(0x40)
            mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone, 0x14), targetBytes)
            mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            _MToken := create2(0, clone, 0x37, salt)
        }

        IMToken(_MToken).init(_name, _symbol, _decimals, _baseToken);

        baseToken[_baseToken] = _MToken;
        MToken[_MToken] = _baseToken;

        emit CreateMToken(_MToken, _baseToken);
    }

    function mint(address _MToken, address _to, uint _amount) external onlyOwner {
        IMToken(_MToken).mint(_to, _amount);
    }

    function burn(address _MToken, uint _amount) external {
        IMToken(_MToken).burnFrom(msg.sender, _amount);
    }

    // The key to the reentrancy attack is that the contract interface calls back the contract itself
    // Contract interfaces are not severely restricted by other contract constraints
    function deposit(address _token, address _to, uint _amount) external {
        address sender = _msgSender();
        address _MToken = baseToken[_token];
        _token.safeTransferFrom(sender, address(this), _amount);
        IMToken(_MToken).mint(_to, _amount);
    }

    function withdraw(address _MToken, address _to, uint _amount) external {
        address sender = _msgSender();
        address _token = MToken[_MToken];
        IMToken(_MToken).burnFrom(sender, _amount);
        _token.safeTransfer(_to, _amount);
    }

    function borrowBalanceOf(address _user, address _asset) external view returns(uint) {
        return _borrowAmount[_user][_asset];
    }

    function check(address from, address to, uint amount) external virtual {}

    function maxFlashLoan(address token) public view returns (uint256) {
        return token == address(this) ? type(uint256).max - IERC20(token).totalSupply() : 0;
    }

}