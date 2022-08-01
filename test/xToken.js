const { expect } = require("chai");

const {
    Accounts,
    Attach,
    address,
    ImportAddress,
    BigNumber,
    DecimalHex,
    ForBig,
    AddBlockTime
} = require('../scripts/deployed/index')


let tx;

let weth;

let usdt;
let meer;

let killRobot;
let spd;

let xFactory;
let xUsdt;

let lps = {}

let factory;
let router;
let spdRouter;

let accounts;

describe("M token", function () {

    before(async () => {
        accounts = await Accounts()

        meer = await Attach.TestCoin.Deploy("meer","meer")
        usdt = await Attach.TestCoin.Deploy("usdt","usdt")

        weth = await Attach.WETH.Deploy()

        const xToken = await Attach.MTokenERC20.Deploy()
        xFactory = await Attach.MTokenFactory.DeployProxy([xToken.address])

        tx = await xFactory.createMToken(usdt.address)
        await tx.wait()

        xUsdt = await Attach.MTokenERC20(await xFactory.baseToken(usdt.address))
    })

    it("deposit USDT", async function () {
        const signer = accounts[3]
        const amount = BigNumber.from(100).mul(DecimalHex)

        const beforeUSDT = await usdt.balanceOf(signer.address)
        const beforeXUsdt = await xUsdt.balanceOf(signer.address)

        tx = await usdt.mint(signer.address, amount)

        tx = await usdt.connect(signer).approve(xFactory.address, amount)
        await tx.wait()

        tx = await xFactory.connect(signer).deposit(usdt.address, signer.address, amount)
        await tx.wait()
        console.log(amount)

        const afterUSDT = await usdt.balanceOf(signer.address)
        const afterXUsdt = await xUsdt.balanceOf(signer.address)

        console.log(
            "USDT ",
            ForBig(afterUSDT) / 1e18,
            ForBig(beforeUSDT) / 1e18
        )

        console.log(
            "xUSDT ",
            ForBig(afterXUsdt) / 1e18,
            ForBig(beforeXUsdt) / 1e18
        )
    })
});
