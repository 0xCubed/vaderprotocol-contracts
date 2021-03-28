const { expect } = require("chai");
var Utils = artifacts.require('./Utils')
var Vether = artifacts.require('./Vether')
var Vader = artifacts.require('./Vader')
var VSD = artifacts.require('./VSD')
const BigNumber = require('bignumber.js')
const truffleAssert = require('truffle-assertions')

function BN2Str(BN) { return ((new BigNumber(BN)).toFixed()) }
function getBN(BN) { return (new BigNumber(BN)) }

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

var utils; var vader; var vether; var usdv;
var acc0; var acc1; var acc2; var acc3; var acc0; var acc5;
const one = 10**18

before(async function() {
  accounts = await ethers.getSigners();
  acc0 = await accounts[0].getAddress()
  acc1 = await accounts[1].getAddress()
  acc2 = await accounts[2].getAddress()
  acc3 = await accounts[3].getAddress()

  utils = await Utils.new();
  vether = await Vether.new();
  vader = await Vader.new(vether.address);
  usdv = await VSD.new(vader.address, utils.address);

  await vether.transfer(acc1, BN2Str(1001))
// acc  | VTH | VADER  |
// acc0 |   0 |    0 |
// acc1 |1001 |    0 |

})

describe("Deploy", function() {
  it("Should deploy", async function() {
    expect(await vader.name()).to.equal("VADER PROTOCOL TOKEN");
    expect(await vader.symbol()).to.equal("VADER");
    expect(BN2Str(await vader.decimals())).to.equal('18');
    expect(BN2Str(await vader.totalSupply())).to.equal('0');
    expect(BN2Str(await vader.maxSupply())).to.equal(BN2Str(2000000 * one));
    expect(BN2Str(await vader.emissionCurve())).to.equal('2048');
    expect(await vader.emitting()).to.equal(false);
    expect(BN2Str(await vader.currentEra())).to.equal('1');
    expect(BN2Str(await vader.secondsPerEra())).to.equal('1');
    // console.log(BN2Str(await vader.nextEraTime()));
    expect(await vader.DAO()).to.equal(acc0);
    expect(await vader.burnAddress()).to.equal("0x0111011001100001011011000111010101100101");
    expect(BN2Str(await vader.getDailyEmission())).to.equal(BN2Str('0'));
  });
});

describe("Upgrade", function() {

  it("Should upgrade acc1", async function() {
    await vether.approve(vader.address, '1000', {from:acc1})
    expect(BN2Str(await vether.allowance(acc1, vader.address))).to.equal(BN2Str(1000));
    await vader.upgrade(1000, {from:acc1})
    expect(BN2Str(await vader.totalSupply())).to.equal(BN2Str(1000));
    expect(BN2Str(await vether.balanceOf(acc1))).to.equal(BN2Str(0));
    expect(BN2Str(await vader.balanceOf(acc1))).to.equal(BN2Str(1000));
    expect(BN2Str(await vader.getDailyEmission())).to.equal(BN2Str('0'));
  });
// acc  | VTH | VADER  |
// acc0 |   0 |    0 |
// acc1 |   0 | 1000 |

});

describe("Be a valid ERC-20", function() {
  it("Should transfer From", async function() {
    await vader.approve(acc0, "100", {from:acc1}) 
    expect(BN2Str(await vader.allowance(acc1, acc0))).to.equal('100');
    await vader.transferFrom(acc1, acc0, "100", {from:acc0})
    expect(BN2Str(await vader.balanceOf(acc0))).to.equal('100');
  });
// acc  | VTH | VADER  |
// acc0 |   0 |  100 |
// acc1 |   0 |  900 |

  it("Should transfer to", async function() {
    await vader.transferTo(acc0, "100", {from:acc1}) 
    expect(BN2Str(await vader.balanceOf(acc0))).to.equal('200');
  });
// acc  | VTH | VADER  |
// acc0 |   0 |  200 |
// acc1 |   0 |  800 |

  it("Should burn", async function() {
    await vader.burn("100", {from:acc0})
    expect(BN2Str(await vader.balanceOf(acc0))).to.equal('100');
    expect(BN2Str(await vader.totalSupply())).to.equal(BN2Str('900'));
  });
// acc  | VTH | VADER  |
// acc0 |   0 |  100 |
// acc1 |   0 |  800 |

  it("Should burn from", async function() {
    await vader.approve(acc1, "100", {from:acc0}) 
    expect(BN2Str(await vader.allowance(acc0, acc1))).to.equal('100');
    await vader.burnFrom(acc0, "100", {from:acc1})
    expect(BN2Str(await vader.balanceOf(acc0))).to.equal('0');
    expect(BN2Str(await vader.totalSupply())).to.equal(BN2Str('800'));
  });
// acc  | VTH | VADER  |
// acc0 |   0 |  0   |
// acc1 |   0 |  800 |

});

describe("DAO Functions", function() {
  it("Non-DAO fails", async function() {
    await truffleAssert.reverts(vader.startEmissions({from:acc1}))
  });
  it("DAO changeEmissionCurve", async function() {
    await vader.changeEmissionCurve('1')
    expect(BN2Str(await vader.emissionCurve())).to.equal('1');
  });
  it("DAO changeIncentiveAddress", async function() {
    await vader.setVSD(usdv.address)
    expect(await vader.VSD()).to.equal(usdv.address);
  });
  it("DAO changeDAO", async function() {
    await vader.changeDAO(acc2)
    expect(await vader.DAO()).to.equal(acc2);
  });
  it("DAO start emitting", async function() {
    await vader.startEmissions({from:acc2})
    expect(await vader.emitting()).to.equal(true);
  });
  
  it("Old DAO fails", async function() {
    await truffleAssert.reverts(vader.startEmissions())
  });
});

describe("Emissions", function() {
  it("Should emit properly", async function() {
    expect(BN2Str(await vader.getDailyEmission())).to.equal(BN2Str('800'));
// 
    // await sleep(2000)
    await vader.transfer(acc0, BN2Str(200), {from:acc1})
    await vader.transfer(acc1, BN2Str(100), {from:acc0})
// acc  | VTH | VADER  |
// acc0 |   0 |  100 |
// acc1 |   0 |  800 |

    expect(BN2Str(await vader.currentEra())).to.equal('3');
    expect(BN2Str(await vader.balanceOf(usdv.address))).to.equal(BN2Str('2400'));
    expect(BN2Str(await vader.getDailyEmission())).to.equal(BN2Str('3200'));
    
    // await sleep(2000)
    await vader.transfer(acc0, BN2Str(100), {from:acc1})
// acc  | VTH | VADER  |
// acc0 |   0 |  200 |
// acc1 |   0 |  800 |
    expect(BN2Str(await vader.currentEra())).to.equal('4');
    expect(BN2Str(await vader.balanceOf(usdv.address))).to.equal(BN2Str('5600'));
    expect(BN2Str(await vader.getDailyEmission())).to.equal(BN2Str('6400'));
  });

  it("DAO changeEraDuration", async function() {
    await vader.changeEraDuration('200',{from:acc2})
    expect(BN2Str(await vader.secondsPerEra())).to.equal('200');
  });
});


