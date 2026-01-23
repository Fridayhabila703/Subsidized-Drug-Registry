import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;

/*
  Drug Price History Tracking System - Simple Tests
  Basic functionality tests to ensure contract deployment and core features work
*/

describe("Drug Price History Tracking System - Simple Tests", () => {
  
  it("ensures simnet and contract are initialized", () => {
    expect(simnet.blockHeight).toBeDefined();
  });

  it("returns correct initial values", () => {
    const entryId = simnet.callReadOnlyFn("drug-price-history", "get-next-entry-id", [], deployer);
    expect(entryId.result).toBeUint(1);
    
    const alertId = simnet.callReadOnlyFn("drug-price-history", "get-next-alert-id", [], deployer);
    expect(alertId.result).toBeUint(1);
    
    const fee = simnet.callReadOnlyFn("drug-price-history", "get-recording-fee", [], deployer);
    expect(fee.result).toBeUint(100000);
  });

  it("returns contract info as tuple", () => {
    const contractInfo = simnet.callReadOnlyFn(
      "drug-price-history",
      "get-contract-info",
      [],
      deployer
    );

    expect(contractInfo.result).toBeTuple({
      "contract-owner": Cl.standardPrincipal(deployer),
      "next-entry-id": Cl.uint(1),
      "next-alert-id": Cl.uint(1),
      "recording-fee": Cl.uint(100000),
      "deployed-at": expect.anything(),
    });
  });

  it("returns none for non-existent drug", () => {
    const nonExistentPrice = simnet.callReadOnlyFn(
      "drug-price-history",
      "get-current-price",
      [Cl.stringAscii("NON-EXISTENT-DRUG")],
      deployer
    );
    expect(nonExistentPrice.result).toBeNone();

    const nonExistentStats = simnet.callReadOnlyFn(
      "drug-price-history",
      "get-drug-statistics",
      [Cl.stringAscii("NON-EXISTENT-DRUG")],
      deployer
    );
    expect(nonExistentStats.result).toBeNone();
  });

  it("returns none for non-existent price entries", () => {
    const nonExistentEntry = simnet.callReadOnlyFn(
      "drug-price-history",
      "get-price-entry",
      [Cl.uint(9999)],
      deployer
    );
    expect(nonExistentEntry.result).toBeNone();
  });

  it("allows deployer to register drug for tracking", () => {
    const registerResult = simnet.callPublicFn(
      "drug-price-history",
      "register-drug-for-tracking",
      [
        Cl.stringAscii("PARACETAMOL-500MG"),
        Cl.stringAscii("Paracetamol 500mg Tablets"),
        Cl.stringAscii("Pain Relief"),
        Cl.uint(1000000),
      ],
      deployer
    );
    expect(registerResult.result).toBeOk(Cl.bool(true));

    const drugInfo = simnet.callReadOnlyFn(
      "drug-price-history",
      "get-tracked-drug",
      [Cl.stringAscii("PARACETAMOL-500MG")],
      deployer
    );
    expect(drugInfo.result).toBeSome(expect.anything());

    const drug = (drugInfo.result as any).value;
    expect(drug).toBeTuple({
      name: Cl.stringAscii("Paracetamol 500mg Tablets"),
      category: Cl.stringAscii("Pain Relief"),
      "registered-by": Cl.standardPrincipal(deployer),
      "registration-date": expect.anything(),
      active: Cl.bool(true),
      "initial-price": Cl.uint(1000000),
    });
  });

  it("initializes price data correctly", () => {
    const currentPrice = simnet.callReadOnlyFn(
      "drug-price-history",
      "get-current-price",
      [Cl.stringAscii("PARACETAMOL-500MG")],
      deployer
    );
    expect(currentPrice.result).toBeSome(expect.anything());

    const price = (currentPrice.result as any).value;
    expect(price).toBeTuple({
      price: Cl.uint(1000000),
      "last-updated": expect.anything(),
      "last-entry-id": Cl.uint(0),
      "update-count": Cl.uint(1),
    });

    const stats = simnet.callReadOnlyFn(
      "drug-price-history",
      "get-drug-statistics",
      [Cl.stringAscii("PARACETAMOL-500MG")],
      deployer
    );
    expect(stats.result).toBeSome(expect.anything());

    const statistics = (stats.result as any).value;
    expect(statistics).toBeTuple({
      "min-price": Cl.uint(1000000),
      "max-price": Cl.uint(1000000),
      "average-price": Cl.uint(1000000),
      "total-entries": Cl.uint(1),
      "first-recorded": expect.anything(),
      "last-updated": expect.anything(),
      "volatility-score": Cl.uint(0),
    });
  });

  it("prevents duplicate drug registration", () => {
    const duplicateResult = simnet.callPublicFn(
      "drug-price-history",
      "register-drug-for-tracking",
      [
        Cl.stringAscii("PARACETAMOL-500MG"),
        Cl.stringAscii("Aspirin Different"),
        Cl.stringAscii("Different Category"),
        Cl.uint(900000),
      ],
      deployer
    );
    expect(duplicateResult.result).toBeErr(Cl.uint(207));
  });

  it("allows owner to authorize price recorders", () => {
    const authResult = simnet.callPublicFn(
      "drug-price-history",
      "authorize-price-recorder",
      [Cl.standardPrincipal(wallet1), Cl.stringAscii("PARACETAMOL-500MG")],
      deployer
    );
    expect(authResult.result).toBeOk(Cl.bool(true));

    const isAuthorized = simnet.callReadOnlyFn(
      "drug-price-history",
      "is-price-recorder-authorized",
      [Cl.standardPrincipal(wallet1), Cl.stringAscii("PARACETAMOL-500MG")],
      deployer
    );
    expect(isAuthorized.result).toBeBool(true);
  });

  it("allows authorized users to record price changes", () => {
    const recordResult = simnet.callPublicFn(
      "drug-price-history",
      "record-price-change",
      [
        Cl.stringAscii("PARACETAMOL-500MG"),
        Cl.uint(1200000),
        Cl.stringAscii("Market price increase"),
      ],
      wallet1
    );
    expect(recordResult.result).toBeOk(Cl.uint(1));

    const newPrice = simnet.callReadOnlyFn(
      "drug-price-history",
      "get-current-price",
      [Cl.stringAscii("PARACETAMOL-500MG")],
      deployer
    );
    expect(newPrice.result).toBeSome(expect.anything());

    const priceData = (newPrice.result as any).value;
    expect(priceData).toBeTuple({
      price: Cl.uint(1200000),
      "last-updated": expect.anything(),
      "last-entry-id": Cl.uint(1),
      "update-count": Cl.uint(2),
    });
  });

  it("prevents unauthorized users from recording prices", () => {
    const unauthorizedRecord = simnet.callPublicFn(
      "drug-price-history",
      "record-price-change",
      [
        Cl.stringAscii("PARACETAMOL-500MG"),
        Cl.uint(1300000),
        Cl.stringAscii("Unauthorized attempt"),
      ],
      wallet2
    );
    expect(unauthorizedRecord.result).toBeErr(Cl.uint(200));
  });

  it("allows owner to set recording fee", () => {
    const setFeeResult = simnet.callPublicFn(
      "drug-price-history",
      "set-recording-fee",
      [Cl.uint(200000)],
      deployer
    );
    expect(setFeeResult.result).toBeOk(Cl.bool(true));

    const newFee = simnet.callReadOnlyFn("drug-price-history", "get-recording-fee", [], deployer);
    expect(newFee.result).toBeUint(200000);
  });

  it("prevents non-owner from setting fee", () => {
    const unauthorizedFee = simnet.callPublicFn(
      "drug-price-history",
      "set-recording-fee",
      [Cl.uint(300000)],
      wallet1
    );
    expect(unauthorizedFee.result).toBeErr(Cl.uint(200));
  });
});
