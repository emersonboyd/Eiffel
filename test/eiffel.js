// test/eiffel.js
// Load dependencies
const { expect } = require('chai');

let MyContract;
let myContract;
 
// Start test block
// describe('MyContract Implementation Tests', function () {
//   beforeEach(async function () {
//     MyContract = await ethers.getContractFactory("MyUpgradeableContract");
//     myContract = await MyContract.deploy(); // deploys the implementation contract
//     await myContract.deployed();
//     await myContract.initialize();
//   });
 
//   // Test case
//   it('Should create token with totalSupply', async function () {
//     const decimals = '000000000000000000'; // 18 decimals
//     const wholeNum = '1000000000000'; // 10^12 (1 trillion coins)
//     const totalSupplyExpected = wholeNum + decimals;
//     const minterAddress = await myContract.getMinter();
//     const totalSupply = await myContract.balanceOf(minterAddress);
//     expect(totalSupply.toString()).to.equal(totalSupplyExpected);
//   });

//   // Test case
//   it('Should burn 5 percent from transaction', async function () {
//     // Only 5 percent is burned because minter is the liquidityPoolAddress for starters
//     const minterAddress = await myContract.getMinter();
//     const tradeAmount = 924;
//     await myContract.transfer(minterAddress, tradeAmount);
//     const newMinterAmount = await myContract.balanceOf(minterAddress);
//     expect(newMinterAmount.toString()).to.equal('999999999999999999999999999954'); // 46 was burned
//   });
// });


let Market;
let market;
let owner;
let ownerAddress;
let a1;
let a1Address;
const bid = 0;
const ask = 1;

describe("Eiffel contract tests", function () {
  beforeEach(async function() {
    [owner, a1] = await ethers.getSigners();
    ownerAddress = await owner.getAddress();
    a1Address = await a1.getAddress();
    Market = await ethers.getContractFactory("Market");
    market = await Market.deploy();
    await market.deployed();
  });

  // Test case
  it("Test matching all sorts of orders", async function () {
    await expect(market.connect(owner).AddLimitOrder(ask, 50, 5))
      .to.emit(market, "NewOrder").withArgs(ask, ownerAddress, 50, 5);

    const mktQty1 = await market.GetMarketQty();
    const mktQty2 = await market.connect(owner).GetMarketQty();
    const mktQty3 = await market.connect(a1).GetMarketQty();
    expect(mktQty1.toString()).to.equal('5');
    expect(mktQty2.toString()).to.equal('5');
    expect(mktQty3.toString()).to.equal('5');
    const [qty, prc] = await market.GetMarketInfo(ask, 1);
    expect(prc.toString()).to.equal('50');
    expect(qty.toString()).to.equal('5');

    {
    const [topAccount, topPrc, topQty] = await market.GetTopOrder(ask);
    expect(topAccount).to.equal(ownerAddress);
    expect(topPrc.toString()).to.equal('50');
    expect(topQty.toString()).to.equal('5');
    }

    // plain old match, clear ask order book
    await expect(market.connect(a1).AddLimitOrder(bid, 50, 5))
      .to.emit(market, "NewOrder").withArgs(bid, a1Address, 50, 5)
      .and.to.emit(market, "OrderMatch").withArgs(ask, a1Address, ownerAddress, 50, 5);

    await expect(market.connect(owner).AddLimitOrder(bid, 48, 5))
      .to.emit(market, "NewOrder").withArgs(bid, ownerAddress, 48, 5);
    await expect(market.connect(owner).AddLimitOrder(bid, 49, 5))
      .to.emit(market, "NewOrder").withArgs(bid, ownerAddress, 49, 5);
    await expect(market.connect(owner).AddLimitOrder(bid, 50, 5))
      .to.emit(market, "NewOrder").withArgs(bid, ownerAddress, 50, 5)
      .and.to.emit(market, "OrderLevelClear").withArgs(bid, 48);

    // test a self-match, which should work fine. clear a few from the top order, but don't clear it entirely
    await expect (market.connect(owner).AddLimitOrder(ask, 49, 2))
      .to.emit(market, "NewOrder").withArgs(ask, ownerAddress, 49, 2)
      .and.to.emit(market, "OrderMatch").withArgs(bid, ownerAddress, ownerAddress, 50, 2);

    // matching across price levels
    await expect(market.connect(a1).AddLimitOrder(ask, 45, 10))
      .to.emit(market, "NewOrder").withArgs(ask, a1Address, 45, 10)
      .and.to.emit(market, "OrderMatch").withArgs(bid, a1Address, ownerAddress, 50, 3)
      .and.to.emit(market, "OrderMatch").withArgs(bid, a1Address, ownerAddress, 49, 5);

    {
    const [topAccount, topPrc, topQty] = await market.GetTopOrder(ask);
    expect(topAccount).to.equal(a1Address);
    expect(topPrc.toString()).to.equal('45');
    expect(topQty.toString()).to.equal('2');
    }
  });

});
