// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const {
    Attach,
    Accounts,
    address,
    ForBig
} = require("../deployed")

let accounts;

let misAmm;
async function main() {
    accounts = await Accounts()
    console.log(
        accounts[0].address
    )

    misAmm = await Attach.SmartAMM(address.Address.MIS_AMM)
    
    async function run(nextTime) {
        setTimeout(async () => {
            const tx = await misAmm.buy()
            console.log(tx.hash)
            await tx.wait()
            const next = await misAmm.lastBuy()
            const now = Math.floor(new Date() / 1000)
            const step = ForBig(next) - now
            console.log(
                step
            )
            run(step * 1000)
        }, nextTime)
    }
    
    await run(0)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
