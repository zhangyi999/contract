network=""
fork=""
if [ ${2} ]
then
    network="--network ${2}"
fi

if [ ${2} == "fork" ]
then
    fork=true
    network=""
fi

IN_FORK=$fork npx hardhat $network test test/work/${1}