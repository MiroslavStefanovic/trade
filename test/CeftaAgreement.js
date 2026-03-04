import { expect } from "chai";
import { network } from "hardhat";

const { ethers } = await network.connect();

const ACTION = {
  AddMember: 0,
  RemoveMember: 1,
  AddHSCode: 2,
  SetQuota: 3,
  SetAgreementActive: 4,
  SetCeftaTrade: 5,
};

function encodeAction(actionType, types, values) {
  const abiCoder = ethers.AbiCoder.defaultAbiCoder();
  const params = abiCoder.encode(types, values);
  const payload = abiCoder.encode(["uint8", "bytes"], [actionType, params]);
  const actionId = ethers.keccak256(payload);

  return { payload, actionId };
}

async function approveAll(governance, actionId, approvers) {
  for (const approver of approvers) {
    await governance.connect(approver).approveAction(actionId);
  }
}

async function configureAnnex(
  governance,
  actor,
  approvals,
  exporterCountry,
  importerCountry,
  hsCode,
  quota,
) {
  const { payload: quotaPayload, actionId: quotaActionId } = encodeAction(
    ACTION.SetQuota,
    ["uint16", "uint16", "string", "uint256"],
    [exporterCountry, importerCountry, hsCode, quota],
  );
  await governance.connect(actor).proposeAction(quotaActionId, quotaPayload);
  await approveAll(governance, quotaActionId, approvals);
  await governance.connect(actor).executeAction(quotaActionId);
}

async function deployAgreement() {
  const [alice, bob, carol] = await ethers.getSigners();
  const agreement = await ethers.deployContract("CeftaAgreement", [
    [alice.address, bob.address, carol.address],
  ]);
  const governance = await ethers.deployContract("CeftaGovernance", [
    await agreement.getAddress(),
  ]);
  await agreement.connect(alice).setGovernance(await governance.getAddress());

  return { agreement, governance, alice, bob, carol };
}

async function enableTradeEnvironment(agreement, governance, alice, bob, carol) {
  const { payload: activatePayload, actionId: activateActionId } = encodeAction(
    ACTION.SetAgreementActive,
    ["bool"],
    [true],
  );
  await governance.connect(alice).proposeAction(activateActionId, activatePayload);
  await approveAll(governance, activateActionId, [bob, carol]);
  await governance.connect(alice).executeAction(activateActionId);
}

async function addHs(governance, alice, bob, carol, hsCode) {
  const { payload, actionId } = encodeAction(
    ACTION.AddHSCode,
    ["string"],
    [hsCode],
  );
  await governance.connect(alice).proposeAction(actionId, payload);
  await approveAll(governance, actionId, [bob, carol]);
  await governance.connect(alice).executeAction(actionId);
}

async function addMember(governance, alice, bob, carol, member, country) {
  const { payload, actionId } = encodeAction(
    ACTION.AddMember,
    ["address", "uint16"],
    [member, country],
  );
  await governance.connect(alice).proposeAction(actionId, payload);
  await approveAll(governance, actionId, [bob, carol]);
  await governance.connect(alice).executeAction(actionId);
}

async function setTradeAddress(governance, alice, bob, carol, tradeAddress) {
  const { payload, actionId } = encodeAction(
    ACTION.SetCeftaTrade,
    ["address"],
    [tradeAddress],
  );
  await governance.connect(alice).proposeAction(actionId, payload);
  await approveAll(governance, actionId, [bob, carol]);
  await governance.connect(alice).executeAction(actionId);
}

describe("CeftaAgreement governance", function () {
  it("requires unanimous approval to execute actions", async function () {
    const { agreement, governance, alice, bob, carol } = await deployAgreement();
    const [, , , dave] = await ethers.getSigners();

    const { payload, actionId } = encodeAction(
      ACTION.AddMember,
      ["address", "uint16"],
      [dave.address, 710],
    );

    await governance.connect(alice).proposeAction(actionId, payload);
    await governance.connect(bob).approveAction(actionId);

    await expect(
      governance.connect(alice).executeAction(actionId),
    ).to.be.revertedWith("Not fully approved");

    await governance.connect(carol).approveAction(actionId);
    await governance.connect(alice).executeAction(actionId);

    expect(await agreement.isMember(dave.address)).to.equal(true);
  });

  it("requires removed member approval", async function () {
    const { agreement, governance, alice, bob, carol } = await deployAgreement();

    const { payload, actionId } = encodeAction(
      ACTION.RemoveMember,
      ["address"],
      [carol.address],
    );

    await governance.connect(alice).proposeAction(actionId, payload);
    await governance.connect(bob).approveAction(actionId);

    await expect(
      governance.connect(alice).executeAction(actionId),
    ).to.be.revertedWith("Not fully approved");

    await governance.connect(carol).approveAction(actionId);
    await governance.connect(alice).executeAction(actionId);

    expect(await agreement.isMember(carol.address)).to.equal(false);
  });

  it("adds member with country via governance", async function () {
    const { agreement, governance, alice, bob, carol } = await deployAgreement();

    await addMember(governance, alice, bob, carol, bob.address, 499);

    const members = await agreement.getMembers();
    const updated = members.find((member) => member.account === bob.address);
    expect(updated?.country).to.equal(499n);
  });

  it("prevents non-members from proposing or approving", async function () {
    const { governance, alice } = await deployAgreement();
    const [, , , dave] = await ethers.getSigners();

    const { payload, actionId } = encodeAction(
      ACTION.AddHSCode,
      ["string"],
      ["1001"],
    );

    await expect(
      governance.connect(dave).proposeAction(actionId, payload),
    ).to.be.revertedWith("Not a member");

    await governance.connect(alice).proposeAction(actionId, payload);

    await expect(
      governance.connect(dave).approveAction(actionId),
    ).to.be.revertedWith("Not a member");
  });

  it("requires removed member approval even after unanimous approvals", async function () {
    const { governance, alice, bob, carol } = await deployAgreement();

    const { payload, actionId } = encodeAction(
      ACTION.RemoveMember,
      ["address"],
      [carol.address],
    );

    await governance.connect(alice).proposeAction(actionId, payload);
    await governance.connect(bob).approveAction(actionId);

    await expect(
      governance.connect(alice).executeAction(actionId),
    ).to.be.revertedWith("Not fully approved");

    await governance.connect(carol).approveAction(actionId);

    await governance.connect(alice).executeAction(actionId);
  });
});

describe("CeftaAgreement setters", function () {
  it("rejects non-governance calls for setters", async function () {
    const { agreement, governance, alice, bob, carol } = await deployAgreement();
    const [, , , dave] = await ethers.getSigners();

    await expect(
      agreement.connect(dave).setHSCode("1001"),
    ).to.be.revertedWith("Not governance");

    await addMember(governance, alice, bob, carol, dave.address, 499);

    await expect(
      agreement.connect(dave).addMember(dave.address, 498),
    ).to.be.revertedWith("Not governance");
  });

  it("rejects invalid governance set attempts", async function () {
    const [alice] = await ethers.getSigners();
    const agreement = await ethers.deployContract("CeftaAgreement", [
      [alice.address],
    ]);

    await expect(
      agreement.connect(alice).setGovernance(ethers.ZeroAddress),
    ).to.be.revertedWith("Invalid governance");
  });

  it("rejects non-admin governance assignment", async function () {
    const [alice, bob] = await ethers.getSigners();
    const agreement = await ethers.deployContract("CeftaAgreement", [
      [alice.address],
    ]);
    const governance = await ethers.deployContract("CeftaGovernance", [
      await agreement.getAddress(),
    ]);

    await expect(
      agreement.connect(bob).setGovernance(await governance.getAddress()),
    ).to.be.revertedWith("Not admin");
  });

  it("rejects governance mismatches", async function () {
    const [alice] = await ethers.getSigners();
    const agreementA = await ethers.deployContract("CeftaAgreement", [
      [alice.address],
    ]);
    const agreementB = await ethers.deployContract("CeftaAgreement", [
      [alice.address],
    ]);
    const governanceB = await ethers.deployContract("CeftaGovernance", [
      await agreementB.getAddress(),
    ]);

    await expect(
      agreementA.connect(alice).setGovernance(await governanceB.getAddress()),
    ).to.be.revertedWith("Governance mismatch");
  });
});

describe("Cefta trade", function () {
  async function setupAgreement() {
    const { agreement, governance, alice, bob, carol } = await deployAgreement();

    await enableTradeEnvironment(agreement, governance, alice, bob, carol);

    await addHs(governance, alice, bob, carol, "1001");
    await addHs(governance, alice, bob, carol, "2001");
    await addHs(governance, alice, bob, carol, "3001");

    await addMember(governance, alice, bob, carol, alice.address, 499);
    await addMember(governance, alice, bob, carol, bob.address, 688);

    return { agreement, governance, alice, bob, carol };
  }

  it("enforces annex rules and quota consumption", async function () {
    const { agreement, governance, alice, bob, carol } = await setupAgreement();

    await configureAnnex(
      governance,
      alice,
      [bob, carol],
      499,
      688,
      "1001",
      100,
    );

    const factory = await ethers.deployContract("CeftaTrade", [
      await agreement.getAddress(),
    ]);

    await setTradeAddress(
      governance,
      alice,
      bob,
      carol,
      await factory.getAddress(),
    );

    expect(await agreement.ceftaTrade()).to.equal(await factory.getAddress());

    const tradeTx = await factory.connect(alice).submitTrade({
      hsCode: "1001",
      quantity: 10,
      value: 1000,
      exporter: {
        account: alice.address,
        country: 499,
      },
      importer: {
        account: bob.address,
        country: 688,
      },
    });
    const tradeReceipt = await tradeTx.wait();
    const tradeId = tradeReceipt.logs[0].args.tradeId;

    await factory.connect(bob).signTrade(tradeId);

    const remaining = await agreement.quotaAvailable(499, 688, "1001");
    expect(remaining).to.equal(90n);
  });

  it("rejects unknown HS codes", async function () {
    const { agreement, governance, alice, bob, carol } = await setupAgreement();

    const factory = await ethers.deployContract("CeftaTrade", [
      await agreement.getAddress(),
    ]);

    await setTradeAddress(
      governance,
      alice,
      bob,
      carol,
      await factory.getAddress(),
    );

    await expect(
      factory.connect(alice).submitTrade({
        hsCode: "9999",
        quantity: 10,
        value: 1000,
        exporter: {
          account: alice.address,
          country: 499,
        },
        importer: {
          account: bob.address,
          country: 688,
        },
      }),
    ).to.be.revertedWith("HS not allowed");
  });

  it("rejects quota exceedance", async function () {
    const { agreement, governance, alice, bob, carol } = await setupAgreement();

    await configureAnnex(
      governance,
      alice,
      [bob, carol],
      499,
      688,
      "2001",
      5,
    );

    const factory = await ethers.deployContract("CeftaTrade", [
      await agreement.getAddress(),
    ]);

    await setTradeAddress(
      governance,
      alice,
      bob,
      carol,
      await factory.getAddress(),
    );

    const tradeTx = await factory.connect(alice).submitTrade({
      hsCode: "2001",
      quantity: 6,
      value: 1000,
      exporter: {
        account: alice.address,
        country: 499,
      },
      importer: {
        account: bob.address,
        country: 688,
      },
    });
    const tradeReceipt = await tradeTx.wait();
    const tradeId = tradeReceipt.logs[0].args.tradeId;

    await expect(factory.connect(bob).signTrade(tradeId)).to.be.revertedWith(
      "Quota exceeded",
    );
  });

  it("creates a trade contract and finalizes", async function () {
    const { agreement, governance, alice, bob, carol } = await setupAgreement();

    await configureAnnex(
      governance,
      alice,
      [bob, carol],
      499,
      688,
      "3001",
      50,
    );

    const factory = await ethers.deployContract("CeftaTrade", [
      await agreement.getAddress(),
    ]);

    await setTradeAddress(
      governance,
      alice,
      bob,
      carol,
      await factory.getAddress(),
    );

    const tradeTx = await factory.connect(alice).submitTrade({
      hsCode: "3001",
      quantity: 10,
      value: 1000,
      exporter: {
        account: alice.address,
        country: 499,
      },
      importer: {
        account: bob.address,
        country: 688,
      },
    });
    const tradeReceipt = await tradeTx.wait();
    const tradeId = tradeReceipt.logs[0].args.tradeId;

    const tradeAddress = await factory.connect(bob).signTrade.staticCall(tradeId);

    await factory.connect(bob).signTrade(tradeId);

    const trade = await ethers.getContractAt(
      "CeftaTradeContract",
      tradeAddress,
    );

    expect(await trade.active()).to.equal(true);
  });

  it("rejects non-member countries in submitTrade", async function () {
    const { agreement, governance, alice, bob, carol } = await setupAgreement();
    const [, , , dave] = await ethers.getSigners();

    const factory = await ethers.deployContract("CeftaTrade", [
      await agreement.getAddress(),
    ]);

    await setTradeAddress(
      governance,
      alice,
      bob,
      carol,
      await factory.getAddress(),
    );

    await expect(
      factory.connect(alice).submitTrade({
        hsCode: "1001",
        quantity: 10,
        value: 1000,
        exporter: {
          account: alice.address,
          country: 840,
        },
        importer: {
          account: bob.address,
          country: 688,
        },
      }),
    ).to.be.revertedWith("Exporter not member");

    await expect(
      factory.connect(alice).submitTrade({
        hsCode: "1001",
        quantity: 10,
        value: 1000,
        exporter: {
          account: alice.address,
          country: 499,
        },
        importer: {
          account: bob.address,
          country: 999,
        },
      }),
    ).to.be.revertedWith("Importer not member");

    await expect(
      factory.connect(dave).submitTrade({
        hsCode: "1001",
        quantity: 10,
        value: 1000,
        exporter: {
          account: alice.address,
          country: 499,
        },
        importer: {
          account: bob.address,
          country: 688,
        },
      }),
    ).to.be.revertedWith("Only exporter");
  });

  it("rejects zero quantity or value", async function () {
    const { agreement, governance, alice, bob, carol } = await setupAgreement();

    const factory = await ethers.deployContract("CeftaTrade", [
      await agreement.getAddress(),
    ]);

    await setTradeAddress(
      governance,
      alice,
      bob,
      carol,
      await factory.getAddress(),
    );

    await expect(
      factory.connect(alice).submitTrade({
        hsCode: "1001",
        quantity: 0,
        value: 1000,
        exporter: {
          account: alice.address,
          country: 499,
        },
        importer: {
          account: bob.address,
          country: 688,
        },
      }),
    ).to.be.revertedWith("Zero quantity");

    await expect(
      factory.connect(alice).submitTrade({
        hsCode: "1001",
        quantity: 10,
        value: 0,
        exporter: {
          account: alice.address,
          country: 499,
        },
        importer: {
          account: bob.address,
          country: 688,
        },
      }),
    ).to.be.revertedWith("Zero value");
  });

  it("updates trade values with dual approval", async function () {
    const { agreement, governance, alice, bob, carol } = await setupAgreement();

    await configureAnnex(
      governance,
      alice,
      [bob, carol],
      499,
      688,
      "1001",
      100,
    );

    const factory = await ethers.deployContract("CeftaTrade", [
      await agreement.getAddress(),
    ]);

    await setTradeAddress(
      governance,
      alice,
      bob,
      carol,
      await factory.getAddress(),
    );

    const tradeTx = await factory.connect(alice).submitTrade({
      hsCode: "1001",
      quantity: 10,
      value: 1000,
      exporter: {
        account: alice.address,
        country: 499,
      },
      importer: {
        account: bob.address,
        country: 688,
      },
    });
    const tradeReceipt = await tradeTx.wait();
    const tradeId = tradeReceipt.logs[0].args.tradeId;
    const tradeAddress = await factory.connect(bob).signTrade.staticCall(tradeId);
    await factory.connect(bob).signTrade(tradeId);

    const trade = await ethers.getContractAt(
      "CeftaTradeContract",
      tradeAddress,
    );

    await trade.connect(alice).approveUpdate(8, 900, true);
    await trade.connect(bob).approveUpdate(8, 900, true);

    expect(await trade.quantity()).to.equal(8n);
    expect(await trade.value()).to.equal(900n);
    expect(await trade.active()).to.equal(true);
    expect(await agreement.quotaAvailable(499, 688, "1001")).to.equal(92n);
  });

  it("rejects mismatched update approvals", async function () {
    const { agreement, governance, alice, bob, carol } = await setupAgreement();

    await configureAnnex(
      governance,
      alice,
      [bob, carol],
      499,
      688,
      "1001",
      100,
    );

    const factory = await ethers.deployContract("CeftaTrade", [
      await agreement.getAddress(),
    ]);

    await setTradeAddress(
      governance,
      alice,
      bob,
      carol,
      await factory.getAddress(),
    );

    const tradeTx = await factory.connect(alice).submitTrade({
      hsCode: "1001",
      quantity: 10,
      value: 1000,
      exporter: {
        account: alice.address,
        country: 499,
      },
      importer: {
        account: bob.address,
        country: 688,
      },
    });
    const tradeReceipt = await tradeTx.wait();
    const tradeId = tradeReceipt.logs[0].args.tradeId;
    const tradeAddress = await factory.connect(bob).signTrade.staticCall(tradeId);
    await factory.connect(bob).signTrade(tradeId);

    const trade = await ethers.getContractAt(
      "CeftaTradeContract",
      tradeAddress,
    );

    await trade.connect(alice).approveUpdate(8, 900, true);

    await expect(
      trade.connect(bob).approveUpdate(9, 900, true),
    ).to.be.revertedWith("Quantity mismatch");

    await expect(
      trade.connect(alice).approveUpdate(8, 900, true),
    ).to.be.revertedWith("Only counterparty");
  });

  it("updates quota when quantity increases", async function () {
    const { agreement, governance, alice, bob, carol } = await setupAgreement();

    await configureAnnex(
      governance,
      alice,
      [bob, carol],
      499,
      688,
      "1001",
      12,
    );

    const factory = await ethers.deployContract("CeftaTrade", [
      await agreement.getAddress(),
    ]);

    await setTradeAddress(
      governance,
      alice,
      bob,
      carol,
      await factory.getAddress(),
    );

    const tradeTx = await factory.connect(alice).submitTrade({
      hsCode: "1001",
      quantity: 10,
      value: 1000,
      exporter: {
        account: alice.address,
        country: 499,
      },
      importer: {
        account: bob.address,
        country: 688,
      },
    });
    const tradeReceipt = await tradeTx.wait();
    const tradeId = tradeReceipt.logs[0].args.tradeId;
    const tradeAddress = await factory.connect(bob).signTrade.staticCall(tradeId);
    await factory.connect(bob).signTrade(tradeId);

    const trade = await ethers.getContractAt(
      "CeftaTradeContract",
      tradeAddress,
    );

    await trade.connect(alice).approveUpdate(12, 1000, true);
    await trade.connect(bob).approveUpdate(12, 1000, true);

    expect(await agreement.quotaAvailable(499, 688, "1001")).to.equal(0n);
  });

  it("rejects quantity increase that exceeds quota", async function () {
    const { agreement, governance, alice, bob, carol } = await setupAgreement();

    await configureAnnex(
      governance,
      alice,
      [bob, carol],
      499,
      688,
      "1001",
      11,
    );

    const factory = await ethers.deployContract("CeftaTrade", [
      await agreement.getAddress(),
    ]);

    await setTradeAddress(
      governance,
      alice,
      bob,
      carol,
      await factory.getAddress(),
    );

    const tradeTx = await factory.connect(alice).submitTrade({
      hsCode: "1001",
      quantity: 10,
      value: 1000,
      exporter: {
        account: alice.address,
        country: 499,
      },
      importer: {
        account: bob.address,
        country: 688,
      },
    });
    const tradeReceipt = await tradeTx.wait();
    const tradeId = tradeReceipt.logs[0].args.tradeId;
    const tradeAddress = await factory.connect(bob).signTrade.staticCall(tradeId);
    await factory.connect(bob).signTrade(tradeId);

    const trade = await ethers.getContractAt(
      "CeftaTradeContract",
      tradeAddress,
    );

    await trade.connect(alice).approveUpdate(12, 1000, true);

    await expect(
      trade.connect(bob).approveUpdate(12, 1000, true),
    ).to.be.revertedWith("Quota exceeded");
  });

  it("restricts trade mutations to authorized contracts", async function () {
    const { agreement, governance, alice, bob, carol } = await setupAgreement();

    await configureAnnex(
      governance,
      alice,
      [bob, carol],
      499,
      688,
      "1001",
      100,
    );

    await expect(
      agreement.updateTradeQuantity(499, 688, "1001", 1, 2),
    ).to.be.revertedWith("Not trade");

    await expect(
      agreement.recordTrade(
        { account: alice.address, country: 499 },
        { account: bob.address, country: 688 },
        "1001",
        1,
        1,
      ),
    ).to.be.revertedWith("Not trade");
  });
});

describe("E2E trade flow", function () {
  it("submits and signs a trade end-to-end", async function () {
    const { agreement, governance, alice, bob, carol } = await deployAgreement();

    await enableTradeEnvironment(agreement, governance, alice, bob, carol);
    await addHs(governance, alice, bob, carol, "1001");
    await addMember(governance, alice, bob, carol, alice.address, 499);
    await addMember(governance, alice, bob, carol, bob.address, 688);
    await configureAnnex(
      governance,
      alice,
      [bob, carol],
      499,
      688,
      "1001",
      20,
    );

    const factory = await ethers.deployContract("CeftaTrade", [
      await agreement.getAddress(),
    ]);
    await setTradeAddress(
      governance,
      alice,
      bob,
      carol,
      await factory.getAddress(),
    );

    const submitTx = await factory.connect(alice).submitTrade({
      hsCode: "1001",
      quantity: 5,
      value: 500,
      exporter: {
        account: alice.address,
        country: 499,
      },
      importer: {
        account: bob.address,
        country: 688,
      },
    });
    const submitReceipt = await submitTx.wait();
    const tradeId = submitReceipt.logs[0].args.tradeId;

    const tradeAddress = await factory.connect(bob).signTrade.staticCall(tradeId);
    await factory.connect(bob).signTrade(tradeId);

    const trade = await ethers.getContractAt(
      "CeftaTradeContract",
      tradeAddress,
    );
    expect(await trade.active()).to.equal(true);
    expect(await agreement.quotaAvailable(499, 688, "1001")).to.equal(15n);
  });

  it("rejects signing by non-importer", async function () {
    const { agreement, governance, alice, bob, carol } = await deployAgreement();

    await enableTradeEnvironment(agreement, governance, alice, bob, carol);
    await addHs(governance, alice, bob, carol, "1001");
    await addMember(governance, alice, bob, carol, alice.address, 499);
    await addMember(governance, alice, bob, carol, bob.address, 688);
    await configureAnnex(
      governance,
      alice,
      [bob, carol],
      499,
      688,
      "1001",
      20,
    );

    const factory = await ethers.deployContract("CeftaTrade", [
      await agreement.getAddress(),
    ]);
    await setTradeAddress(
      governance,
      alice,
      bob,
      carol,
      await factory.getAddress(),
    );

    const submitTx = await factory.connect(alice).submitTrade({
      hsCode: "1001",
      quantity: 5,
      value: 500,
      exporter: {
        account: alice.address,
        country: 499,
      },
      importer: {
        account: bob.address,
        country: 688,
      },
    });
    const submitReceipt = await submitTx.wait();
    const tradeId = submitReceipt.logs[0].args.tradeId;

    await expect(
      factory.connect(carol).signTrade(tradeId),
    ).to.be.revertedWith("Only importer");
  });
});
