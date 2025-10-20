import { describe, expect, it } from "vitest";

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
    
    const info = contractInfo.result.expectTuple();
    expect(info["contract-owner"]).toBeStandardPrincipal(deployer);
    expect(info["next-entry-id"]).toBeUint(1);
    expect(info["next-alert-id"]).toBeUint(1);
    expect(info["recording-fee"]).toBeUint(100000);
  });

  it("returns none for non-existent drug", () => {
    const nonExistentPrice = simnet.callReadOnlyFn(
      "drug-price-history",
      "get-current-price",
      ["NON-EXISTENT-DRUG"],
      deployer
    );
    expect(nonExistentPrice.result).toBeNone();
    
    const nonExistentStats = simnet.callReadOnlyFn(
      "drug-price-history",
      "get-drug-statistics",
      ["NON-EXISTENT-DRUG"],
      deployer
    );
    expect(nonExistentStats.result).toBeNone();
  });

  it("returns none for non-existent price entries", () => {
    const nonExistentEntry = simnet.callReadOnlyFn(
      "drug-price-history",
      "get-price-entry",
      [9999],
      deployer
    );
    expect(nonExistentEntry.result).toBeNone();
  });

  it("allows deployer to register drug for tracking", () => {
    const registerResult = simnet.callPublicFn(
      "drug-price-history",
      "register-drug-for-tracking",
      [
        "PARACETAMOL-500MG",
        "Paracetamol 500mg Tablets",
        "Pain Relief",
        1000000 // 1 STX initial price
      ],
      deployer
    );
    expect(registerResult.result).toBeOk(true);
    
    // Verify drug was registered
    const drugInfo = simnet.callReadOnlyFn(
      "drug-price-history",
      "get-tracked-drug",
      ["PARACETAMOL-500MG"],
      deployer
    );
    expect(drugInfo.result).toBeSome();
    
    const drug = drugInfo.result.expectSome().expectTuple();
    expect(drug["name"]).toBeAscii("Paracetamol 500mg Tablets");
    expect(drug["category"]).toBeAscii("Pain Relief");
    expect(drug["registered-by"]).toBeStandardPrincipal(deployer);
    expect(drug["active"]).toBeBool(true);
    expect(drug["initial-price"]).toBeUint(1000000);
  });

  it("initializes price data correctly", () => {
    // Check current price was set
    const currentPrice = simnet.callReadOnlyFn(
      "drug-price-history",
      "get-current-price",
      ["PARACETAMOL-500MG"],
      deployer
    );
    expect(currentPrice.result).toBeSome();
    
    const price = currentPrice.result.expectSome().expectTuple();
    expect(price["price"]).toBeUint(1000000);
    expect(price["update-count"]).toBeUint(1);
    
    // Check statistics were initialized
    const stats = simnet.callReadOnlyFn(
      "drug-price-history",
      "get-drug-statistics",
      ["PARACETAMOL-500MG"],
      deployer
    );
    expect(stats.result).toBeSome();
    
    const statistics = stats.result.expectSome().expectTuple();
    expect(statistics["min-price"]).toBeUint(1000000);
    expect(statistics["max-price"]).toBeUint(1000000);
    expect(statistics["average-price"]).toBeUint(1000000);
    expect(statistics["total-entries"]).toBeUint(1);
    expect(statistics["volatility-score"]).toBeUint(0);
  });

  it("prevents duplicate drug registration", () => {
    // Try to register same drug again
    const duplicateResult = simnet.callPublicFn(
      "drug-price-history",
      "register-drug-for-tracking",
      ["PARACETAMOL-500MG", "Aspirin Different", "Different Category", 900000],
      deployer
    );
    expect(duplicateResult.result).toBeErr(207); // ERR_ALREADY_EXISTS
  });

  it("allows owner to authorize price recorders", () => {
    const authResult = simnet.callPublicFn(
      "drug-price-history",
      "authorize-price-recorder",
      [wallet1, "PARACETAMOL-500MG"],
      deployer
    );
    expect(authResult.result).toBeOk(true);
    
    // Verify authorization
    const isAuthorized = simnet.callReadOnlyFn(
      "drug-price-history",
      "is-price-recorder-authorized",
      [wallet1, "PARACETAMOL-500MG"],
      deployer
    );
    expect(isAuthorized.result).toBeBool(true);
  });

  it("allows authorized users to record price changes", () => {
    // Record price change
    const recordResult = simnet.callPublicFn(
      "drug-price-history",
      "record-price-change",
      ["PARACETAMOL-500MG", 1200000, "Market price increase"],
      wallet1
    );
    expect(recordResult.result).toBeOk(1); // Entry ID 1
    
    // Verify price was updated
    const newPrice = simnet.callReadOnlyFn(
      "drug-price-history",
      "get-current-price",
      ["PARACETAMOL-500MG"],
      deployer
    );
    const priceData = newPrice.result.expectSome().expectTuple();
    expect(priceData["price"]).toBeUint(1200000);
    expect(priceData["update-count"]).toBeUint(2); // Initial + this update
  });

  it("prevents unauthorized users from recording prices", () => {
    const unauthorizedRecord = simnet.callPublicFn(
      "drug-price-history",
      "record-price-change",
      ["PARACETAMOL-500MG", 1300000, "Unauthorized attempt"],
      wallet2 // Not authorized
    );
    expect(unauthorizedRecord.result).toBeErr(200); // ERR_UNAUTHORIZED
  });

  it("allows owner to set recording fee", () => {
    const setFeeResult = simnet.callPublicFn(
      "drug-price-history",
      "set-recording-fee",
      [200000], // New fee: 0.2 STX
      deployer
    );
    expect(setFeeResult.result).toBeOk(true);
    
    const newFee = simnet.callReadOnlyFn("drug-price-history", "get-recording-fee", [], deployer);
    expect(newFee.result).toBeUint(200000);
  });

  it("prevents non-owner from setting fee", () => {
    const unauthorizedFee = simnet.callPublicFn(
      "drug-price-history",
      "set-recording-fee",
      [300000],
      wallet1
    );
    expect(unauthorizedFee.result).toBeErr(200); // ERR_UNAUTHORIZED
  });
});
