import { BigInt, Address } from "@graphprotocol/graph-ts";
import { CollateralDeposited, CollateralRedeemed, MintAUSD, BurnAUSD, Liquidated, TreasuryFeeSent, DebtAllocated, DebtDeallocated, ForceClosed, CumulativeIndexUpdated, LTVUpdated, CollateralInfoUpdated, DebtCeilingHit, CollateralSeized } from "../generated/AurumEngine/AurumEngine";
import { User, Protocol, Liquidation, TreasuryFee, UserCollateral, UserDebtAllocation, ForceClose, CumulativeIndexUpdate, LTVUpdate, CollateralInfoUpdate, DebtCeilingHitUpdate, CollateralSeizedUpdate } from "../generated/schema";


// ----------- Constants -----------
const AUR_ADDRESS = "0xda33e052c5719a608734a2063404cbdf97cce794";
const WETH_ADDRESS = "0xdd13E55209Fd76AfE204dBda4007C227904f0a81";


// ----------- Helpers -----------
function getOrCreateUser(userAddress: Address): User {
  let id = userAddress.toHexString();
  let user = User.load(id);
  if (!user) {
    user = new User(id);
    user.lastUpdated = BigInt.fromI32(0);
    user.lastIndex = BigInt.fromI32(1); // initial index 1e18
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
    protocol.totalAurCollateral = BigInt.fromI32(0);
    protocol.totalWethCollateral = BigInt.fromI32(0);
    protocol.totalNormalizedDebt = BigInt.fromI32(0);
    protocol.totalDebt = BigInt.fromI32(0);
    protocol.cumulativeIndex = BigInt.fromI32(1); // 1e18 scaled
    protocol.utilization = BigInt.fromI32(0);
    protocol.totalUsers = 0;
    protocol.lastUpdated = BigInt.fromI32(0);
  }
  return protocol;
}

function getUserCollateral(userId: string, token: Address): UserCollateral {
  let id = userId + "-" + token.toHexString();
  let uc = UserCollateral.load(id);
  if (!uc) {
    uc = new UserCollateral(id);
    uc.user = userId;
    uc.token = token;
    uc.amount = BigInt.fromI32(0);
  }
  return uc;
}

function getUserDebt(userId: string, token: Address): UserDebtAllocation {
  let id = userId + "-" + token.toHexString();
  let ud = UserDebtAllocation.load(id);
  if (!ud) {
    ud = new UserDebtAllocation(id);
    ud.user = userId;
    ud.token = token;
    ud.normalizedDebt = BigInt.fromI32(0);
  }
  return ud;
}


// ----------- Handlers -----------
export function handleCollateralDeposited(event: CollateralDeposited): void {
  let user = getOrCreateUser(event.params.user);
  let uc = getUserCollateral(user.id, event.params.token);
  uc.amount = uc.amount.plus(event.params.amount);
  uc.save();
  user.lastUpdated = event.block.timestamp;
  user.save();

  let protocol = getOrCreateProtocol();
  if (event.params.token.toHexString().toLowerCase() == AUR_ADDRESS.toLowerCase()) {
    protocol.totalAurCollateral = protocol.totalAurCollateral.plus(event.params.amount);
  } 
  else if (event.params.token.toHexString().toLowerCase() == WETH_ADDRESS.toLowerCase()) {
    protocol.totalWethCollateral = protocol.totalWethCollateral.plus(event.params.amount);
  }
  protocol.lastUpdated = event.block.timestamp;
  protocol.save();
}


export function handleCollateralRedeemed(event: CollateralRedeemed): void {
  let user = getOrCreateUser(event.params.redeemedFrom);
  let uc = getUserCollateral(user.id, event.params.token);
  uc.amount = uc.amount.minus(event.params.amount);
  uc.save();
  user.lastUpdated = event.block.timestamp;
  user.save();

  let protocol = getOrCreateProtocol();
  if (event.params.token.toHexString().toLowerCase() == AUR_ADDRESS.toLowerCase()) {
    protocol.totalAurCollateral = protocol.totalAurCollateral.minus(event.params.amount);
  } else if (event.params.token.toHexString().toLowerCase() == WETH_ADDRESS.toLowerCase()) {
    protocol.totalWethCollateral = protocol.totalWethCollateral.minus(event.params.amount);
  }
  protocol.lastUpdated = event.block.timestamp;
  protocol.save();
}


export function handleMintAUSD(event: MintAUSD): void {
  let user = getOrCreateUser(event.params.user);
  let protocol = getOrCreateProtocol();
  
  user.lastIndex = protocol.cumulativeIndex;
  user.lastUpdated = event.block.timestamp;
  user.save();

  protocol.totalDebt = protocol.totalDebt.plus(event.params.amount);
  protocol.lastUpdated = event.block.timestamp;
  protocol.save();
}


export function handleBurnAUSD(event: BurnAUSD): void {
  let user = getOrCreateUser(event.params.user);
  let protocol = getOrCreateProtocol();

  user.lastIndex = protocol.cumulativeIndex;
  user.lastUpdated = event.block.timestamp;
  user.save();

  protocol.totalDebt = protocol.totalDebt.minus(event.params.amount);
  protocol.lastUpdated = event.block.timestamp;
  protocol.save();
}


export function handleLiquidated(event: Liquidated): void {
  let user = getOrCreateUser(event.params.user);
  let uc = getUserCollateral(user.id, event.params.collateralToken);
  uc.amount = uc.amount.minus(event.params.totalCollateralToRedeem);
  uc.save();
  user.lastUpdated = event.block.timestamp;
  user.save();

  // Update protocol totals for that collateral
  let protocol = getOrCreateProtocol();
  if (event.params.collateralToken.toHexString().toLowerCase() == AUR_ADDRESS.toLowerCase()) {
    protocol.totalAurCollateral = protocol.totalAurCollateral.minus(event.params.totalCollateralToRedeem);
  } 
  else if (event.params.collateralToken.toHexString().toLowerCase() == WETH_ADDRESS.toLowerCase()) {
    protocol.totalWethCollateral = protocol.totalWethCollateral.minus(event.params.totalCollateralToRedeem);
  }  
  protocol.lastUpdated = event.block.timestamp;
  protocol.save();

  // Record liquidation event
  let liquidation = new Liquidation(event.transaction.hash.toHexString() + "-" + event.logIndex.toString());
  liquidation.user = user.id;
  liquidation.liquidator = event.params.liquidator;
  liquidation.debtToCover = event.params.debtToCover;
  liquidation.collateralToken = event.params.collateralToken;
  liquidation.totalCollateralToRedeem = event.params.totalCollateralToRedeem;
  liquidation.protocolShare = event.params.protocolShare;
  liquidation.block = event.block.number;
  liquidation.timestamp = event.block.timestamp;
  liquidation.save();
}


export function handleDebtAllocated(event: DebtAllocated): void {
  let user = getOrCreateUser(event.params.user);
  let ud = getUserDebt(user.id, event.params.token);
  ud.normalizedDebt = ud.normalizedDebt.plus(event.params.allocatedDebt);
  ud.save();
  user.lastUpdated = event.block.timestamp;
  user.save();

  let protocol = getOrCreateProtocol();
  protocol.totalNormalizedDebt = protocol.totalNormalizedDebt.plus(event.params.allocatedDebt);
  protocol.lastUpdated = event.block.timestamp;
  protocol.save();
}


export function handleDebtDeallocated(event: DebtDeallocated): void {
  let user = getOrCreateUser(event.params.user);
  let ud = getUserDebt(user.id, event.params.token);
  ud.normalizedDebt = ud.normalizedDebt.minus(event.params.debtReduction);
  ud.save();
  user.lastUpdated = event.block.timestamp;
  user.save();

  let protocol = getOrCreateProtocol();
  protocol.totalNormalizedDebt = protocol.totalNormalizedDebt.minus(event.params.debtReduction);
  protocol.lastUpdated = event.block.timestamp;
  protocol.save();
}


export function handleForceClosed(event: ForceClosed): void {
  let user = getOrCreateUser(event.params.user);
  let protocol = getOrCreateProtocol();

  // Clear all user collateral
  let aurUc = getUserCollateral(user.id, Address.fromString(AUR_ADDRESS));
  let wethUc = getUserCollateral(user.id, Address.fromString(WETH_ADDRESS));
  protocol.totalAurCollateral = protocol.totalAurCollateral.minus(aurUc.amount);
  protocol.totalWethCollateral = protocol.totalWethCollateral.minus(wethUc.amount);
  aurUc.amount = BigInt.fromI32(0);
  wethUc.amount = BigInt.fromI32(0);
  aurUc.save();
  wethUc.save();

  // Protocol debt reduction
  protocol.totalDebt = protocol.totalDebt.minus(event.params.debtAbsorbed);
  protocol.lastUpdated = event.block.timestamp;
  protocol.save();

  user.lastUpdated = event.block.timestamp;
  user.save();

  // Record event
  let forceClose = new ForceClose(event.transaction.hash.toHexString() + "-" + event.logIndex.toString());
  forceClose.user = user.id;
  forceClose.debtAbsorbed = event.params.debtAbsorbed;
  forceClose.collateralValueSeized = event.params.collateralValueSeized;
  forceClose.block = event.block.number;
  forceClose.timestamp = event.block.timestamp;
  forceClose.save();
}


export function handleCumulativeIndexUpdated(event: CumulativeIndexUpdated): void {
  let protocol = getOrCreateProtocol();
  protocol.cumulativeIndex = event.params.newIndex;
  protocol.utilization = event.params.utilization;
  protocol.lastUpdated = event.block.timestamp;
  protocol.save();

  let update = new CumulativeIndexUpdate(event.transaction.hash.toHexString() + "-" + event.logIndex.toString());
  update.newIndex = event.params.newIndex;
  update.utilization = event.params.utilization;
  update.timestamp = event.block.timestamp;
  update.save();
}


export function handleLtvUpdated(event: LTVUpdated): void {
  let update = new LTVUpdate(event.transaction.hash.toHexString() + "-" + event.logIndex.toString());
  update.token = event.params.token;
  update.newLtv = event.params.newLtv;
  update.timestamp = event.block.timestamp;
  update.save();
}


export function handleCollateralInfoUpdated(event: CollateralInfoUpdated): void {
  let update = new CollateralInfoUpdate(event.transaction.hash.toHexString() + "-" + event.logIndex.toString());
  update.token = event.params.token;
  update.volatilityFeed = event.params.volatilityFeed;
  update.newLtv = event.params.newLtv;
  update.newDebtCeiling = event.params.newDebtCeiling;
  update.isActive = event.params.isActive;
  update.timestamp = event.block.timestamp;
  update.save();
}


export function handleTreasuryFeeSent(event: TreasuryFeeSent): void {
  let update = new TreasuryFee(event.transaction.hash.toHexString() + "-" + event.logIndex.toString());
  update.treasury = event.params.treasury;
  update.token = event.params.token;
  update.tokenAmount = event.params.tokenAmount;
  update.timestamp = event.block.timestamp;
  update.save();
}


export function handleDebtCeilingHit(event: DebtCeilingHit): void {
  let update = new DebtCeilingHitUpdate(event.transaction.hash.toHexString() + "-" + event.logIndex.toString());
  update.token = event.params.token;
  update.totalNormalizedDebt = event.params.totalNormalizedDebt;
  update.allocatedDebt = event.params.allocatedDebt;
  update.timestamp = event.block.timestamp;
  update.save();
}


export function handleCollateralSeized(event: CollateralSeized): void {
  let update = new CollateralSeizedUpdate(event.transaction.hash.toHexString() + "-" + event.logIndex.toString());
  update.token = event.params.token;
  update.amount = event.params.amount;
  update.timestamp = event.block.timestamp;
  update.save();
}