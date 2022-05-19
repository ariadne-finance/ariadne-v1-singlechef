// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "../libraries/IRewarder.sol";

contract RewarderBrokenMock is IRewarder {
    function onIncentReward (uint256, address, address, uint256, uint256) override external {
        revert();
    }

    function pendingTokens(uint256 pid, address user, uint256 incentAmount) override external view returns (IERC20[] memory rewardTokens, uint256[] memory rewardAmounts){
        revert();
    }
}
