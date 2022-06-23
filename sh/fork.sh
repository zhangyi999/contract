network="test"
if [ ${2} ]
then
    network="${2}"
fi
npx hardhat --network fork test $network/work/${1}