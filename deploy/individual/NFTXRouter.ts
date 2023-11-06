import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { utils } from "ethers";
import deployConfig from "../../deployConfig";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, execute } = deployments;

  const { deployer } = await getNamedAccounts();
  const config = deployConfig[network.name];

  const vaultFactory = await deployments.get("NFTXVaultFactoryUpgradeableV3");
  const positionManager = await deployments.get("NonfungiblePositionManager");
  const inventoryStaking = await deployments.get(
    "NFTXInventoryStakingV3Upgradeable"
  );
  const router = await deployments.get("SwapRouter");
  const quoter = await deployments.get("QuoterV2");

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
  console.log("Setting fee exclusion for NFTXRouter...");
  await execute(
    "NFTXVaultFactoryUpgradeableV3",
    { from: deployer },
    "setFeeExclusion",
    nftxRouter.address,
    true
  );
  console.log("Fee exclusion set for NFTXRouter");

  // ==
  console.log("Setting NFTXRouter in FeeDistributor...");
  await execute(
    "NFTXFeeDistributorV3",
    { from: deployer },
    "setNFTXRouter",
    nftxRouter.address
  );
  console.log("NFTXRouter set in FeeDistributor");
};
export default func;
func.tags = ["NFTXRouter"];
