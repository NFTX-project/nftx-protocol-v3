import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { utils } from "ethers";
import deployConfig from "../../deployConfig";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, execute } = deployments;

  const { deployer } = await getNamedAccounts();
  const config = deployConfig[network.name];

  const descriptor = await deployments.get(
    "NonfungibleTokenPositionDescriptor"
  );
  const factory = await deployments.get("UniswapV3FactoryUpgradeable");
  const router = await deployments.get("SwapRouter");
  const quoter = await deployments.get("QuoterV2");
  const vaultFactory = await deployments.get("NFTXVaultFactoryUpgradeableV3");
  const inventoryStaking = await deployments.get(
    "NFTXInventoryStakingV3Upgradeable"
  );
  const uniV3Factory = await deployments.get("UniswapV3FactoryUpgradeable");

  const positionManager = await deploy("NonfungiblePositionManager", {
    from: deployer,
    args: [factory.address, config.WETH, descriptor.address],
    log: true,
  });

  const nftxRouter = await deploy("NFTXRouter", {
    from: deployer,
    args: [
      positionManager.address,
      router.address,
      quoter.address,
      vaultFactory.address,
      config.permit2,
      config.lpTimelock,
      config.lpEarlyWithdrawPenaltyInWei,
      config.nftxRouterVTokenDustThreshold,
      inventoryStaking.address,
    ],
    log: true,
  });

  // NFTXRouter has in-built fee handling
  // console.log("Setting fee exclusion for NFTXRouter...");
  // await execute(
  //   "NFTXVaultFactoryUpgradeableV3",
  //   { from: deployer },
  //   "setFeeExclusion",
  //   nftxRouter.address,
  //   true
  // );
  // console.log("Fee exclusion set for NFTXRouter");

  console.log(
    "Setting timelock exclusion for NFTXRouter on positionManager..."
  );
  await execute(
    "NonfungiblePositionManager",
    { from: deployer },
    "setTimelockExcluded",
    nftxRouter.address,
    true
  );
  console.log("Timelock exclusion set for NFTXRouter on positionManager");

  const createVaultZap = await deploy("CreateVaultZap", {
    from: deployer,
    args: [nftxRouter.address, uniV3Factory.address, inventoryStaking.address],
    log: true,
  });

  // CreateVaultZap doesn't deduct fees
  console.log("Setting fee exclusion for CreateVaultZap...");
  await execute(
    "NFTXVaultFactoryUpgradeableV3",
    { from: deployer },
    "setFeeExclusion",
    createVaultZap.address,
    true
  );
  console.log("Fee exclusion set for CreateVaultZap");
};
export default func;
func.tags = ["NFPM"];
