const { ethers, upgrades, network } = require("hardhat");

const deployed = require("./deployed-"+network.config.chainId+".json")

const {BigNumber} = ethers

function ForBig(big) {
    if ( big instanceof BigNumber ) {
        return big.toString()
    }


    if (  big instanceof Object ) {
        let obj = big instanceof Array ?[]:{}
        for(let k in big ) {
            obj[k] = ForBig(big[k])
        }
        return obj
    }
    return big
}

const Hex = num => {
    const h = num.toString(16)
    return '0x' + (h.length % 2 === 1?'0':'') + num.toString(16)
}

const DecimalHex = Hex(1e18)

const MaxInit = '0x'+'f'.repeat(64)

const ZeroAddress = "0x" + '0'.repeat(40)

const Sleep = (s) => new Promise((r,j) => setTimeout(r, s))

let _accounts;
async function Accounts() {
    if ( _accounts ) return _accounts
    _accounts = await ethers.getSigners()
    return _accounts 
}

let _contract = {};
let _contractFactory = {};

async function getContractFactory(contractName) {
    if ( !_contractFactory[contractName] ) {
        _contractFactory[contractName] = await ethers.getContractFactory(contractName)
    }
    return _contractFactory[contractName];
}

async function attach(contractName, address) {
    if ( !_contract[address] ) {
        let contract = await getContractFactory(contractName)
        contract = contract.attach(address)
        contract.calls = new Proxy({}, {
            get(_, key) {
                return (...arg) => {
                    const met = [
                        contract.address,
                        contract.interface.encodeFunctionData(key, arg)
                    ]
                    met._isMethods = true
                    met.decode = hex => {
                        const ed = contract.interface.decodeFunctionResult(key, hex)
                        return ed.length <= 1 ? ed[0] : ed
                    }
                    return met
                }
            }
        });
        _contract[address] = contract
    }
    return _contract[address]
}

/////////// MultiCall ///////////
// any 
function proxy(obj, key, call) {
    Object.defineProperty(obj, key, {
        get: () => call(),
        enumerable : true,
        configurable : false
    })
}

async function MultiCall() {
    const multiCall = await attach("MultiCall", deployed.MULTI_CALL)
    multiCall.callArr = async (callsArg) => {
        const calRes = await multiCall.callStatic.aggregate(callsArg)
        return calRes.returnData.map((v,i) => callsArg[i].decode(v))
    }
    multiCall.callObj = async (methodsObj) => {
        // 存放 encodeABI
        let calls = []
        let pro = []
        // 存放 callsIndex
        const callsIndex = methodsObj instanceof Array?[]:{}

        function analyze(methods, parentObj, key) {
            if ( methods._isMethods) {
                const index = calls.length
                calls.push(methods)
                proxy(parentObj, key, () => {
                    return methods.decode(calls[index])
                })
            }
            else if ( methods instanceof Promise ) {
                const index = pro.length
                pro.push(methods)
                proxy(parentObj, key, () => pro[index])
            }
            else if ( methods instanceof BigNumber ) {
                parentObj[key] = methods
            }
            else if ( methods instanceof Object ) {
                parentObj[key] = methods instanceof Array?[]:{}
                for(let index in methods) {
                    analyze(methods[index], parentObj[key], index)
                }
            }
            else {
                parentObj[key] = methods
            }
        }

        for(let key in methodsObj) {
            analyze(methodsObj[key], callsIndex, key)
        }

        calls = (await multiCall.callStatic.aggregate(calls)).returnData
        if ( pro.length > 0 ) pro = await Promise.all(pro)
        return callsIndex        
    }
    return multiCall
}


async function SendBNB(fromSigner, toAddress, amountBig, data = "0x") {
    tx = await fromSigner.sendTransaction({
        to: toAddress,
        value: amountBig,
        data
    })
    console.log(fromSigner.address, " send BNB to ", toAddress, " on ", tx.hash)
    await tx.wait()
}

function CallBNB(fromSigner, toAddress, inputABI, outputType) {
    return fromSigner.provider.call(
        {
            from: fromSigner.address,
            to: toAddress,
            data: inputABI
        }
    ).then( hex => {
        return outputType ? DecodeABI(outputType, hex) : hex
    })
}

function EstimateGas(fromSigner, toAddress, inputABI) {
    return fromSigner.provider.call(
        {
            from: fromSigner.address,
            to: toAddress,
            data: inputABI
        }
    )
}

// types => ["uint","address"]
// dataArray = [[123, "0x111111"]]
function MethodsEncodeABI(methodsName, types, dataArray) {
    if (isNaN(methodsName * 1) ) methodsName = (ethers.utils.solidityKeccak256(["string"], [methodsName])).slice(0,10)
    return ethers.utils.defaultAbiCoder.encode(types, dataArray).replace("0x",methodsName)
}

function EncodeABI(types, dataArray) {
    return ethers.utils.defaultAbiCoder.encode(types, dataArray)
}

function DecodeABI(types, hex) {
    return ethers.utils.defaultAbiCoder.decode(types, hex)
}

function BnbBalance(address) {
    return ethers.provider.getBalance(address)
}

// deploy contract by deployed json

// deployed.ContractAt

function ERC20(address) {
    return attach("TestCoin", address)
}

function Pair(address) {
    return attach("MockUniswapV2FactoryUniswapV2Pair", address)
}

async function Deploy(contractName, ...arg) {
    let dep = await getContractFactory(contractName)
    console.log(...arg)
    dep = await dep.deploy(...arg)
    console.log(contractName, " deployed to ", dep.address )
    return dep
}

async function DeployProxy(contractName, arg, config ) {
    let dep = await getContractFactory(contractName)
    dep = await upgrades.deployProxy(dep, arg, config);
    await dep.deployed();
    console.log(contractName, " deployed to ", dep.address )
    return dep
}

async function UpProxy(contractName, address) {
    address = address || deployed.ContractAt[contractName]
    if (!address) throw contractName + ' not address';
    let dep = await getContractFactory(contractName)
    dep = await upgrades.upgradeProxy(address, dep);
    console.log(contractName, " deployed to ", dep.address )
    return dep
}


const Attach = new Proxy({}, {
    get: function(_, contactName) {
        const getAttach = address => {
            if ( !address ) {
                address = deployed.ContractAt[contactName]
            }
            if ( !address ) throw(contactName, " address error")
            return attach(contactName, address)
        }
        getAttach.Deploy = (...arg) => Deploy(contactName, ...arg)
        getAttach.DeployProxy = (arg, config) => DeployProxy(contactName, arg, config)
        getAttach.UpProxy = (address) => UpProxy(contactName, address)
        return getAttach
    }
});

async function DeploySwap(freeToAddress) {
    const WETH = await Deploy("WETH")
    const factory = await Deploy("UniFactory", freeToAddress)
    const router = await Deploy("Router", factory.address, WETH.address)

    return {
        WETH,
        factory,
        router
    }
}

async function SetBlockTime(seconds) {
    try {
        // 仅 test net 可用
        await network.provider.send("evm_setNextBlockTimestamp", [seconds])
        // await network.provider.send("evm_mine")
    } catch (error) {
        console.log("当前网络不支持 SetBlockTime")
    }
    
}

async function AddBlockTime(seconds) {
    try {
        // 仅 test net 可用
        await network.provider.send("evm_increaseTime", [seconds])
        // await network.provider.send("evm_mine")
    } catch (error) {
        console.log("当前网络不支持 AddBlockTime")
    }
}

// 冒出账户 仅 fork 可用
let signers = {}
async function _ImportAddress(address) {
    const provider = process.env.IN_FORK === 'true' ? network.provider : new ethers.providers.JsonRpcProvider(network.config.url);
    await provider.send("hardhat_impersonateAccount", [address]);
    return ethers.provider.getSigner(address); 
}
async function ImportAddress(address) {
    address = address.toLocaleLowerCase()
    if (!signers[address]) {
        signers[address] = await _ImportAddress(address) 
        signers[address].address = address
    }
    return signers[address]
    
}

module.exports = {
    ForBig,
    Sleep,
    Hex,
    DecimalHex,
    MaxInit,
    Accounts,
    BigNumber,

    BnbBalance,
    SendBNB,
    MultiCall,
    ERC20,
    address: deployed,
    Attach,
    Pair,
    Deploy,
    DeployProxy,
    UpProxy,
    EncodeABI,
    DecodeABI,
    MethodsEncodeABI,
    CallBNB,
    EstimateGas,
    DeploySwap,
    SetBlockTime,
    AddBlockTime,
    ZeroAddress,
    ImportAddress
    // UniFactory,
    // Router,
}