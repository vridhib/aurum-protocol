"use client";

import { useState, useEffect, useMemo } from "react";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { parseEther, formatEther, getAddress, decodeErrorResult } from "viem";
import aurumEngineJson from "@/abis/AurumEngine.json";
import aurumGoldJson from "@/abis/AurumGold.json";
import aurumAUSDJson from "@/abis/AurumUSD.json"; 
import aurumGoldFaucetJson from "@/abis/AurumGoldFaucet.json";


// Constants
const AURUM_ENGINE_ADDRESS = getAddress("0x57dd5e001cD51689cDA9F38Ca49D841923cD5012");
const AUR_GOLD_ADDRESS = getAddress("0x7769F56edC2a1882a51cec1d3c96F31482b5A241");
const AURUM_AUSD_ADDRESS = getAddress("0x9C707127B1c8ab786E23474BCa253948Bae1B452");
const AUR_FAUCET_ADDRESS = getAddress("0x25067322310e834498b1638423383b3e5603dd30");

const ONE = 10n ** 18n;                 // 1e18
const THRESHOLD = 80n;                  // LIQUIDATION_THRESHOLD
const PRECISION = 100n;                 // LIQUIDATION_PRECISION

/**
 * Computes the health factor after a proposed change.
 * Formula: (collateral * price * THRESHOLD) / (minted * PRECISION * ONE)
 * Returns a value where >= ONE means healthy.
 */
function calculateProjectedHealthFactor(collateralWei: bigint, mintedWei: bigint, pricePerAurWei: bigint): bigint {
  if (mintedWei === 0n) return ONE * 100n; 
  const usdValue = (collateralWei * pricePerAurWei) / ONE;
  const adjusted = (usdValue * THRESHOLD) / PRECISION;
  const projectedHealthFactor = (adjusted * ONE) / mintedWei;
  console.log("projectedHealthFactor: ", projectedHealthFactor);
  return projectedHealthFactor;
}

// Clears action related state errors on input change
function useClearErrorOnInputChange(
  setError: (error: string | null) => void,
  inputValue: string
) {
  useEffect(() => {
    setError(null);
  }, [inputValue, setError]);
}

function useWriteErrorHandler(
  error: unknown,
  setError: (msg: string | null) => void
) {
  useEffect(() => {
    if (error) {
      setError(getUserFriendlyErrorMessage(error));
    } else {
      setError(null);
    }
  }, [error, setError]);
}

// Validates an amount string and optionally checks against a maximum (in wei).
function useAmountValidation(amount: string, max?: bigint) {
  const isValid = useMemo(() => amount && parseFloat(amount) > 0, [amount]);
  const exceeds = useMemo(() => {
    if (!isValid || max === undefined) return false;
    return parseEther(amount) > max;
  }, [amount, max, isValid]);
  return { isValid, exceeds };
}

// Gets user friendly error messages
function getUserFriendlyErrorMessage(error: unknown): string {
  if (error instanceof Error && error.message.includes("User rejected")) {
    return "Transaction was rejected in your wallet.";
  }

  try {
    const cause = (error as any).cause;
    if (cause?.data) {
      const decoded = decodeErrorResult({
        abi: aurumEngineJson.abi,
        data: cause.data,
      });
      switch (decoded.errorName) {
        case "AurumEngine__ExceedsMaxSupply":
          return "Cannot mint more than the maximum supply of AUSD.";
        default:
          return `Contract error: ${decoded.errorName}`;
      }
    }
  } catch (e) {}
  return error instanceof Error ? error.message : "An unknown error occurred.";
}



export default function Dashboard() {
  const { address, isConnected } = useAccount();

  // State for amounts
  const [depositAmount, setDepositAmount] = useState("");
  const [redeemAmount, setRedeemAmount] = useState("");
  const [mintAmount, setMintAmount] = useState("");
  const [burnAmount, setBurnAmount] = useState("");
  const [pendingDepositAmount, setPendingDepositAmount] = useState<bigint | null>(null);
  const [pendingBurnAmount, setPendingBurnAmount] = useState<bigint | null>(null);
  const [pendingAction, setPendingAction] = useState<string | null>(null);
  const [depositError, setDepositError] = useState<string | null>(null);
  const [redeemError, setRedeemError] = useState<string | null>(null);
  const [mintError, setMintError] = useState<string | null>(null);
  const [burnError, setBurnError] = useState<string | null>(null);
 

  // Read: Collateral deposited
  const {data: amountCollateral, isLoading: isCollateralLoading, refetch: refetchCollateral} = useReadContract({
    address: AURUM_ENGINE_ADDRESS,
    abi: aurumEngineJson.abi,
    functionName: "getAmountCollateral",
    args: [address],
    //query: { enabled: !!address },
    query: { enabled: !!address, select: (data) => data as bigint }
  });

  // Read: Minted AUSD
  const {data: mintedAmount, isLoading: isDebtLoading, refetch: refetchMinted} = useReadContract({
    address: AURUM_ENGINE_ADDRESS,
    abi: aurumEngineJson.abi,
    functionName: "getAUSDMinted",
    args: [address],
    //query: { enabled: !!address },
    query: { enabled: !!address, select: (data) => data as bigint }
  });

  // Read: Health Factor
  const {data: healthFactor, isLoading: isHealthFactorLoading, refetch: refetchHealthFactor} = useReadContract({
    address: AURUM_ENGINE_ADDRESS,
    abi: aurumEngineJson.abi,
    functionName: "getHealthFactor",
    args: [address],
    query: { enabled: !!address },
  });

  // Read: Current AUR Price
  const {data: pricePerAur} = useReadContract({
    address: AURUM_ENGINE_ADDRESS,
    abi: aurumEngineJson.abi,
    functionName: "getUsdValue",
    args: [parseEther("1")],
    query: { enabled: !!address, select: (data) => data as bigint }
  });

  // Read: AUR Faucet lastClaimTime
  const {data: lastClaimTime} = useReadContract({
    address: AUR_FAUCET_ADDRESS,
    abi: aurumGoldFaucetJson.abi,
    functionName: "lastClaimTime",
    args: [address],
    query: { enabled: !!address },
  });
  const canClaim = lastClaimTime ? Date.now() / 1000 > Number(lastClaimTime) + 86400 : true;

  // Read: AUR allowance for the Engine
  const {data: aurAllowance, refetch: refetchAURAllowance} = useReadContract({
    address: AUR_GOLD_ADDRESS,
    abi: aurumGoldJson.abi,
    functionName: "allowance",
    args: [address, AURUM_ENGINE_ADDRESS],
    query: { enabled: !!address, select: (data) => data as bigint }
  });

  // Read: AUSD allowance for the Engine
  const {data: ausdAllowance, refetch: refetchAUSDAllowance} = useReadContract({
    address: AURUM_AUSD_ADDRESS,
    abi: aurumAUSDJson.abi,
    functionName: "allowance",
    args: [address, AURUM_ENGINE_ADDRESS],
    query: { enabled: !!address },
  });

  // Write: Deposit Collateral (AUR)
  const { data: depositHash, isPending: isDepositPending, writeContract: deposit, error: depositWriteError } = useWriteContract();
  const { isLoading: isDepositConfirming, isSuccess: isDepositSuccess } =
    useWaitForTransactionReceipt({ hash: depositHash });

  // Write: Redeem Collateral (AUR)
  const { data: redeemHash, isPending: isRedeemPending, writeContract: redeem, error: redeemWriteError } = useWriteContract();
  const {isLoading: isRedeemConfirming, isSuccess: isRedeemSuccess } =
    useWaitForTransactionReceipt({ hash: redeemHash });

  // Write: Mint AUSD
  const { data: mintHash, isPending: isMintPending, writeContract: mint, error: mintWriteError } = useWriteContract();
  const { isLoading: isMintConfirming, isSuccess: isMintSuccess } =
    useWaitForTransactionReceipt({ hash: mintHash });

  // Write: Burn AUSD
  const {data: burnHash, isPending: isBurnPending, writeContract: burn, error: burnWriteError } = useWriteContract();
  const {isLoading: isBurnConfirming, isSuccess: isBurnSuccess } = useWaitForTransactionReceipt({ hash: burnHash });

  // Write: Claim AUR Faucet Funds
  const {data: claimHash, isPending: isClaimPending, writeContract: claim } = useWriteContract();
  const {isLoading: isClaimConfirming, isSuccess: isClaimSuccess} = useWaitForTransactionReceipt({ hash: claimHash});

  // Write: Approve AUR
  const { data: approveAURHash, isPending: isApproveAURPending, writeContract: approveAUR } = useWriteContract();
  const { isLoading: isApproveAURConfirming, isSuccess: isApproveAURSuccess } =
    useWaitForTransactionReceipt({ hash: approveAURHash });

  // Write: Approve AUSD 
  const { data: approveAUSDHash, isPending: isApproveAUSDPending, writeContract: approveAUSD } = useWriteContract();
  const { isLoading: isApproveAUSDConfirming, isSuccess: isApproveAUSDSuccess } =
    useWaitForTransactionReceipt({ hash: approveAUSDHash });

  const isAnyTxPending = 
  isDepositPending || isDepositConfirming ||
  isRedeemPending || isRedeemConfirming ||
  isMintPending || isMintConfirming ||
  isBurnPending || isBurnConfirming ||
  isApproveAURPending || isApproveAURConfirming ||
  isApproveAUSDPending || isApproveAUSDConfirming;

  
  /***************************************************/
  /**********Compute Projected Health Factor**********/
  /***************************************************/
  // Check if mintAmount keeps the user's health factor healthy
  const mintWouldBeHealthy = useMemo(() => {
    if (!mintAmount || parseFloat(mintAmount) <= 0) return true;
    if (amountCollateral === undefined || mintedAmount === undefined || pricePerAur === undefined) return false;

    const mintWei = parseEther(mintAmount);
    const newMinted = (mintedAmount as bigint) + mintWei;
    const collateral = amountCollateral as bigint;
    const price = pricePerAur as bigint;

    const projectedHealthFactor = calculateProjectedHealthFactor(collateral, newMinted, price);
    return projectedHealthFactor >= ONE;
  }, [mintAmount, amountCollateral, mintedAmount, pricePerAur]);

  // Check if redeemAmount keeps the user's health factor healthy
  const redeemWouldBeHealthy = useMemo(() => {
    if (!redeemAmount || parseFloat(redeemAmount) <= 0) return true;
    if (amountCollateral === undefined || mintedAmount === undefined || pricePerAur === undefined) return false;

    const redeemWei = parseEther(redeemAmount);
    const newCollateral = (amountCollateral as bigint) - redeemWei;
    const minted = mintedAmount as bigint;
    const price = pricePerAur as bigint;

    if (minted === 0n) return true;
    const projectedHealthFactor = calculateProjectedHealthFactor(newCollateral, minted, price);
    return projectedHealthFactor >= ONE;
  }, [redeemAmount, amountCollateral, mintedAmount, pricePerAur]);


  /***************************************************/
  /*********************useEffect*********************/
  /***************************************************/
  // If the user removed the bad/invalid number remove the error
  useClearErrorOnInputChange(setDepositError, depositAmount);
  useClearErrorOnInputChange(setRedeemError, redeemAmount);
  useClearErrorOnInputChange(setMintError, mintAmount);
  useClearErrorOnInputChange(setBurnError, burnAmount);

  // Handle post transaction write errors
  useWriteErrorHandler(depositWriteError, setDepositError);
  useWriteErrorHandler(redeemWriteError, setRedeemError);
  useWriteErrorHandler(mintWriteError, setMintError);
  useWriteErrorHandler(burnWriteError, setBurnError);

  // Refetch data after successful deposit 
  useEffect(() => {
    if (isDepositSuccess) {
      setPendingAction(null);  
      refetchCollateral();
      refetchAURAllowance();
      refetchHealthFactor();
      setDepositAmount("");
      setPendingDepositAmount(null);
    }
  }, [isDepositSuccess, refetchCollateral, refetchAURAllowance, refetchHealthFactor]);

  // Refetch data after successful redeem
  useEffect(() => {
    if (isRedeemSuccess) {  
      setPendingAction(null);
      refetchCollateral();
      refetchHealthFactor();
      setRedeemAmount("");
    }
  }, [isRedeemSuccess, refetchCollateral, refetchHealthFactor]);

  // Refetch data after successful mint
  useEffect(() => {
    if (isMintSuccess) {
      setPendingAction(null);
      refetchMinted();
      refetchHealthFactor();
      setMintAmount("");
    }
  }, [isMintSuccess, refetchMinted, refetchHealthFactor]);

  // Refetch data after successful burn
  useEffect(() => {
    if (isBurnSuccess) {
      setPendingAction(null);
      refetchMinted();
      setBurnAmount("");
      setPendingBurnAmount(null);
      refetchAUSDAllowance();
      refetchHealthFactor();
    }
  }, [isBurnSuccess, refetchMinted, refetchAUSDAllowance, refetchHealthFactor]);

  // After AUR (collateral) approval succeeds, automatically deposit the pending amount
  useEffect(() => {
    if (isApproveAURSuccess && pendingDepositAmount !== null) {
      setPendingAction("Depositing AUR...");
      deposit({
        address: AURUM_ENGINE_ADDRESS,
        abi: aurumEngineJson.abi,
        functionName: "depositCollateral",
        args: [pendingDepositAmount],
      });
    }
  }, [isApproveAURSuccess, pendingDepositAmount, deposit]);

  // After AUSD approval succeeds, automatically burn the pending amount
  useEffect(() => {
    if (isApproveAUSDSuccess && pendingBurnAmount !== null) {
      setPendingAction("Burning AUSD...");
      burn({
        address: AURUM_ENGINE_ADDRESS,
        abi: aurumEngineJson.abi,
        functionName: "burnAUSD",
        args: [pendingBurnAmount],
      });
    }
  }, [isApproveAUSDSuccess, pendingBurnAmount, burn]);


  /***************************************************/
  /*********************Handlers**********************/
  /***************************************************/
  // Deposit handler
  const { isValid: isDepositAmountValid } = useAmountValidation(depositAmount);
  const handleDeposit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (!isDepositAmountValid) return;

    const amountWei = parseEther(depositAmount);
    if (aurAllowance !== undefined && aurAllowance < amountWei) {
      setPendingDepositAmount(amountWei);
      setPendingAction("Approving deposit...");
      approveAUR({
        address: AUR_GOLD_ADDRESS,
        abi: aurumGoldJson.abi,
        functionName: "approve",
        args: [AURUM_ENGINE_ADDRESS, amountWei],
      });
    } else {
      setPendingDepositAmount(amountWei);
      setPendingAction("Depositing AUR...");
      deposit({
        address: AURUM_ENGINE_ADDRESS,
        abi: aurumEngineJson.abi,
        functionName: "depositCollateral",
        args: [amountWei],
      });
    }
  };


  // Redeem handler
  const { isValid: isRedeemAmountValid, exceeds: doesRedeemExceedCollateral } = useAmountValidation(redeemAmount, amountCollateral);
  const handleRedeem = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (!isRedeemAmountValid || doesRedeemExceedCollateral) return;

    const amountWei = parseEther(redeemAmount);
    setPendingAction("Redeeming AUR...");
    redeem({
      address: AURUM_ENGINE_ADDRESS,
      abi: aurumEngineJson.abi,
      functionName: "redeemCollateral",
      args: [amountWei],
    });
  };


  // Mint handler
  const { isValid: isMintAmountValid } = useAmountValidation(mintAmount);
  const handleMint = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (!isMintAmountValid) return;

    const amountWei = parseEther(mintAmount);
    setPendingAction("Minting AUSD...");
    mint({
      address: AURUM_ENGINE_ADDRESS,
      abi: aurumEngineJson.abi,
      functionName: "mintAUSD", 
      args: [amountWei],
    });
  };


  // Burn handler
  const { isValid: isBurnAmountValid, exceeds: doesBurnExceedMinted } = useAmountValidation(burnAmount, mintedAmount);
  const handleBurn = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (!isBurnAmountValid || doesBurnExceedMinted) return;

    const amountWei = parseEther(burnAmount);
    if (ausdAllowance !== undefined && (ausdAllowance as bigint) < amountWei) {
      setPendingBurnAmount(amountWei);
      setPendingAction("Approving AUSD...");
      approveAUSD({
        address: AURUM_AUSD_ADDRESS,
        abi: aurumAUSDJson.abi,
        functionName: "approve",
        args: [AURUM_ENGINE_ADDRESS, amountWei],
      });
    } else {
      setPendingBurnAmount(amountWei);
      setPendingAction("Burning AUSD...");
      burn({
        address: AURUM_ENGINE_ADDRESS,
        abi: aurumEngineJson.abi,
        functionName: "burnAUSD",
        args: [amountWei],
      });
    }
  };


  // Claim AUR from faucet handler
  const handleClaim = () => {
    setPendingAction("Claiming AUR from faucet...")
    claim({
      address: AUR_FAUCET_ADDRESS,
      abi: aurumGoldFaucetJson.abi,
      functionName: "claim"
    });
  };

  /***************************************************/
  /**************Determine Button States**************/
  /***************************************************/
  // Determine deposit button state
  const isDepositButtonDisabled =
    !isDepositAmountValid || !!depositError ||
    isDepositPending || isDepositConfirming ||
    isApproveAURPending || isApproveAURConfirming;

  // Determine redeem button state
  const isRedeemButtonDisabled =
    !isRedeemAmountValid || doesRedeemExceedCollateral || 
    !!redeemError || 
    isRedeemPending || isRedeemConfirming || 
    !redeemWouldBeHealthy;

  // Determine mint button state
  const isMintButtonDisabled =
    !isMintAmountValid || !!mintError ||
    isMintPending || isMintConfirming ||
    !mintWouldBeHealthy;

  // Determine burn button state
  const isBurnButtonDisabled =
    !isBurnAmountValid || doesBurnExceedMinted ||
    !!burnError ||
    isBurnPending || isBurnConfirming ||
    isApproveAUSDPending || isApproveAUSDConfirming;

  // Determine whether to display dashboard components
  if (!isConnected) {
    return (
      <div className="flex items-center justify-center h-96 text-gray-400">
        Please connect your wallet to view the dashboard.
      </div>
    );
  }


/***************************************************/
/******************Main Component*******************/
/***************************************************/
  return (
    <div className="max-w-7xl mx-auto p-6 space-y-8">
      {/* Header */}
      <div className="flex justify-between items-center border-b border-gray-800 pb-6">
        <div>
          <h1 className="text-3xl font-bold tracking-tight text-white">Dashboard</h1>
          <p className="text-gray-400 text-sm">Manage your Aurum positions</p>
        </div>
        
        <div className="flex items-center gap-2">
          {isAnyTxPending && (
            <div className="flex items-center text-yellow-400">
              <LoadingSpinner />
              <span className="ml-2 text-sm">{pendingAction}</span>
            </div>
          )}
        
        <button
          onClick={() => {
            refetchCollateral();
            refetchAURAllowance();
            refetchAUSDAllowance();
            refetchMinted();
            refetchHealthFactor();
          }}
          className="px-4 py-2 bg-gray-800 hover:bg-gray-700 rounded-lg text-sm transition"
        >
          Refresh Data
        </button>

        <button
          onClick={handleClaim}
          disabled={!canClaim || isClaimPending || isClaimConfirming}
          className="px-4 py-2 bg-yellow-600 hover:bg-yellow-700 rounded-lg text-sm"
        >
          Get Test AUR
        </button>
      </div>
    </div>

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <StatCard
          title="Collateral Deposited"
          value={isCollateralLoading ? "Loading..." : `${formatEther(amountCollateral || 0n)} AUR`}
        />
        <StatCard
          title="AUSD Minted"
          value={isDebtLoading ? "Loading..." : `${formatEther(mintedAmount || 0n)} AUSD`}
        />
        <StatCard 
          title="Health Factor" 
          value={isHealthFactorLoading ? "Loading..." : Number(formatEther((healthFactor as bigint) || 0n)).toFixed(2)}
        />
      </div>

      {/* Actions */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Deposit Card */}
        <form onSubmit={handleDeposit} className="bg-gray-800 border border-gray-700 p-6 rounded-xl shadow-sm space-y-4">
          <h3 className="text-xl font-bold text-white">Deposit Collateral</h3>
          <input
            type="number"
            placeholder="0.00"
            step="0.01"
            value={depositAmount}
            onChange={(e) => setDepositAmount(e.target.value)}
            className="w-full p-3 bg-gray-900 border border-gray-700 rounded-lg text-white focus:ring-2 focus:ring-blue-500 outline-none transition"
          />
          <button
            type="submit"
            disabled={isDepositButtonDisabled}
            className="w-full bg-blue-600 hover:bg-blue-700 text-white font-bold py-3 px-4 rounded-lg transition disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Deposit
          </button>
          {!!depositAmount && !isDepositAmountValid && (<p className="text-red-500 text-sm">Please enter a valid amount greater than 0.</p>)}
          {depositError && <p className="text-red-500 text-sm">{depositError}</p>}
        </form>
 
        {/* Redeem Card */}
        <form onSubmit={handleRedeem} className="bg-gray-800 border border-gray-700 p-6 rounded-xl shadow-sm space-y-4">
          <h3 className="text-xl font-bold text-white">Redeem Collateral</h3>
          <input
            type="number"
            placeholder="0.00"
            step="0.01"
            value={redeemAmount}
            onChange={(e) => setRedeemAmount(e.target.value)}
            className="w-full p-3 bg-gray-900 border border-gray-700 rounded-lg text-white focus:ring-2 focus:ring-blue-500 outline-none transition"
          />
          <button
            type="submit"
            disabled={isRedeemButtonDisabled}
            className="w-full bg-blue-600 hover:bg-blue-700 text-white font-bold py-3 px-4 rounded-lg transition disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Redeem
          </button>
          {!!redeemAmount && !isRedeemAmountValid && (<p className="text-red-500 text-sm">Please enter a valid amount greater than 0.</p>)}
          {isRedeemAmountValid && doesRedeemExceedCollateral && (<p className="text-red-500 text-sm">Cannot redeem more than your deposited collateral.</p>)}
          {!redeemWouldBeHealthy && (<p className="text-red-500 text-sm">Redeeming this amount would put your health factor below 1.</p>)}
        </form>

        {/* Mint Card */}
        <form onSubmit={handleMint} className="bg-gray-800 border border-gray-700 p-6 rounded-xl shadow-sm space-y-4">
          <h3 className="text-xl font-bold text-white">Mint AUSD</h3>
          <input
            type="number"
            placeholder="0.00"
            step="0.01"
            value={mintAmount}
            onChange={(e) => setMintAmount(e.target.value)}
            className="w-full p-3 bg-gray-900 border border-gray-700 rounded-lg text-white focus:ring-2 focus:ring-blue-500 outline-none transition"
          />
          <button
            type="submit"
            disabled={isMintButtonDisabled}
            className="w-full bg-green-600 hover:bg-green-700 text-white font-bold py-3 px-4 rounded-lg transition disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Mint
          </button>
          {!!mintAmount && !isMintAmountValid && (<p className="text-red-500 text-sm">Please enter a valid amount greater than 0.</p>)}
          {!mintWouldBeHealthy && (<p className="text-red-500 text-sm">Minting this amount would put your health factor below 1.</p>)}
          {mintError && <p className="text-red-500 text-sm">{mintError}</p>}
        </form>

        {/* Burn Card */}
        <form onSubmit={handleBurn} className="bg-gray-800 border border-gray-700 p-6 rounded-xl shadow-sm space-y-4">
          <h3 className="text-xl font-bold text-white">Burn AUSD</h3>
          <input
            type="number"
            placeholder="0.00"
            step="0.01"
            value={burnAmount}
            onChange={(e) => setBurnAmount(e.target.value)}
            className="w-full p-3 bg-gray-900 border border-gray-700 rounded-lg text-white focus:ring-2 focus:ring-blue-500 outline-none transition"
          />
          <button
            type="submit"
            disabled={isBurnButtonDisabled}
            className="w-full bg-green-600 hover:bg-green-700 text-white font-bold py-3 px-4 rounded-lg transition disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Burn
          </button>
          {!!burnAmount && !isBurnAmountValid && (<p className="text-red-500 text-sm">Please enter a valid amount greater than 0.</p>)}
          {isBurnAmountValid && doesBurnExceedMinted && (<p className="text-red-500 text-sm">Cannot burn more AUSD than your minted AUSD.</p>)}
          {burnError && <p className="text-red-500 text-sm">{burnError}</p>}
        </form>
      </div>
    </div>
  );
}

/***************************************************/
/*****************Helper Components*****************/
/***************************************************/
function LoadingSpinner() {
  return (
    <div className="inline-block h-4 w-4 animate-spin rounded-full border-2 border-solid border-current border-r-transparent align-[-0.125em] motion-reduce:animate-[spin_1.5s_linear_infinite]" role="status">
      <span className="!absolute !-m-px !h-px !w-px !overflow-hidden !whitespace-nowrap !border-0 !p-0 ![clip:rect(0,0,0,0)]">Loading...</span>
    </div>
  );
}

function StatCard({ title, value }: { title: string; value: string }) {
  return (
    <div className="bg-gray-800 border border-gray-700 p-6 rounded-xl shadow-sm">
      <h3 className="text-gray-400 font-medium">{title}</h3>
      <p className="text-2xl font-mono text-white mt-2">{value}</p>
    </div>
  );
}