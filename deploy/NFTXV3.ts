import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import deployConfig from "../deployConfig";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, execute } = deployments;

  const { deployer } = await getNamedAccounts();
  const config = deployConfig[network.name];

  const positionManager = await deployments.get("NonfungiblePositionManager");
  const router = await deployments.get("SwapRouter");
  const quoter = await deployments.get("QuoterV2");
  const weth = await deployments.get("MockWETH");
  const nft = await deployments.get("MockNFT");

  const vaultImpl = await deploy("NFTXVaultUpgradeable", {
    from: deployer,
    log: true,
  });

  const vaultFactory = await deploy("NFTXVaultFactoryUpgradeable", {
    from: deployer,
    log: true,
  });
  await execute(
    "NFTXVaultFactoryUpgradeable",
    { from: deployer },
    "__NFTXVaultFactory_init",
    vaultImpl.address,
    "0x0000000000000000000000000000000000000001" // FIXME: temporary feeDistributor address
  );

  const nftxRouter = await deploy("NFTXRouter", {
    from: deployer,
    args: [
      positionManager.address,
      router.address,
      quoter.address,
      vaultFactory.address,
    ],
    log: true,
  });

  // V2 currently deducts fees in vTokens which messes up with our calculations atm
  await execute(
    "NFTXVaultFactoryUpgradeable",
    { from: deployer },
    "setFeeExclusion",
    nftxRouter.address,
    true
  );

  const inventoryStaking = await deploy("MockInventoryStakingV3", {
    from: deployer,
    args: [vaultFactory.address, weth.address],
    log: true,
  });

  const feeDistributor = await deploy("NFTXFeeDistributorV3", {
    from: deployer,
    args: [inventoryStaking.address, nftxRouter.address, config.treasury],
    log: true,
  });

  await execute(
    "UniswapV3FactoryUpgradeable",
    { from: deployer },
    "setFeeDistributor",
    feeDistributor.address
  );
  await execute(
    "NFTXVaultFactoryUpgradeable",
    { from: deployer },
    "setFeeDistributor",
    feeDistributor.address
  );

  await execute(
    "NFTXVaultFactoryUpgradeable",
    { from: deployer },
    "createVault",
    "TEST",
    "TST",
    nft.address,
    false,
    true
  );
};
export default func;
func.tags = ["NFTXV3"];
func.dependencies = ["UniV3", "Mocks"];
