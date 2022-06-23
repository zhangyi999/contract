const { ethers, upgrades, network } = require("hardhat");

const {
    Attach,
    Accounts,
    MethodsEncodeABI,
    DecodeABI,
    CallBNB
} = require('./deployed')

async function main() {
    // console.log(network)
    const accounts = await Accounts()
    const usdt = await Attach.USDT()
    // console.log(
    //     await usdt.balanceOf(accounts[0].address)
    // )
    console.log(
        await CallBNB(
            accounts[0],
            "0x6D1225934410433A80a8a5E6E1D113a01D53C280",
            MethodsEncodeABI("name()",[],[]),
            ["string"]
        )
    )
    // decode
    // console.log(
    //     usdt.calls.balanceOf(accounts[0].address)[1],
    //     EncodeABI("balanceOf(address)",["address"],[accounts[0].address]),
    //     EncodeABI("0x70a08231",["address"],[accounts[0].address]),

    // )
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});