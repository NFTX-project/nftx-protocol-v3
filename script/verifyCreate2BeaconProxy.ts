import dotenv from "dotenv";
dotenv.config();
import { Etherscan } from "@nomicfoundation/hardhat-verify/etherscan";
import contractInfo from "../out/Create2BeaconProxy.sol/Create2BeaconProxy.json";

const contractAddressToVerify = "0xffE5d77309efd6e9391Ac14D95f2035A1e138659";

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

const main = async () => {
  console.log("script started...");

  const instance = new Etherscan(
    process.env.ETHERSCAN_API_KEY!, // Etherscan API key
    "https://api.etherscan.io/api", // Etherscan API URL
    "https://goerli.etherscan.io" // Etherscan browser URL
  );

  if (!(await instance.isVerified(contractAddressToVerify))) {
    console.log("verifying...");

    const { message: guid } = await instance.verify(
      // Contract address
      contractAddressToVerify,
      // Contract source code
      contractInfo.rawMetadata,
      // Contract name
      `${contractInfo.ast.absolutePath}:${
        contractInfo.metadata.settings.compilationTarget[
          contractInfo.ast.absolutePath
        ]
      }`,
      // Compiler version
      contractInfo.metadata.compiler.version,
      // Encoded constructor arguments
      ""
    );

    await sleep(1000);
    const verificationStatus = await instance.getVerificationStatus(guid);

    if (verificationStatus.isSuccess()) {
      const contractURL = instance.getContractUrl(contractAddressToVerify);
      console.log(
        `Successfully verified contract ${
          contractInfo.metadata.settings.compilationTarget[
            contractInfo.ast.absolutePath
          ]
        } on Etherscan: ${contractURL}`
      );
    }
  }
};

main();
