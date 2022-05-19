// NOTE: cloned from sushiswap canary #45da9720

const { ADDRESS_ZERO, advanceBlock, advanceBlockTo, advanceTime, advanceTimeAndBlock, deploy, getBigNumber, prepare } = require("./utilities");
const { assert, expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");

describe("SingleChef", function () {
  let custodian = null;

  before(async function () {
    const signers = await ethers.getSigners();
    custodian = signers[4];

    await prepare(this, ["SingleChef", "ERC20Mock"])
  })

  beforeEach(async function () {
    await deploy(this, [
      ["token", this.ERC20Mock, ["ARDN mock", "ARDN", getBigNumber(0)]]
    ])

    await deploy(this, [
      ["chef", this.SingleChef, [this.token.address, custodian.address]]
    ])

    await this.token.mint(custodian.address, getBigNumber(10000))
    await this.token.mint(this.alice.address, getBigNumber(10000))
    await this.token.connect(this.alice).approve(this.chef.address, ethers.constants.MaxUint256);
    await this.token.connect(custodian).approve(this.chef.address, ethers.constants.MaxUint256);
    await this.chef.setTokenPerSecond("10000000000000000")
  })

  describe("PendingToken", function () {
    it("PendingToken should equal ExpectedToken", async function () {
      let log = await this.chef.deposit(getBigNumber(1), this.alice.address)
      await advanceTime(86400)
      let log2 = await this.chef.updatePool()
      let timestamp2 = (await ethers.provider.getBlock(log2.blockNumber)).timestamp
      let timestamp = (await ethers.provider.getBlock(log.blockNumber)).timestamp
      let expectedToken = BigNumber.from("10000000000000000").mul(timestamp2 - timestamp)
      let pendingToken = await this.chef.pendingToken(this.alice.address)
      expect(pendingToken).to.be.equal(expectedToken)
    })

    it("When time is lastRewardTime", async function () {
      let log = await this.chef.deposit(getBigNumber(1), this.alice.address)
      await advanceBlockTo(3)
      let log2 = await this.chef.updatePool()
      let timestamp2 = (await ethers.provider.getBlock(log2.blockNumber)).timestamp
      let timestamp = (await ethers.provider.getBlock(log.blockNumber)).timestamp
      let expectedToken = BigNumber.from("10000000000000000").mul(timestamp2 - timestamp)
      let pendingToken = await this.chef.pendingToken(this.alice.address)
      expect(pendingToken).to.be.equal(expectedToken)
    })
  })

  describe("UpdatePool", function () {
    it("Should emit event LogUpdatePool", async function () {
      await advanceBlockTo(1)
      await expect(this.chef.updatePool())
        .to.emit(this.chef, "LogUpdatePool")
        .withArgs(
          (await this.chef.lastRewardTime()),
          await this.token.balanceOf(this.chef.address),
          (await this.chef.accTokenPerShare())
        )
    })
  })

  describe("Deposit", function () {
    it("Depositing 0 amount", async function () {
      await expect(this.chef.deposit(getBigNumber(0), this.alice.address))
        .to.emit(this.chef, "Deposit")
        .withArgs(this.alice.address, 0, this.alice.address)
    })

    it("Depositing 10 amount", async function () {
      await expect(this.chef.deposit(getBigNumber(10), this.alice.address))
        .to.emit(this.chef, "Deposit")
        .withArgs(this.alice.address, getBigNumber(10), this.alice.address)

      let userInfo = await this.chef.userInfo(this.alice.address);
      expect(userInfo.amount).to.be.equal(getBigNumber(10));
    })
  })

  describe("Withdraw", function () {
    it("Withdraw 0 amount", async function () {
      await expect(this.chef.withdraw(getBigNumber(0), this.alice.address))
        .to.emit(this.chef, "Withdraw")
        .withArgs(this.alice.address, 0, this.alice.address)
    })
  })

  describe("Harvest", function () {
    it("Should give back the correct amount of TOKEN", async function () {
      const initialBalance = await this.token.balanceOf(this.alice.address);

      let log = await this.chef.deposit(getBigNumber(1), this.alice.address)
      await advanceTime(86400)
      let log2 = await this.chef.withdraw(getBigNumber(1), this.alice.address)

      let timestamp2 = (await ethers.provider.getBlock(log2.blockNumber)).timestamp
      let timestamp = (await ethers.provider.getBlock(log.blockNumber)).timestamp

      let expectedToken = BigNumber.from("10000000000000000").mul(timestamp2 - timestamp);
      expect((await this.chef.userInfo(this.alice.address)).rewardDebt).to.be.equal("-" + expectedToken)

      await this.chef.harvest(this.alice.address)

      expect(await this.token.balanceOf(this.alice.address)).to.be.equal(expectedToken.add(initialBalance))
    })
    it("Harvest with empty user balance", async function () {
      await this.chef.harvest(this.alice.address)
    })
  })

  describe("EmergencyWithdraw", function () {
    it("Should emit event EmergencyWithdraw", async function () {
      await this.chef.deposit(getBigNumber(1), this.bob.address)
      await expect(this.chef.connect(this.bob).emergencyWithdraw(this.bob.address))
        .to.emit(this.chef, "EmergencyWithdraw")
        .withArgs(this.bob.address, getBigNumber(1), this.bob.address)
    })
  })
})
