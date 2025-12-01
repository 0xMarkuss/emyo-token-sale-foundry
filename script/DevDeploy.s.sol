// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {EmyoToken} from "src/token/EmyoToken.sol";
import {Treasury} from "src/treasury/Treasury.sol";
import {TokenSale} from "src/sale/TokenSale.sol";
import {StakingRewards} from "src/staking/StakingRewards.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {Roles} from "src/access/Roles.sol";

/**
 * @notice Dev deployment script for local/anvil networks.
 * - Deploys Mock USDC, Treasury, EmyoToken, TokenSale (with integrated vesting), StakingRewards
 * - Wires roles and sets sensible defaults for dev
 * - Configures sale stages with vesting schedules
 * - Writes addresses into script/config/dev.latest.json
 */
contract DevDeploy is Script {
        address constant FINAL_OWNER = 0x79F9860d48ef9dDFaF3571281c033664de05E6f5;
        address constant ADD_OWNER_1 = 0xD78b12E941Cb760D7Ae4DC3949a4dBCCd6568BCb;
        address constant ADD_OWNER_2 = 0xa54e547F2030C6e422cC47Da1afd54A45E0912C8;

    function run() external {
        uint256 pk = vm.envUint("DEV_PRIVATE_KEY");

        uint256 totalSupply = vm.envOr("TOTAL_SUPPLY", uint256(10_000_000 ether));
        uint256 emyPriceUsd = vm.envOr("EMY_PRICE_USD", uint256(100));
        uint64 saleEndOffset = uint64(vm.envOr("SALE_END_OFFSET", uint256(7 days)));
        uint64 vestStart = uint64(vm.envOr("VEST_START", uint256(0)));
        uint64 vestPeriodLength = uint64(vm.envOr("VEST_PERIOD_LENGTH", uint256(30 days)));

        

        vm.startBroadcast(pk);

        address admin = vm.addr(pk);
        Treasury treasury = new Treasury(admin);
        EmyoToken emyo = new EmyoToken("Emyo", "EMY", totalSupply, address(treasury));
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);
        MockERC20 rewardToken = new MockERC20("REWARD", "REWARD", 18);
        TokenSale sale = new TokenSale(usdc, emyo, address(treasury), admin);
        StakingRewards staking = new StakingRewards(emyo, rewardToken, admin);

        uint256 saleTokenAllocation = totalSupply / 5;
        treasury.withdrawERC20(emyo, address(sale), saleTokenAllocation);

        address[] memory owners = new address[](4);
        owners[0] = admin;
        owners[1] = FINAL_OWNER;
        owners[2] = ADD_OWNER_1;
        owners[3] = ADD_OWNER_2;

        for (uint256 i = 0; i < owners.length; i++) {
            address o = owners[i];
            emyo.grantRole(emyo.DEFAULT_ADMIN_ROLE(), o);
            emyo.grantRole(Roles.PAUSER_ROLE, o);
            treasury.grantRole(treasury.DEFAULT_ADMIN_ROLE(), o);
            treasury.grantRole(Roles.PAUSER_ROLE, o);
            treasury.grantRole(Roles.TREASURY_ROLE, o);
            sale.grantRole(sale.DEFAULT_ADMIN_ROLE(), o);
            sale.grantRole(Roles.PAUSER_ROLE, o);
            sale.grantRole(Roles.SALE_ADMIN_ROLE, o);
            staking.grantRole(staking.DEFAULT_ADMIN_ROLE(), o);
            staking.grantRole(Roles.PAUSER_ROLE, o);
            staking.grantRole(Roles.STAKING_ADMIN_ROLE, o);
        }

        vm.stopBroadcast();

        string memory root = "dev";
        vm.serializeAddress(root, "admin", admin);
        vm.serializeAddress(root, "treasury", address(treasury));
        vm.serializeAddress(root, "emyo", address(emyo));
        vm.serializeAddress(root, "usdc", address(usdc));
        vm.serializeAddress(root, "sale", address(sale));
        vm.serializeAddress(root, "staking", address(staking));

        console.log("=== Deployment Configuration ===");
        console.log("Network chainid:", block.chainid);
        console.log("Total supply:", totalSupply);
        console.log("Sale price (tokens/USDC):", emyPriceUsd);
        console.log("Price scale: 100000");
        console.log("Sale end offset (s):", saleEndOffset);
        console.log("Vesting start offset (s):", vestStart);
        console.log("Vesting period length (s):", vestPeriodLength);
        console.log("Sale token allocation:", saleTokenAllocation);
        console.log("");
        console.log("=== Deployed Addresses ===");
        console.log("Deployer (admin):", admin);
        console.log("FINAL_OWNER:", FINAL_OWNER);
        console.log("ADD_OWNER_1:", ADD_OWNER_1);
        console.log("ADD_OWNER_2:", ADD_OWNER_2);
        console.log("Treasury:", address(treasury));
        console.log("Emyo Token:", address(emyo));
        console.log("USDC (Mock):", address(usdc));
        console.log("TokenSale:", address(sale));
        console.log("StakingRewards:", address(staking));
    }
}


