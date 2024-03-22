// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {Test} from "forge-std/Test.sol";

contract TestExtend is Test {
    bytes constant OWNABLE_NOT_OWNER_ERROR = "Ownable: caller is not the owner";

    function assertEqUint24(
        uint24 a,
        uint24 b,
        string memory err
    ) internal virtual {
        assertEq(keccak256(abi.encode(a)), keccak256(abi.encode(b)), err);
    }

    function assertEqInt24(
        int24 a,
        int24 b,
        string memory err
    ) internal virtual {
        assertEq(keccak256(abi.encode(a)), keccak256(abi.encode(b)), err);
    }
}
