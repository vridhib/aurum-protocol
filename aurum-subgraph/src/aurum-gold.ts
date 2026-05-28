import { GoldDeposited, GoldWithdrawn, GoldLoss } from "../generated/AurumGold/AurumGold"
import { GoldDeposited as GoldDepositedEntity, GoldWithdrawn as GoldWithdrawnEntity, GoldLoss as GoldLossEntity } from "../generated/schema"

export function handleGoldDeposited(event: GoldDeposited): void {
  let entity = new GoldDepositedEntity(event.transaction.hash.toHexString() + "-" + event.logIndex.toString());
  entity.to = event.params.to;
  entity.ouncesDeposited = event.params.ouncesDeposited;
  entity.tokensMinted = event.params.tokensMinted;
  entity.block = event.block.number;
  entity.timestamp = event.block.timestamp;
  entity.save();
}

export function handleGoldWithdrawn(event: GoldWithdrawn): void {
  let entity = new GoldWithdrawnEntity(event.transaction.hash.toHexString() + "-" + event.logIndex.toString());
  entity.to = event.params.to;
  entity.ouncesWithdrawn = event.params.ouncesWithdrawn;
  entity.tokensBurned = event.params.tokensBurned;
  entity.block = event.block.number;
  entity.timestamp = event.block.timestamp;
  entity.save();
}

export function handleGoldLoss(event: GoldLoss): void {
  let entity = new GoldLossEntity(event.transaction.hash.toHexString() + "-" + event.logIndex.toString());
  entity.reporter = event.params.reporter;
  entity.ouncesLost = event.params.ouncesLost;
  entity.block = event.block.number;
  entity.timestamp = event.block.timestamp;
  entity.save();
}