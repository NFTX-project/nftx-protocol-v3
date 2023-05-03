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
  const vaultFactory = await deployments.get("NFTXVaultFactoryUpgradeable");

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
};
export default func;
func.tags = ["NFTXRouter"];
// func.dependencies = ["UniV3", "Mocks"];
