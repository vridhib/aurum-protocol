import { newMockEvent } from "matchstick-as"
import { ethereum, Address, BigInt } from "@graphprotocol/graph-ts"
import {
  CollateralDeposited,
  CollateralRedeemed,
  Liquidated
} from "../generated/AurumEngine/AurumEngine"

export function createCollateralDepositedEvent(
  user: Address,
  amount: BigInt
): CollateralDeposited {
  let collateralDepositedEvent = changetype<CollateralDeposited>(newMockEvent())

  collateralDepositedEvent.parameters = new Array()

  collateralDepositedEvent.parameters.push(
    new ethereum.EventParam("user", ethereum.Value.fromAddress(user))
  )
  collateralDepositedEvent.parameters.push(
    new ethereum.EventParam("amount", ethereum.Value.fromUnsignedBigInt(amount))
  )

  return collateralDepositedEvent
}

export function createCollateralRedeemedEvent(
  redeemedFrom: Address,
  redeemedTo: Address,
  amount: BigInt
): CollateralRedeemed {
  let collateralRedeemedEvent = changetype<CollateralRedeemed>(newMockEvent())

  collateralRedeemedEvent.parameters = new Array()

  collateralRedeemedEvent.parameters.push(
    new ethereum.EventParam(
      "redeemedFrom",
      ethereum.Value.fromAddress(redeemedFrom)
    )
  )
  collateralRedeemedEvent.parameters.push(
    new ethereum.EventParam(
      "redeemedTo",
      ethereum.Value.fromAddress(redeemedTo)
    )
  )
  collateralRedeemedEvent.parameters.push(
    new ethereum.EventParam("amount", ethereum.Value.fromUnsignedBigInt(amount))
  )

  return collateralRedeemedEvent
}

export function createLiquidatedEvent(
  user: Address,
  liquidator: Address,
  debtToCover: BigInt,
  totalCollateralToRedeem: BigInt,
  protocolShare: BigInt
): Liquidated {
  let liquidatedEvent = changetype<Liquidated>(newMockEvent())

  liquidatedEvent.parameters = new Array()

  liquidatedEvent.parameters.push(
    new ethereum.EventParam("user", ethereum.Value.fromAddress(user))
  )
  liquidatedEvent.parameters.push(
    new ethereum.EventParam(
      "liquidator",
      ethereum.Value.fromAddress(liquidator)
    )
  )
  liquidatedEvent.parameters.push(
    new ethereum.EventParam(
      "debtToCover",
      ethereum.Value.fromUnsignedBigInt(debtToCover)
    )
  )
  liquidatedEvent.parameters.push(
    new ethereum.EventParam(
      "totalCollateralToRedeem",
      ethereum.Value.fromUnsignedBigInt(totalCollateralToRedeem)
    )
  )
  liquidatedEvent.parameters.push(
    new ethereum.EventParam(
      "protocolShare",
      ethereum.Value.fromUnsignedBigInt(protocolShare)
    )
  )

  return liquidatedEvent
}
