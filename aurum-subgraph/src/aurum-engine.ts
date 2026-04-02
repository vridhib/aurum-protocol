import { BigInt, Address } from "@graphprotocol/graph-ts";
import { CollateralDeposited, CollateralRedeemed, MintAUSD, BurnAUSD, Liquidated} from "../generated/AurumEngine/AurumEngine";
import { User, Protocol, Liquidation } from "../generated/schema";


function getOrCreateUser(userAddress: Address): User {
  let id = userAddress.toHexString();
  let user = User.load(id);

  if (!user) {
    user = new User(id);
    user.collateral = BigInt.fromI32(0);
    user.debt = BigInt.fromI32(0);
    user.lastUpdated = BigInt.fromI32(0);
    // Increment totalUsers when a new user is created
    let protocol = getOrCreateProtocol();
    protocol.totalUsers++;
    protocol.save();
  }
  return user;
}


function getOrCreateProtocol(): Protocol {
  let protocol = Protocol.load("1");
  if (!protocol) {
    protocol = new Protocol("1");
    protocol.totalCollateral = BigInt.fromI32(0);
    protocol.totalDebt = BigInt.fromI32(0);
    protocol.totalUsers = 0;
  }
  return protocol;
}


export function handleCollateralDeposited(event: CollateralDeposited): void {
  let user = getOrCreateUser(event.params.user);
  user.collateral = user.collateral.plus(event.params.amount);
  user.lastUpdated = event.block.timestamp;
  user.save();

  let protocol = getOrCreateProtocol();
  protocol.totalCollateral = protocol.totalCollateral.plus(event.params.amount);
  protocol.save();
}


export function handleCollateralRedeemed(event: CollateralRedeemed): void {
  let user = getOrCreateUser(event.params.redeemedFrom);
  user.collateral = user.collateral.minus(event.params.amount);
  user.lastUpdated = event.block.timestamp;
  user.save();

  let protocol = getOrCreateProtocol();
  protocol.totalCollateral = protocol.totalCollateral.minus(event.params.amount);
  protocol.save();
}


export function handleMintAUSD(event: MintAUSD): void {
  let user = getOrCreateUser(event.params.user);
  user.debt = user.debt.plus(event.params.amount);
  user.lastUpdated = event.block.timestamp;
  user.save();

  let protocol = getOrCreateProtocol();
  protocol.totalDebt = protocol.totalDebt.plus(event.params.amount);
  protocol.save();
}


export function handleBurnAUSD(event: BurnAUSD): void {
  let user = getOrCreateUser(event.params.user);
  user.debt = user.debt.minus(event.params.amount);
  user.lastUpdated = event.block.timestamp;
  user.save();

  let protocol = getOrCreateProtocol();
  protocol.totalDebt = protocol.totalDebt.minus(event.params.amount);
  protocol.save();
}


export function handleLiquidated(event: Liquidated): void {
  let user = getOrCreateUser(event.params.user);
  user.collateral = user.collateral.minus(event.params.totalCollateralToRedeem);
  user.debt = user.debt.minus(event.params.debtToCover);
  user.lastUpdated = event.block.timestamp;
  user.save();

  // Create a Liquidation entity
  let liquidation = new Liquidation(
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString()
  );
  liquidation.user = user.id;
  liquidation.liquidator = event.params.liquidator;
  liquidation.debtCovered = event.params.debtToCover;
  liquidation.collateralSeized = event.params.totalCollateralToRedeem;
  liquidation.fee = event.params.protocolShare;
  liquidation.block = event.block.number;
  liquidation.timestamp = event.block.timestamp;
  liquidation.save();

  // Update protocol totals
  let protocol = getOrCreateProtocol();
  let collateralTakenOutOfProtocol = event.params.totalCollateralToRedeem.minus(event.params.protocolShare);
  protocol.totalCollateral = protocol.totalCollateral.minus(collateralTakenOutOfProtocol);
  protocol.totalDebt = protocol.totalDebt.minus(event.params.debtToCover);
  protocol.save();
}