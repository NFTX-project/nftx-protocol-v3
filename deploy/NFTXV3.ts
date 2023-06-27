import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { utils } from "ethers";
import deployConfig from "../deployConfig";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, execute } = deployments;

  const { deployer } = await getNamedAccounts();
  const config = deployConfig[network.name];

  const positionManager = await deployments.get("NonfungiblePositionManager");
  const uniV3Factory = await deployments.get("UniswapV3FactoryUpgradeable");
  const router = await deployments.get("SwapRouter");
  const quoter = await deployments.get("QuoterV2");

  const vaultImpl = await deploy("NFTXVaultUpgradeableV3", {
    from: deployer,
    args: [config.WETH],
    log: true,
  });

  const vaultFactory = await deploy("NFTXVaultFactoryUpgradeableV3", {
    from: deployer,
    proxy: {
      proxyContract: "OpenZeppelinTransparentProxy",
      execute: {
        init: {
          methodName: "__NFTXVaultFactory_init",
          args: [
            vaultImpl.address,
            20 * 60, // twapInterval = 20 mins
            10 * 60 * 60, // premiumDuration = 10 hrs
            utils.parseEther("5"), // premiumMax = 5 ether
            utils.parseEther("0.30"), // depositorPremiumShare = 0.30 ether
          ],
        },
      },
    },
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
      2 * 24 * 60 * 60, // lpTimelock = 2 days
    ],
    log: true,
  });

  // NFTXRouter has in-built fee handling
  console.log("Setting fee exclusion for NFTXRouter...");
  await execute(
    "NFTXVaultFactoryUpgradeable",
    { from: deployer },
    "setFeeExclusion",
    nftxRouter.address,
    true
  );
  console.log("Fee exclusion set for NFTXRouter");

  const timelockExcludeList = await deploy("TimelockExcludeList", {
    from: deployer,
    log: true,
  });

  const inventoryStaking = await deploy("NFTXInventoryStakingV3Upgradeable", {
    from: deployer,
    args: [config.WETH, config.permit2, vaultFactory.address],
    proxy: {
      proxyContract: "OpenZeppelinTransparentProxy",
      execute: {
        init: {
          methodName: "__NFTXInventoryStaking_init",
          args: [
            2 * 24 * 60 * 60, // timelock = 2 days timelock
            utils.parseEther("0.05"), // penalty = 5%
            timelockExcludeList.address,
          ],
        },
      },
    },
    log: true,
  });
  console.log("Setting guardian on InventoryStaking...");
  await execute(
    "NFTXInventoryStakingV3Upgradeable",
    { from: deployer },
    "setIsGuardian",
    deployer,
    true
  );
  console.log("Set guardian on InventoryStaking");

  const feeDistributor = await deploy("NFTXFeeDistributorV3", {
    from: deployer,
    args: [
      vaultFactory.address,
      uniV3Factory.address,
      inventoryStaking.address,
      nftxRouter.address,
      config.treasury,
    ],
    log: true,
  });

  console.log("Setting FeeDistributor in UniV3Factory...");
  await execute(
    "UniswapV3FactoryUpgradeable",
    { from: deployer },
    "setFeeDistributor",
    feeDistributor.address
  );
  console.log("Set FeeDistributor in UniV3Factory");
  console.log("Setting FeeDistributor in NFTXVaultFactory...");
  await execute(
    "NFTXVaultFactoryUpgradeable",
    { from: deployer },
    "setFeeDistributor",
    feeDistributor.address
  );
  console.log("Set FeeDistributor in NFTXVaultFactory");

  const marketplaceZap = await deploy("MarketplaceUniversalRouterZap", {
    from: deployer,
    args: [
      vaultFactory.address,
      config.nftxUniversalRouter,
      config.permit2,
      inventoryStaking.address,
      config.WETH,
    ],
    log: true,
  });
};
export default func;
func.tags = ["NFTXV3"];
func.dependencies = ["UniV3", "Mocks"];
